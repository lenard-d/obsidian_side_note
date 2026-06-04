import AppKit
import KeyboardShortcuts

extension NSMenuItem {
    func applyShortcut(_ action: ShortcutAction) {
        setShortcut(for: action.shortcutName)
    }

    func removeShortcut() {
        keyEquivalent = ""
        keyEquivalentModifierMask = []
    }
}
