import AppKit
import Defaults
import Foundation
import KeyboardShortcuts
import OSLog

enum AppConfigStore {
    private static let directoryName = "ObsidianSideNote"
    private static let fileName = "config.json"
    static var configURLOverride: URL?

    static var configURL: URL {
        if let configURLOverride {
            return configURLOverride
        }

        if isRunningUnderXCTest {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("ObsidianSideNoteTests", isDirectory: true)
                .appendingPathComponent("config.json")
        }

        if isRunningInUITest {
            if let path = ProcessInfo.processInfo.environment["OSN_TEST_CONFIG_URL"], !path.isEmpty {
                return URL(fileURLWithPath: path)
            }

            return FileManager.default.temporaryDirectory
                .appendingPathComponent("ObsidianSideNoteUITests", isDirectory: true)
                .appendingPathComponent("config-\(ProcessInfo.processInfo.processIdentifier).json")
        }

        return primaryConfigURL
    }

    private static var primaryConfigURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static var isRunningInUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    private static var legacySandboxConfigURL: URL {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "live.lukesmith.ObsidianSideNote"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static var legacySandboxPreferencesURL: URL {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "live.lukesmith.ObsidianSideNote"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).plist")
    }

    static var restorableUserDefaultKeys: [String] {
        let shortcutKeys = ShortcutAction.allCases.flatMap { action in
            [action.preferenceKey, action.modifierPreferenceKey]
        }

        return [
            VaultStore.pathKey,
            VaultStore.bookmarkKey,
            "obsidianVault",
            "startAtLogin",
            NoteMode.appendDaily.draftTextKey,
            NoteMode.newNote.draftTextKey,
            NoteMode.newNote.draftTitleKey,
            NewNotePreferences.draftFilePathKey,
            NewNotePreferences.sessionStartedAtKey,
            NewNotePreferences.resumeIntervalMinutesKey,
            NewNotePreferences.useObsidianNewNoteFolderKey,
            NewNotePreferences.folderPathKey,
            NoteMode.editVaultFile.draftTextKey,
            NoteMode.editVaultFile.draftTitleKey,
            "draft.editVaultFile.search"
        ] + shortcutKeys
    }

    private static var configReadURLs: [URL] {
        guard configURLOverride == nil, !isRunningUnderXCTest else {
            return [configURL]
        }

        let legacyURL = legacySandboxConfigURL
        guard legacyURL != primaryConfigURL else {
            return [primaryConfigURL]
        }

        return [primaryConfigURL, legacyURL]
    }

    static func restorePersistedSettingsIfNeeded() {
        migrateLegacySandboxUserDefaultsIfNeeded()

        guard let config = read() else { return }
        let currentVaultURL = VaultStore.sanitizePersistedVaultSelection()
        let persistedVaultSelection = persistedVaultSelection(in: config)

        if currentVaultURL == nil, let persistedVaultSelection {
            let vaultName = config.vaultName?.isEmpty == false
                ? config.vaultName!
                : persistedVaultSelection.url.lastPathComponent

            UserDefaults.standard.set(persistedVaultSelection.url.path, forKey: VaultStore.pathKey)
            UserDefaults.standard.set(vaultName, forKey: "obsidianVault")

            if let bookmarkData = persistedVaultSelection.bookmarkData {
                UserDefaults.standard.set(bookmarkData, forKey: VaultStore.bookmarkKey)
            }
        }

        if let resumeInterval = config.newNoteResumeIntervalMinutes,
           NewNotePreferences.allowedResumeIntervals.contains(resumeInterval) {
            Defaults[.newNoteResumeIntervalMinutes] = resumeInterval
        }

        if let useObsidianFolder = config.useObsidianNewNoteFolder {
            UserDefaults.standard.set(useObsidianFolder, forKey: NewNotePreferences.useObsidianNewNoteFolderKey)
        }

        if let folderPath = config.newNoteFolderPath {
            UserDefaults.standard.set(folderPath, forKey: NewNotePreferences.folderPathKey)
        }

        if let startAtLogin = config.startAtLogin {
            UserDefaults.standard.set(startAtLogin, forKey: "startAtLogin")
        }

        for action in ShortcutAction.allCases {
            guard let shortcut = config.shortcuts[action.rawValue] else {
                continue
            }
            ShortcutPreference.restore(
                ShortcutDefinition(key: shortcut.key, modifiers: shortcut.modifierFlags),
                for: action
            )
        }
    }

    static func migrateUserDefaults(
        from legacyValues: [String: Any],
        to defaults: UserDefaults = .standard,
        keys: [String] = restorableUserDefaultKeys
    ) {
        for key in keys where defaults.object(forKey: key) == nil {
            guard let value = legacyValues[key] else { continue }
            defaults.set(value, forKey: key)
        }
    }

    private static func migrateLegacySandboxUserDefaultsIfNeeded() {
        guard configURLOverride == nil, !isRunningUnderXCTest, !isRunningInUITest else { return }
        guard let legacyValues = NSDictionary(contentsOf: legacySandboxPreferencesURL) as? [String: Any] else {
            return
        }

        migrateUserDefaults(from: legacyValues)
    }

    static func synchronizeCurrentSettings() {
        let currentVaultURL = VaultStore.sanitizePersistedVaultSelection()

        update { config in
            if let vaultURL = currentVaultURL {
                config.vaultPath = vaultURL.path
                config.vaultName = vaultURL.lastPathComponent
                config.vaultBookmarkBase64 = UserDefaults.standard.data(forKey: VaultStore.bookmarkKey)?
                    .base64EncodedString()
            } else if persistedVaultSelection(in: config) == nil {
                config.vaultPath = nil
                config.vaultName = nil
                config.vaultBookmarkBase64 = nil
            }

            config.newNoteResumeIntervalMinutes = NewNotePreferences.resumeIntervalMinutes
            config.useObsidianNewNoteFolder = NewNotePreferences.useObsidianNewNoteFolder
            config.newNoteFolderPath = NewNotePreferences.folderPath
            config.startAtLogin = UserDefaults.standard.bool(forKey: "startAtLogin")

            for action in ShortcutAction.allCases {
                let shortcut = ShortcutPreference.definition(for: action)
                config.shortcuts[action.rawValue] = PersistentShortcut(
                    key: shortcut.key,
                    modifiers: shortcut.modifiers
                )
            }
        }
    }

    static func saveVault(url: URL, bookmarkData: Data?) {
        guard VaultStore.directoryExists(at: url, usingSecurityScope: true) else { return }

        update { config in
            config.vaultPath = url.path
            config.vaultName = url.lastPathComponent
            config.vaultBookmarkBase64 = bookmarkData?.base64EncodedString() ?? config.vaultBookmarkBase64
        }
    }

    static func saveShortcut(action: ShortcutAction, key: String, modifiers: NSEvent.ModifierFlags) {
        update { config in
            config.shortcuts[action.rawValue] = PersistentShortcut(key: key, modifiers: modifiers)
        }
    }

    static func saveNewNoteResumeInterval(_ minutes: Int) {
        update { config in
            config.newNoteResumeIntervalMinutes = minutes
        }
    }

    static func saveNewNoteFolderPreferences(useObsidianFolder: Bool, folderPath: String) {
        update { config in
            config.useObsidianNewNoteFolder = useObsidianFolder
            config.newNoteFolderPath = folderPath
        }
    }

    static func saveStartAtLogin(_ isEnabled: Bool) {
        update { config in
            config.startAtLogin = isEnabled
        }
    }

    static func read() -> PersistentAppConfig? {
        for url in configReadURLs {
            guard let data = try? Data(contentsOf: url),
                  let config = try? JSONDecoder().decode(PersistentAppConfig.self, from: data) else {
                continue
            }
            return config
        }

        return nil
    }

    private static func update(_ body: (inout PersistentAppConfig) -> Void) {
        var config = read() ?? PersistentAppConfig()
        body(&config)
        write(config)
    }

    private static func write(_ config: PersistentAppConfig) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: configURL, options: .atomic)
        } catch {
            AppLogger.app.error("Failed to write persistent config: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func persistedVaultSelection(in config: PersistentAppConfig) -> (url: URL, bookmarkData: Data?)? {
        if let base64Bookmark = config.vaultBookmarkBase64,
           let bookmarkData = Data(base64Encoded: base64Bookmark),
           let url = resolvedExistingBookmarkURL(from: bookmarkData) {
            return (url, bookmarkData)
        }

        if let url = existingDirectoryURL(path: config.vaultPath) {
            return (url, nil)
        }

        return nil
    }

    private static func resolvedExistingBookmarkURL(from bookmarkData: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        return existingDirectoryURL(path: url.path)
            ?? (VaultStore.directoryExists(at: url, usingSecurityScope: true) ? url : nil)
    }

    private static func existingDirectoryURL(path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }
}

struct PersistentAppConfig: Codable, Equatable {
    var vaultPath: String?
    var vaultName: String?
    var vaultBookmarkBase64: String?
    var shortcuts: [String: PersistentShortcut] = [:]
    var newNoteResumeIntervalMinutes: Int?
    var useObsidianNewNoteFolder: Bool?
    var newNoteFolderPath: String?
    var startAtLogin: Bool?
}

struct PersistentShortcut: Codable, Equatable {
    let key: String
    let modifiersRawValue: UInt

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = ShortcutPreference.normalized(key)
        modifiersRawValue = ShortcutPreference.menuModifierFlags(from: modifiers).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        ShortcutPreference.menuModifierFlags(from: NSEvent.ModifierFlags(rawValue: modifiersRawValue))
    }
}
