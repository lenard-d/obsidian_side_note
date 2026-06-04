import AppKit

final class MediaScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

protocol MediaTextViewDelegate: AnyObject {
    func mediaTextViewDidRequestPasteMedia(_ textView: MediaTextView) -> Bool
    func mediaTextView(_ textView: MediaTextView, didReceiveDrop pasteboard: NSPasteboard) -> Bool
}

protocol MarkdownCommandTextViewDelegate: AnyObject {
    func mediaTextView(_ textView: MediaTextView, didRequestMarkdownWrapper wrapper: String)
}

protocol TaskListTextViewDelegate: AnyObject {
    func mediaTextView(_ textView: MediaTextView, didRequestTaskToggleAtVisibleLocation location: Int)
}

final class MediaTextView: NSTextView {
    weak var mediaDelegate: MediaTextViewDelegate?
    weak var markdownCommandDelegate: MarkdownCommandTextViewDelegate?
    weak var taskListDelegate: TaskListTextViewDelegate?

    init() {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )

        textContainer.widthTracksTextView = true
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        super.init(frame: .zero, textContainer: textContainer)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func configureForVerticalScrolling(contentSize: NSSize) {
        let width = max(80, contentSize.width)
        let height = max(120, contentSize.height)

        minSize = NSSize(width: 0, height: height)
        maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]

        if abs(frame.width - width) > 1 || frame.height < height {
            setFrameSize(NSSize(width: width, height: max(frame.height, height)))
        }

        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        textContainer?.containerSize = NSSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )

        resizeToFitTextContent()
    }

    func resizeToFitTextContent() {
        guard let layoutManager, let textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let requiredHeight = ceil(usedRect.height + textContainerInset.height * 2)
        let height = max(minSize.height, requiredHeight)

        if abs(frame.height - height) > 1 {
            setFrameSize(NSSize(width: frame.width, height: height))
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if MediaAttachmentImporter.canImportFromPasteboard(sender.draggingPasteboard) {
            return .copy
        }

        return super.draggingEntered(sender)
    }

    override func paste(_ sender: Any?) {
        if mediaDelegate?.mediaTextViewDidRequestPasteMedia(self) == true {
            return
        }

        super.paste(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let containsMedia = MediaAttachmentImporter.canImportFromPasteboard(sender.draggingPasteboard)
        if mediaDelegate?.mediaTextView(self, didReceiveDrop: sender.draggingPasteboard) == true {
            return true
        }

        if containsMedia {
            return true
        }

        return super.performDragOperation(sender)
    }

    override func mouseDown(with event: NSEvent) {
        if let characterIndex = characterIndex(for: event),
           attributedString().attribute(.markdownTaskCheckbox, at: characterIndex, effectiveRange: nil) != nil {
            taskListDelegate?.mediaTextView(self, didRequestTaskToggleAtVisibleLocation: characterIndex)
            return
        }

        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        let hasShift = event.modifierFlags.contains(.shift)
        let hasOnlyCommandOrShift = event.modifierFlags.intersection([.control, .option]).isEmpty
        guard hasOnlyCommandOrShift else {
            return super.performKeyEquivalent(with: event)
        }

        switch characters {
        case "z" where hasShift:
            undoManager?.redo()
            return true
        case "z":
            undoManager?.undo()
            return true
        case "b":
            markdownCommandDelegate?.mediaTextView(self, didRequestMarkdownWrapper: "**")
            return true
        case "i":
            markdownCommandDelegate?.mediaTextView(self, didRequestMarkdownWrapper: "*")
            return true
        case "h":
            markdownCommandDelegate?.mediaTextView(self, didRequestMarkdownWrapper: "==")
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func characterIndex(for event: NSEvent) -> Int? {
        guard let layoutManager, let textContainer else { return nil }

        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y

        guard point.x >= 0, point.y >= 0 else { return nil }
        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < attributedString().length else { return nil }

        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.insetBy(dx: -4, dy: -4).contains(point) else { return nil }
        return characterIndex
    }
}
