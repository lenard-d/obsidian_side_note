import AppKit
import SwiftUI

struct SelectAllOnFocusTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String

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
        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

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
        }
    }
}
