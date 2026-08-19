import AppKit
import Defaults
import Foundation

/// Coordinates restoration/snapshotting across otherwise independent stores.
/// Leaf preference stores may write config deltas, while AppConfigStore no
/// longer reaches back into those stores, keeping dependencies acyclic.
enum AppSettingsPersistenceCoordinator {
    static var restorableUserDefaultKeys: [String] {
        let shortcutKeys = ShortcutAction.allCases.flatMap { action in
            [action.preferenceKey, action.modifierPreferenceKey]
        }

        return [
            VaultSelectionStore.pathKey,
            VaultSelectionStore.bookmarkKey,
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
            LinkPreviewPreferences.hoverDelaySecondsKey,
            NoteMode.editVaultFile.draftTextKey,
            NoteMode.editVaultFile.draftTitleKey,
            "draft.editVaultFile.search"
        ] + shortcutKeys
    }

    static func restorePersistedSettingsIfNeeded() {
        AppConfigStore.migrateLegacySandboxUserDefaults(keys: restorableUserDefaultKeys)
        guard let config = AppConfigStore.read() else { return }

        let currentVaultURL = VaultSelectionStore.sanitizePersistedSelection()
        let persistedVaultSelection = AppConfigStore.persistedVaultSelection(in: config)
        if currentVaultURL == nil, let persistedVaultSelection {
            let vaultName = config.vaultName.flatMap { $0.isEmpty ? nil : $0 }
                ?? persistedVaultSelection.url.lastPathComponent
            UserDefaults.standard.set(persistedVaultSelection.url.path, forKey: VaultSelectionStore.pathKey)
            UserDefaults.standard.set(vaultName, forKey: "obsidianVault")
            if let bookmarkData = persistedVaultSelection.bookmarkData {
                UserDefaults.standard.set(bookmarkData, forKey: VaultSelectionStore.bookmarkKey)
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
        if let hoverDelay = config.linkPreviewHoverDelaySeconds {
            UserDefaults.standard.set(
                LinkPreviewPreferences.sanitized(hoverDelay),
                forKey: LinkPreviewPreferences.hoverDelaySecondsKey
            )
        }
        if let startAtLogin = config.startAtLogin {
            UserDefaults.standard.set(startAtLogin, forKey: "startAtLogin")
        }

        for action in ShortcutAction.allCases {
            guard let shortcut = config.shortcuts[action.rawValue] else { continue }
            ShortcutPreference.restore(
                ShortcutDefinition(key: shortcut.key, modifiers: shortcut.modifierFlags),
                for: action
            )
        }
    }

    static func synchronizeCurrentSettings() {
        let shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { action in
            let shortcut = ShortcutPreference.definition(for: action)
            return (action.rawValue, PersistentShortcut(key: shortcut.key, modifiers: shortcut.modifiers))
        })
        AppConfigStore.synchronize(
            AppSettingsSnapshot(
                vaultURL: VaultSelectionStore.sanitizePersistedSelection(),
                vaultBookmarkData: UserDefaults.standard.data(forKey: VaultSelectionStore.bookmarkKey),
                newNoteResumeIntervalMinutes: NewNotePreferences.resumeIntervalMinutes,
                useObsidianNewNoteFolder: NewNotePreferences.useObsidianNewNoteFolder,
                newNoteFolderPath: NewNotePreferences.folderPath,
                linkPreviewHoverDelaySeconds: LinkPreviewPreferences.hoverDelaySeconds,
                startAtLogin: UserDefaults.standard.bool(forKey: "startAtLogin"),
                shortcuts: shortcuts
            )
        )
    }

    static func migrateUserDefaults(
        from legacyValues: [String: Any],
        to defaults: UserDefaults = .standard,
        keys: [String]? = nil
    ) {
        for key in keys ?? restorableUserDefaultKeys where defaults.object(forKey: key) == nil {
            guard let value = legacyValues[key] else { continue }
            defaults.set(value, forKey: key)
        }
    }
}

struct AppSettingsSnapshot {
    let vaultURL: URL?
    let vaultBookmarkData: Data?
    let newNoteResumeIntervalMinutes: Int
    let useObsidianNewNoteFolder: Bool
    let newNoteFolderPath: String
    let linkPreviewHoverDelaySeconds: Double
    let startAtLogin: Bool
    let shortcuts: [String: PersistentShortcut]
}
