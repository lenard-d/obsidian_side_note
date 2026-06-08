import AppKit

final class FloatingWindow: NSWindow {
    var keyEquivalentHandler: ((NSEvent) -> Bool)?
    var escapeHandler: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            escapeHandler?()
            return
        }

        super.keyDown(with: event)
    }
}
