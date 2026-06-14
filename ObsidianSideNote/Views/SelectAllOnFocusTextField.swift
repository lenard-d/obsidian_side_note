import AppKit
import SwiftUI

final class ReturnCommittingTextField: NSTextField {
    var returnKeyHandler: ((ReturnCommittingTextField) -> Void)?

    override func keyDown(with event: NSEvent) {
        let returnKeyCodes: Set<UInt16> = [36, 76]
        guard returnKeyCodes.contains(event.keyCode) else {
            super.keyDown(with: event)
            return
        }

        returnKeyHandler?(self)
    }
}

struct SelectAllOnFocusTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let focusRequestID: Int
    let onCommit: (NSWindow?) -> Void

    init(
        placeholder: String,
        text: Binding<String>,
        focusRequestID: Int = 0,
        onCommit: @escaping (NSWindow?) -> Void = { _ in }
    ) {
        self.placeholder = placeholder
        _text = text
        self.focusRequestID = focusRequestID
        self.onCommit = onCommit
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = ReturnCommittingTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 15, weight: .semibold)
        textField.textColor = .labelColor
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.textDidCommit(_:))
        textField.returnKeyHandler = { [weak coordinator = context.coordinator] textField in
            coordinator?.commitReturn(from: textField)
        }
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.onCommit = onCommit
        if let textField = textField as? ReturnCommittingTextField {
            textField.returnKeyHandler = { [weak coordinator = context.coordinator] textField in
                coordinator?.commitReturn(from: textField)
            }
        }

        if textField.stringValue != text {
            textField.stringValue = text
        }

        guard context.coordinator.appliedFocusRequestID != focusRequestID else { return }
        context.coordinator.appliedFocusRequestID = focusRequestID

        DispatchQueue.main.async { [weak textField] in
            guard let textField, let window = textField.window else { return }
            window.makeFirstResponder(textField)
            textField.currentEditor()?.selectAll(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        var onCommit: (NSWindow?) -> Void = { _ in }
        var appliedFocusRequestID = 0
        private var pendingReturnCommit = false

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField,
                  let editor = textField.currentEditor() else { return }
            editor.selectAll(nil)
        }

        @objc func textDidCommit(_ sender: NSTextField) {
            text = sender.stringValue
            pendingReturnCommit = true
            finishReturnCommit(window: sender.window)
        }

        func commitReturn(from textField: NSTextField) {
            let committedText = textField.currentEditor()?.string ?? textField.stringValue
            let commitWindow = textField.window
            text = committedText
            textField.stringValue = committedText
            pendingReturnCommit = true
            commitWindow?.endEditing(for: nil)
            finishReturnCommit(window: commitWindow)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue

            guard textMovement(in: notification) == NSReturnTextMovement || pendingReturnCommit else { return }
            pendingReturnCommit = true
            finishReturnCommit(window: textField.window)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            let isReturnCommand = commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))

            guard isReturnCommand,
                  let textField = control as? NSTextField else {
                return false
            }

            text = textView.string
            textField.stringValue = textView.string
            pendingReturnCommit = true
            let commitWindow = textField.window
            commitWindow?.endEditing(for: nil)
            finishReturnCommit(window: commitWindow)
            return true
        }

        private func finishReturnCommit(window: NSWindow?) {
            guard pendingReturnCommit else { return }
            pendingReturnCommit = false
            let commitWindow = window
            let delays: [TimeInterval] = [0, 0.03, 0.12, 0.30]

            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [onCommit] in
                    onCommit(commitWindow)
                }
            }
        }

        private func textMovement(in notification: Notification) -> Int? {
            if let movement = notification.userInfo?[NSText.movementUserInfoKey] as? Int {
                return movement
            }
            return notification.userInfo?["NSTextMovement"] as? Int
        }
    }
}
