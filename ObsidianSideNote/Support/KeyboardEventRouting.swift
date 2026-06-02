import AppKit

enum KeyboardEventRouting {
    static func shouldHandleLocalShortcut(_ event: NSEvent) -> Bool {
        if eventHasShortcutModifier(event) {
            return true
        }

        return !isTextInputFirstResponder(in: event.window)
    }

    static func eventHasShortcutModifier(_ event: NSEvent) -> Bool {
        let modifiers = ShortcutPreference.menuModifierFlags(from: event.modifierFlags)
        return modifiers.intersection([.command, .control, .option]).isEmpty == false
    }

    static func isTextInputFirstResponder(in window: NSWindow?) -> Bool {
        guard let firstResponder = window?.firstResponder else { return false }

        if let textView = firstResponder as? NSTextView {
            return textView.isEditable || textView.isFieldEditor
        }

        if firstResponder is NSTextField {
            return true
        }

        return false
    }
}
