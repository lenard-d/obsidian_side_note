import SwiftUI
import AppKit

struct KeyboardShortcutRow: View {
    let action: ShortcutAction
    @State private var shortcut: ShortcutDefinition
    @State private var isRecording = false
    @State private var eventMonitor: Any?

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

                if !action.isGlobal {
                    Text("Local only")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.75))
                }
            }

            Spacer()

            Button(action: startRecording) {
                Text(isRecording ? "Press keys..." : shortcut.displayValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(minWidth: 86, alignment: .center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isRecording ? Color.accentColor.opacity(0.25) : Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click, then press the full shortcut")
        }
        .frame(maxWidth: .infinity)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let modifiers = ShortcutPreference.menuModifierFlags(from: event.modifierFlags)
            guard modifiers.intersection([.command, .option, .control, .shift]).isEmpty == false,
                  let pressedKey = event.charactersIgnoringModifiers?.first,
                  event.keyCode != 36,
                  event.keyCode != 48 else {
                return nil
            }

            let key = ShortcutPreference.normalized(String(pressedKey), fallback: action.defaultKey)
            shortcut = ShortcutDefinition(key: key, modifiers: modifiers)
            ShortcutPreference.set(key, modifiers: modifiers, for: action)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }
}
