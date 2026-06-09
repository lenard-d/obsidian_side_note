import AppKit
import SwiftUI

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
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 15, weight: .semibold)
        textField.textColor = .labelColor
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.textDidCommit(_:))
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.onCommit = onCommit

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
        private weak var committingWindow: NSWindow?
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
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  let textField = control as? NSTextField else {
                return false
            }

            text = textView.string
            textField.stringValue = textView.string
            pendingReturnCommit = true
            textField.window?.endEditing(for: nil)
            finishReturnCommit(window: textField.window)
            return true
        }

        private func finishReturnCommit(window: NSWindow?) {
            guard pendingReturnCommit else { return }
            pendingReturnCommit = false
            committingWindow = window
            DispatchQueue.main.async { [weak self, onCommit] in
                onCommit(self?.committingWindow)
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
