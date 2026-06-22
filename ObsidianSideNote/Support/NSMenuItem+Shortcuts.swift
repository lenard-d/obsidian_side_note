import AppKit

extension NSMenuItem {
    func applyShortcut(_ action: ShortcutAction) {
        let shortcut = ShortcutPreference.definition(for: action)
        keyEquivalent = shortcut.menuKeyEquivalent
        keyEquivalentModifierMask = shortcut.modifiers
    }

    func removeShortcut() {
        keyEquivalent = ""
        keyEquivalentModifierMask = []
    }
}

extension ShortcutDefinition {
    var menuKeyEquivalent: String {
        key == "space" ? " " : key
    }
}
