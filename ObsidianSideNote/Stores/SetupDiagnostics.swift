import AppKit
import Foundation

enum SetupDiagnostics {
    static var vaultAccessStatus: String {
        guard VaultStore.isVaultConfigured else { return "Missing" }
        return VaultStore.canAccessSelectedVault ? "Ready" : "Needs folder access"
    }

    static var obsidianStatus: String {
        guard let url = URL(string: "obsidian://open"),
              NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            return "Not detected"
        }

        return "Detected"
    }

    static var advancedURIStatus: String {
        "Manual check"
    }

    static var globalShortcutStatus: String {
        let invalidActions = ShortcutAction.globalActions.filter { action in
            let shortcut = ShortcutPreference.definition(for: action)
            return ShortcutPolicy.validationMessage(for: action, key: shortcut.key, modifiers: shortcut.modifiers) != nil
        }

        return invalidActions.isEmpty ? "Ready" : "Needs review"
    }

    static var launchAtLoginStatus: String {
        LoginItemStore.statusDescription
    }
}
