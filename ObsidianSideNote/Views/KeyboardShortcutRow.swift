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

            if let shortcutName = action.globalShortcutName {
                KeyboardShortcuts.Recorder(for: shortcutName) { shortcut in
                    updateShortcut(shortcut)
                }
                .frame(width: 112)
                .help("Click, then press the full shortcut")
            } else {
                Text(shortcut.displayValue)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 112, alignment: .trailing)
                    .help("Local app shortcut. It only works while Obsidian Side Note is focused.")
            }
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
            if let shortcutName = action.globalShortcutName {
                KeyboardShortcuts.setShortcut(
                    ShortcutPreference.keyboardShortcut(key: shortcut.key, modifiers: shortcut.modifiers),
                    for: shortcutName
                )
            }
            return
        }

        ShortcutPreference.set(key, modifiers: modifiers, for: action)
        shortcut = ShortcutDefinition(key: key, modifiers: modifiers)
        validationMessage = nil
    }
}
