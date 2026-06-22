import SwiftUI
import AppKit
import KeyboardShortcuts

struct KeyboardShortcutRow: View {
    let action: ShortcutAction
    @State private var shortcut: ShortcutDefinition
    @State private var validationMessage: String?

    init(action: ShortcutAction) {
        self.action = action
        ShortcutPreference.syncRecorderShortcut(for: action)
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

            Group {
                if let recorderShortcutName = action.recorderShortcutName {
                    KeyboardShortcuts.Recorder(for: recorderShortcutName) { shortcut in
                        updateShortcut(shortcut)
                    }
                    .frame(width: 112)
                } else {
                    LocalShortcutRecorder(shortcut: $shortcut) { shortcut in
                        updateLocalShortcut(shortcut)
                    }
                    .frame(width: 112)
                }
            }
            .help(action.isGlobal
                  ? "Click, then press the full shortcut"
                  : "Local app shortcut. It only works while Obsidian Side Note is focused.")
        }
        .frame(maxWidth: .infinity)
    }

    private func updateShortcut(_ recordedShortcut: KeyboardShortcuts.Shortcut?) {
        guard let recordedShortcut else {
            ShortcutPreference.resetToDefault(for: action)
            shortcut = action.shortcut
            validationMessage = nil
            return
        }

        let key = GlobalHotKeyManager.key(forKeyCode: recordedShortcut.carbonKeyCode) ?? action.defaultKey
        let modifiers = ShortcutPreference.menuModifierFlags(from: recordedShortcut.modifiers)
        if let message = ShortcutPolicy.validationMessage(for: action, key: key, modifiers: modifiers) {
            validationMessage = message
            ShortcutPreference.syncRecorderShortcut(for: action)
            return
        }

        ShortcutPreference.set(key, modifiers: modifiers, for: action)
        shortcut = ShortcutDefinition(key: key, modifiers: modifiers)
        validationMessage = nil
    }

    private func updateLocalShortcut(_ recordedShortcut: ShortcutDefinition?) {
        guard let recordedShortcut else {
            ShortcutPreference.resetToDefault(for: action)
            shortcut = action.shortcut
            validationMessage = nil
            return
        }

        if let message = ShortcutPolicy.validationMessage(
            for: action,
            key: recordedShortcut.key,
            modifiers: recordedShortcut.modifiers
        ) {
            validationMessage = message
            return
        }

        ShortcutPreference.set(recordedShortcut.key, modifiers: recordedShortcut.modifiers, for: action)
        shortcut = recordedShortcut
        validationMessage = nil
    }
}

private struct LocalShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: ShortcutDefinition
    let onChange: (ShortcutDefinition?) -> Void

    func makeNSView(context: Context) -> LocalShortcutRecorderField {
        LocalShortcutRecorderField(shortcut: shortcut, onChange: onChange)
    }

    func updateNSView(_ nsView: LocalShortcutRecorderField, context: Context) {
        nsView.shortcut = shortcut
    }
}

private final class LocalShortcutRecorderField: NSSearchField, NSSearchFieldDelegate {
    var shortcut: ShortcutDefinition {
        didSet {
            refreshDisplay()
        }
    }

    private let onChange: (ShortcutDefinition?) -> Void
    private var eventMonitor: Any?

    override var canBecomeKeyView: Bool {
        true
    }

    init(shortcut: ShortcutDefinition, onChange: @escaping (ShortcutDefinition?) -> Void) {
        self.shortcut = shortcut
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 112, height: 24))

        delegate = self
        alignment = .center
        placeholderString = "Record Shortcut"
        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        refreshDisplay()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopRecording()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        guard didBecomeFirstResponder else {
            return false
        }

        startRecording()
        return true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopRecording()
        }
    }

    func controlTextDidChange(_ object: Notification) {
        if stringValue.isEmpty {
            onChange(nil)
        }
    }

    private func startRecording() {
        stopRecording()
        placeholderString = "Press Shortcut"
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        placeholderString = "Record Shortcut"
        refreshDisplay()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .leftMouseUp || event.type == .rightMouseUp {
            guard event.window == window else {
                blur()
                return event
            }

            let clickPoint = convert(event.locationInWindow, from: nil)
            if !bounds.insetBy(dx: -3, dy: -3).contains(clickPoint) {
                blur()
            }
            return event
        }

        guard event.type == .keyDown else {
            return event
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           event.keyCode == 48 {
            blur()
            return event
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           event.keyCode == 53 {
            blur()
            return nil
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           event.keyCode == 51 || event.keyCode == 117 {
            onChange(nil)
            blur()
            return nil
        }

        let modifiers = ShortcutPreference.menuModifierFlags(from: event.modifierFlags)
        guard !modifiers.subtracting(.shift).isEmpty else {
            NSSound.beep()
            return nil
        }

        let fallbackKey = ShortcutPreference.normalized(event.charactersIgnoringModifiers ?? "", fallback: "")
        guard let key = GlobalHotKeyManager.key(forKeyCode: Int(event.keyCode)) ?? (fallbackKey.isEmpty ? nil : fallbackKey) else {
            NSSound.beep()
            return nil
        }

        let recordedShortcut = ShortcutDefinition(key: key, modifiers: modifiers)
        stringValue = recordedShortcut.displayValue
        onChange(recordedShortcut)
        blur()
        return nil
    }

    private func refreshDisplay() {
        stringValue = shortcut.displayValue
    }

    private func blur() {
        window?.makeFirstResponder(nil)
    }
}
