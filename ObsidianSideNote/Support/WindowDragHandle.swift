import SwiftUI
import AppKit

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct DraggableWindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSTextField {
        let textField = DraggableTitleTextField(labelWithString: title)
        textField.font = .systemFont(ofSize: 13, weight: .semibold)
        textField.textColor = .labelColor
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        textField.stringValue = title
    }
}

private final class DragHandleView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class DraggableTitleTextField: NSTextField {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
