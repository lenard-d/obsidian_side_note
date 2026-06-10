import AppKit
import STTextKitPlus
import STTextView

final class MediaScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    var focusTextView: (() -> Void)?
    private var topEditorPadding: CGFloat = 0

    override func layout() {
        super.layout()
        updateEditorContentInsets()
        onLayout?()
    }

    override func mouseDown(with event: NSEvent) {
        focusTextView?()
        super.mouseDown(with: event)
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateEditorContentInsets()
    }

    func configureEditorTopPadding(_ top: CGFloat) {
        topEditorPadding = top
        updateEditorContentInsets()
    }

    private func updateEditorContentInsets() {
        let visibleOriginY = documentVisibleRect.minY
        let topPadding = visibleOriginY <= 1 ? topEditorPadding : 0
        let nextInsets = NSEdgeInsets(top: topPadding, left: 0, bottom: 0, right: 0)
        guard contentView.contentInsets.top != nextInsets.top
                || contentView.contentInsets.left != nextInsets.left
                || contentView.contentInsets.bottom != nextInsets.bottom
                || contentView.contentInsets.right != nextInsets.right else {
            return
        }
        contentView.contentInsets = nextInsets
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

protocol MarkdownListEditingTextViewDelegate: AnyObject {
    func mediaTextViewDidRequestSmartNewline(_ textView: MediaTextView) -> Bool
    func mediaTextViewDidRequestIndent(_ textView: MediaTextView) -> Bool
    func mediaTextViewDidRequestOutdent(_ textView: MediaTextView) -> Bool
}

final class MediaTextView: STTextView {
    weak var mediaDelegate: MediaTextViewDelegate?
    weak var markdownCommandDelegate: MarkdownCommandTextViewDelegate?
    weak var taskListDelegate: TaskListTextViewDelegate?
    weak var listEditingDelegate: MarkdownListEditingTextViewDelegate?
    private var minimumDocumentHeight: CGFloat = 120
    private(set) var horizontalEditorPadding: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    init() {
        super.init(frame: .zero)
        configureTextContainer()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureTextContainer()
    }

    var textStorage: NSTextStorage? {
        (textContentManager as? NSTextContentStorage)?.textStorage
    }

    var layoutManager: NSTextLayoutManager? {
        textLayoutManager
    }

    var string: String {
        get { text ?? "" }
        set { text = newValue }
    }

    func setAttributedString(_ attributedString: NSAttributedString) {
        attributedText = attributedString
    }

    func configureHorizontalEditorPadding(_ padding: CGFloat) {
        horizontalEditorPadding = padding
        textContainer.lineFragmentPadding = padding
    }

    func setSelectedRange(_ range: NSRange) {
        textSelection = clamped(range: range)
    }

    func configureForVerticalScrolling(contentSize: NSSize) {
        let width = max(80, contentSize.width)
        let height = max(120, contentSize.height)

        minimumDocumentHeight = height
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]

        if abs(frame.width - width) > 1 || frame.height < height {
            setFrameSize(NSSize(width: width, height: max(frame.height, height)))
        }

        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        resizeToFitTextContent()
    }

    func resizeToFitTextContent() {
        sizeToFit()
        let requiredHeight = ceil(frame.height)
        let height = max(minimumDocumentHeight, requiredHeight)

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

    override func insertNewline(_ sender: Any?) {
        if listEditingDelegate?.mediaTextViewDidRequestSmartNewline(self) == true {
            return
        }

        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        if listEditingDelegate?.mediaTextViewDidRequestIndent(self) == true {
            return
        }

        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if listEditingDelegate?.mediaTextViewDidRequestOutdent(self) == true {
            return
        }

        super.insertBacktab(sender)
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
        window?.makeFirstResponder(self)

        if toggleTaskCheckboxIfClicked(with: event) {
            return
        }

        super.mouseDown(with: event)
    }

    func taskCheckboxLocation(atVisibleLocation location: Int) -> Int? {
        guard location != NSNotFound,
              attributedString().length > location,
              attributedString().attribute(.markdownTaskCheckbox, at: location, effectiveRange: nil) != nil else {
            return nil
        }

        return location
    }

    private func toggleTaskCheckboxIfClicked(with event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown,
              event.clickCount == 1,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
              let visibleLocation = taskCheckboxLocation(for: event) else {
            return false
        }

        taskListDelegate?.mediaTextView(self, didRequestTaskToggleAtVisibleLocation: visibleLocation)
        return true
    }

    private func taskCheckboxLocation(for event: NSEvent) -> Int? {
        let eventPoint = convert(event.locationInWindow, from: nil)
        if let attachmentLocation = taskCheckboxLocation(containing: eventPoint) {
            return attachmentLocation
        }

        guard let textLocation = textLayoutManager.caretLocation(
            interactingAt: eventPoint,
            inContainerAt: textLayoutManager.documentRange.location
        ) else {
            return nil
        }

        let visibleLocation = textContentManager.offset(from: textLayoutManager.documentRange.location, to: textLocation)
        return taskCheckboxLocation(atVisibleLocation: visibleLocation)
    }

    private func taskCheckboxLocation(containing point: NSPoint) -> Int? {
        let attributedString = attributedString()
        guard attributedString.length > 0 else { return nil }

        for location in 0..<attributedString.length {
            guard taskCheckboxLocation(atVisibleLocation: location) != nil,
                  let startLocation = textLayoutManager.location(textLayoutManager.documentRange.location, offsetBy: location),
                  let endLocation = textLayoutManager.location(startLocation, offsetBy: 1) else {
                continue
            }

            guard let textRange = NSTextRange(location: startLocation, end: endLocation) else {
                continue
            }
            var containsPoint = false
            textLayoutManager.enumerateTextSegments(
                in: textRange,
                type: .standard,
                options: [.rangeNotRequired]
            ) { _, frame, _, _ in
                containsPoint = frame.insetBy(dx: -4, dy: -3).contains(point)
                return !containsPoint
            }

            if containsPoint {
                return location
            }
        }

        return nil
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

    private func configureTextContainer() {
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    }

    private func clamped(range: NSRange) -> NSRange {
        let length = string.utf16.count
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(range.length, max(0, length - location)))
    }
}
