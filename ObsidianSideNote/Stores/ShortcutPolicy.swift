import AppKit

enum ShortcutPolicy {
    static func validationMessage(
        for action: ShortcutAction,
        key: String,
        modifiers: NSEvent.ModifierFlags
    ) -> String? {
        let shortcut = ShortcutDefinition(
            key: ShortcutPreference.normalized(key, fallback: action.defaultKey),
            modifiers: ShortcutPreference.menuModifierFlags(from: modifiers)
        )

        if action.isGlobal, isCommandOnly(shortcut.modifiers) {
            return "Global shortcuts need Control or Option so they do not steal normal app commands."
        }

        if let conflictingAction = ShortcutAction.allCases.first(where: { otherAction in
            otherAction != action && ShortcutPreference.definition(for: otherAction) == shortcut
        }) {
            return "Already used by \(conflictingAction.title)."
        }

        return nil
    }

    private static func isCommandOnly(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        ShortcutPreference.menuModifierFlags(from: modifiers) == .command
    }
}
