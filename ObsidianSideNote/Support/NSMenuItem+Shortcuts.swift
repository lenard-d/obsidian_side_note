import AppKit

extension NSMenuItem {
    func applyShortcut(_ action: ShortcutAction) {
        let shortcut = action.shortcut
        keyEquivalent = shortcut.key
        keyEquivalentModifierMask = shortcut.modifiers
    }
}
