import SwiftUI
import AppKit

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragHandleView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
