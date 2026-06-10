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

        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func restorePersistedSettingsIfNeeded() {
        guard let config = read() else { return }

        if UserDefaults.standard.string(forKey: VaultStore.pathKey)?.isEmpty != false,
           let vaultPath = config.vaultPath,
           !vaultPath.isEmpty {
            UserDefaults.standard.set(vaultPath, forKey: VaultStore.pathKey)
        }

        if UserDefaults.standard.string(forKey: "obsidianVault")?.isEmpty != false,
           let vaultName = config.vaultName,
           !vaultName.isEmpty {
            UserDefaults.standard.set(vaultName, forKey: "obsidianVault")
        }

        if UserDefaults.standard.data(forKey: VaultStore.bookmarkKey) == nil,
           let base64Bookmark = config.vaultBookmarkBase64,
           let bookmarkData = Data(base64Encoded: base64Bookmark) {
            UserDefaults.standard.set(bookmarkData, forKey: VaultStore.bookmarkKey)
        }

        if let resumeInterval = config.newNoteResumeIntervalMinutes,
           NewNotePreferences.allowedResumeIntervals.contains(resumeInterval) {
            Defaults[.newNoteResumeIntervalMinutes] = resumeInterval
        }

        if let startAtLogin = config.startAtLogin {
            UserDefaults.standard.set(startAtLogin, forKey: "startAtLogin")
        }

        for action in ShortcutAction.allCases {
            guard let shortcut = config.shortcuts[action.rawValue],
                  let keyboardShortcut = ShortcutPreference.keyboardShortcut(
                    key: shortcut.key,
                    modifiers: shortcut.modifierFlags
                  ) else {
                continue
            }
            KeyboardShortcuts.setShortcut(keyboardShortcut, for: action.shortcutName)
        }
    }

    static func synchronizeCurrentSettings() {
        update { config in
            if let vaultPath = UserDefaults.standard.string(forKey: VaultStore.pathKey),
               !vaultPath.isEmpty {
                config.vaultPath = vaultPath
                config.vaultName = UserDefaults.standard.string(forKey: "obsidianVault")
                    ?? URL(fileURLWithPath: vaultPath).lastPathComponent
            }

            if let bookmarkData = UserDefaults.standard.data(forKey: VaultStore.bookmarkKey) {
                config.vaultBookmarkBase64 = bookmarkData.base64EncodedString()
            }

            config.newNoteResumeIntervalMinutes = NewNotePreferences.resumeIntervalMinutes
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

    static func saveStartAtLogin(_ isEnabled: Bool) {
        update { config in
            config.startAtLogin = isEnabled
        }
    }

    static func read() -> PersistentAppConfig? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(PersistentAppConfig.self, from: data)
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
}

struct PersistentAppConfig: Codable, Equatable {
    var vaultPath: String?
    var vaultName: String?
    var vaultBookmarkBase64: String?
    var shortcuts: [String: PersistentShortcut] = [:]
    var newNoteResumeIntervalMinutes: Int?
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
