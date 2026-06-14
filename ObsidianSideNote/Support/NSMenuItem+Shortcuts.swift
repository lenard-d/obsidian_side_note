import AppKit

extension NSMenuItem {
    func applyShortcut(_ action: ShortcutAction) {
        let shortcut = ShortcutPreference.definition(for: action)
        keyEquivalent = shortcut.key
        keyEquivalentModifierMask = shortcut.modifiers
    }

    func removeShortcut() {
        keyEquivalent = ""
        keyEquivalentModifierMask = []
    }
}
