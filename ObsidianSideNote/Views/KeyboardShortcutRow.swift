import SwiftUI
import AppKit
import KeyboardShortcuts

struct KeyboardShortcutRow: View {
    let action: ShortcutAction
    @State private var shortcut: ShortcutDefinition
    @State private var validationMessage: String?

    init(action: ShortcutAction) {
        self.action = action
        _shortcut = State(initialValue: ShortcutPreference.definition(for: action))
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                if let validationMessage {
                    Text(validationMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            KeyboardShortcuts.Recorder(for: action.shortcutName) { shortcut in
                updateShortcut(shortcut)
            }
            .frame(width: 112)
            .help("Click, then press the full shortcut")
        }
        .frame(maxWidth: .infinity)
    }

    private func updateShortcut(_ recordedShortcut: KeyboardShortcuts.Shortcut?) {
        guard let recordedShortcut else {
            shortcut = action.shortcut
            validationMessage = nil
            NotificationCenter.default.post(name: .shortcutPreferencesDidChange, object: nil)
            return
        }

        let key = GlobalHotKeyManager.key(forKeyCode: recordedShortcut.carbonKeyCode) ?? action.defaultKey
        let modifiers = ShortcutPreference.menuModifierFlags(from: recordedShortcut.modifiers)
        if let message = ShortcutPolicy.validationMessage(for: action, key: key, modifiers: modifiers) {
            validationMessage = message
            KeyboardShortcuts.setShortcut(ShortcutPreference.keyboardShortcut(key: shortcut.key, modifiers: shortcut.modifiers), for: action.shortcutName)
            return
        }

        shortcut = ShortcutDefinition(key: key, modifiers: modifiers)
        validationMessage = nil
        NotificationCenter.default.post(name: .shortcutPreferencesDidChange, object: nil)
    }
}
