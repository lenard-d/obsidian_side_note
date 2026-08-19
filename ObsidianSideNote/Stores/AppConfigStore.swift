import AppKit
import Foundation

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

    private static func migrateUserDefaults(
        from legacyValues: [String: Any],
        to defaults: UserDefaults = .standard,
        keys: [String]
    ) {
        for key in keys where defaults.object(forKey: key) == nil {
            guard let value = legacyValues[key] else { continue }
            defaults.set(value, forKey: key)
        }
    }

    static func migrateLegacySandboxUserDefaults(keys: [String]) {
        guard configURLOverride == nil, !isRunningUnderXCTest, !isRunningInUITest else { return }
        guard let legacyValues = NSDictionary(contentsOf: legacySandboxPreferencesURL) as? [String: Any] else {
            return
        }

        migrateUserDefaults(from: legacyValues, keys: keys)
    }

    static func synchronize(_ snapshot: AppSettingsSnapshot) {
        update { config in
            if let vaultURL = snapshot.vaultURL {
                config.vaultPath = vaultURL.path
                config.vaultName = vaultURL.lastPathComponent
                config.vaultBookmarkBase64 = snapshot.vaultBookmarkData?.base64EncodedString()
            } else if persistedVaultSelection(in: config) == nil {
                config.vaultPath = nil
                config.vaultName = nil
                config.vaultBookmarkBase64 = nil
            }

            config.newNoteResumeIntervalMinutes = snapshot.newNoteResumeIntervalMinutes
            config.useObsidianNewNoteFolder = snapshot.useObsidianNewNoteFolder
            config.newNoteFolderPath = snapshot.newNoteFolderPath
            config.linkPreviewHoverDelaySeconds = snapshot.linkPreviewHoverDelaySeconds
            config.startAtLogin = snapshot.startAtLogin
            config.shortcuts = snapshot.shortcuts
        }
    }

    static func saveVault(url: URL, bookmarkData: Data?) {
        guard VaultSelectionStore.directoryExists(at: url, usingSecurityScope: true) else { return }

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

    static func saveLinkPreviewHoverDelay(_ seconds: Double) {
        update { config in
            config.linkPreviewHoverDelaySeconds = LinkPreviewPreferences.sanitized(seconds)
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
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(PersistentAppConfig.self, from: data)
            } catch {
                AppLogger.app.warn("Skipped unreadable persistent config: \(AppLogger.errorSummary(error))")
            }
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
            AppLogger.app.error("Failed to write persistent config: \(AppLogger.errorSummary(error))")
        }
    }

    static func persistedVaultSelection(in config: PersistentAppConfig) -> (url: URL, bookmarkData: Data?)? {
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
            ?? (VaultSelectionStore.directoryExists(at: url, usingSecurityScope: true) ? url : nil)
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
    var linkPreviewHoverDelaySeconds: Double?
    var startAtLogin: Bool?
}

struct PersistentShortcut: Codable, Equatable {
    let key: String
    let modifiersRawValue: UInt

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key
        modifiersRawValue = modifiers.rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue)
    }
}
