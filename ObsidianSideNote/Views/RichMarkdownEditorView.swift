import AppKit
import SwiftUI

struct RichMarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @Binding var cursorEndRequestID: Int
    let insertMedia: (String) -> Void
    let didInsertMedia: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: $isFocused,
            cursorEndRequestID: $cursorEndRequestID,
            insertMedia: insertMedia,
            didInsertMedia: didInsertMedia
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MediaScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let scrollView else { return }
            coordinator?.updateLayout(contentSize: scrollView.contentSize)
        }

        let textView = MediaTextView()
        textView.delegate = context.coordinator
        textView.mediaDelegate = context.coordinator
        textView.markdownCommandDelegate = context.coordinator
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.configureForVerticalScrolling(contentSize: NSSize(width: 560, height: 320))
        textView.registerForDraggedTypes(MediaAttachmentImporter.pasteboardTypes)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.render(text)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if context.coordinator.renderedText != text {
            context.coordinator.render(text)
        }
        context.coordinator.applyFocusIfNeeded()
        context.coordinator.applyCursorEndRequestIfNeeded()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, MediaTextViewDelegate, MarkdownCommandTextViewDelegate {
        @Binding private var text: String
        @FocusState.Binding private var isFocused: Bool
        @Binding private var cursorEndRequestID: Int
        private let insertMedia: (String) -> Void
        private let didInsertMedia: () -> Void
        fileprivate weak var textView: NSTextView?
        fileprivate var renderedText = ""
        private var mediaWidth: CGFloat = 560
        private var isRendering = false
        private var appliedCursorEndRequestID = 0
        private var pendingMediaLoads: Set<String> = []

        init(
            text: Binding<String>,
            isFocused: FocusState<Bool>.Binding,
            cursorEndRequestID: Binding<Int>,
            insertMedia: @escaping (String) -> Void,
            didInsertMedia: @escaping () -> Void
        ) {
            _text = text
            _isFocused = isFocused
            _cursorEndRequestID = cursorEndRequestID
            self.insertMedia = insertMedia
            self.didInsertMedia = didInsertMedia
        }

        func render(_ source: String) {
            guard let textView else { return }
            isRendering = true
            renderedText = source
            let selectedRange = textView.selectedRange()
            (textView as? MediaTextView)?.setRenderedAttributedString(
                MarkdownEditorTextRenderer.attributedString(from: source, mediaWidth: mediaWidth)
            )
            textView.typingAttributes = MarkdownEditorTextRenderer.typingAttributes
            textView.setSelectedRange(Self.clamped(range: selectedRange, length: textView.string.utf16.count))
            (textView as? MediaTextView)?.resizeToFitTextContent()
            isRendering = false

            applyFocusIfNeeded()

            preloadMissingMedia(in: source)
        }

        func textDidChange(_ notification: Notification) {
            guard !isRendering, let textView else { return }
            let markdown = MarkdownEditorTextRenderer.markdownString(from: textView.attributedString())
            renderedText = markdown
            text = markdown
            (textView as? MediaTextView)?.resizeToFitTextContent()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isRendering else { return }
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused = false
        }

        func updateMediaWidth(_ width: CGFloat) {
            let adjustedWidth = max(80, floor(width - 28))
            guard abs(adjustedWidth - mediaWidth) > 1 else { return }
            mediaWidth = adjustedWidth
            render(renderedText)
        }

        func updateLayout(contentSize: NSSize) {
            (textView as? MediaTextView)?.configureForVerticalScrolling(contentSize: contentSize)
            updateMediaWidth(contentSize.width)
        }

        func applyCursorEndRequestIfNeeded() {
            guard appliedCursorEndRequestID != cursorEndRequestID, let textView else { return }
            appliedCursorEndRequestID = cursorEndRequestID
            let end = textView.string.utf16.count
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(NSRange(location: end, length: 0))
        }

        func applyFocusIfNeeded() {
            guard isFocused,
                  let textView,
                  let window = textView.window,
                  window.firstResponder !== textView else {
                return
            }

            window.makeFirstResponder(textView)
        }

        fileprivate func mediaTextViewDidRequestPasteMedia(_ textView: MediaTextView) -> Bool {
            guard let relativePath = MediaAttachmentImporter.importFromPasteboard() else {
                return false
            }

            insertMedia(relativePath)
            didInsertMedia()
            return true
        }

        fileprivate func mediaTextView(_ textView: MediaTextView, didReceiveDrop pasteboard: NSPasteboard) -> Bool {
            guard let relativePath = MediaAttachmentImporter.importFromPasteboard(pasteboard) else {
                return false
            }

            insertMedia(relativePath)
            didInsertMedia()
            return true
        }

        fileprivate func mediaTextView(_ textView: MediaTextView, didRequestMarkdownWrapper wrapper: String) {
            Self.wrapSelection(in: textView, wrapper: wrapper)
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            render(renderedText)
        }

        private static func clamped(range: NSRange, length: Int) -> NSRange {
            NSRange(location: min(range.location, length), length: min(range.length, max(0, length - range.location)))
        }

        private static func wrapSelection(in textView: NSTextView, wrapper: String) {
            let selectedRange = textView.selectedRange()
            let nsString = textView.string as NSString
            let selectedText = selectedRange.length > 0 ? nsString.substring(with: selectedRange) : "text"
            let replacement = "\(wrapper)\(selectedText)\(wrapper)"

            textView.shouldChangeText(in: selectedRange, replacementString: replacement)
            textView.replaceCharacters(in: selectedRange, with: replacement)
            textView.didChangeText()

            if selectedRange.length == 0 {
                let cursorLocation = selectedRange.location + wrapper.utf16.count
                textView.setSelectedRange(NSRange(location: cursorLocation, length: selectedText.utf16.count))
            } else {
                textView.setSelectedRange(NSRange(location: selectedRange.location, length: replacement.utf16.count))
            }
        }

        private func preloadMissingMedia(in source: String) {
            let links = MarkdownEditorTextRenderer.imageLinksNeedingPreload(from: source, mediaWidth: mediaWidth)
            guard !links.isEmpty else { return }

            for link in links where !pendingMediaLoads.contains(link) {
                pendingMediaLoads.insert(link)
                let pixelWidth = mediaWidth * 2

                DispatchQueue.global(qos: .utility).async { [weak self] in
                    _ = VaultStore.image(forMediaLink: link, maxPixelWidth: pixelWidth)
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.pendingMediaLoads.remove(link)
                        if self.renderedText == source {
                            self.render(source)
                        }
                    }
                }
            }
        }
    }
}

enum MarkdownEditorTextRenderer {
    private static let inlineCodeRegex = try? NSRegularExpression(pattern: #"`([^`\n]+)`"#)
    private static let highlightRegex = try? NSRegularExpression(pattern: #"==([^=\n]+)=="#)
    private static let boldRegex = try? NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#)
    private static let strikethroughRegex = try? NSRegularExpression(pattern: #"~~([^~\n]+)~~"#)
    private static let italicRegex = try? NSRegularExpression(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
    static func attributedString(from source: String, mediaWidth: CGFloat, activeLineIndex: Int? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = source.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let isActiveLine = index == activeLineIndex

            if let media = EmbeddedMedia(markdownLine: line),
               media.type == .image,
               let image = cachedImage(for: media.link, maxWidth: mediaWidth) {
                let attachment = MarkdownMediaTextAttachment(markdown: line, image: image)
                if isActiveLine {
                    result.append(attributedLine(line, revealSyntax: true))
                    result.append(NSAttributedString(string: "\n", attributes: previewOnlyAttributes))
                    attachment.isPreviewOnly = true
                }
                result.append(NSAttributedString(attachment: attachment))
            } else {
                result.append(attributedLine(line, revealSyntax: isActiveLine))
            }

            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: typingAttributes))
            }
        }

        return result
    }

    static func imageLinksNeedingPreload(from source: String, mediaWidth: CGFloat) -> [String] {
        var links: [String] = []
        let pixelWidth = mediaWidth * 2

        for line in source.components(separatedBy: .newlines) {
            guard let media = EmbeddedMedia(markdownLine: line), media.type == .image else {
                continue
            }

            if VaultStore.cachedImage(forMediaLink: media.link, maxPixelWidth: pixelWidth) == nil {
                links.append(media.link)
            }
        }

        return links
    }

    static func markdownString(from attributedString: NSAttributedString) -> String {
        var markdown = ""
        attributedString.enumerateAttributes(
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { attributes, range, _ in
            if attributes[.markdownPreviewOnly] != nil {
                return
            }

            if let attachment = attributes[.attachment] as? MarkdownMediaTextAttachment {
                if attachment.isPreviewOnly {
                    return
                }
                markdown += attachment.markdown
            } else {
                markdown += (attributedString.string as NSString).substring(with: range)
            }
        }
        return markdown
    }

    static var typingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.textColor
        ]
    }

    private static var previewOnlyAttributes: [NSAttributedString.Key: Any] {
        typingAttributes.merging([.markdownPreviewOnly: true]) { current, _ in current }
    }

    private static func attributedLine(_ line: String, revealSyntax: Bool) -> NSAttributedString {
        let attributedLine = NSMutableAttributedString(string: line, attributes: blockAttributes(for: line))
        if !revealSyntax, let headingMarkerRange = headingMarkerRange(in: line) {
            hideSyntaxRanges([headingMarkerRange], in: attributedLine)
        }
        applyInlineStyles(to: attributedLine, in: line, revealSyntax: revealSyntax)
        return attributedLine
    }

    private static func blockAttributes(for line: String) -> [NSAttributedString.Key: Any] {
        if let level = headingLevel(in: line) {
            return headingAttributes(level: level)
        }

        if line.trimmingCharacters(in: .whitespaces).hasPrefix("> ") {
            return [
                .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 16), toHaveTrait: .italicFontMask),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        }

        return typingAttributes
    }

    private static func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let sizes: [Int: CGFloat] = [
            1: 26,
            2: 23,
            3: 20,
            4: 18,
            5: 17,
            6: 16
        ]

        return [
            .font: NSFont.systemFont(ofSize: sizes[level] ?? 16, weight: .semibold),
            .foregroundColor: NSColor.textColor
        ]
    }

    private static func applyInlineStyles(to attributedLine: NSMutableAttributedString, in line: String, revealSyntax: Bool) {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        apply(regex: inlineCodeRegex, to: attributedLine, in: line) { _, range in
            let fontSize = font(at: range.location, in: attributedLine)?.pointSize ?? 16
            attributedLine.addAttributes(
                [
                    .font: NSFont.monospacedSystemFont(ofSize: max(13, fontSize - 1), weight: .regular),
                    .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.75)
                ],
                range: range
            )
        }

        apply(regex: highlightRegex, to: attributedLine, in: line) { _, range in
            attributedLine.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.35),
                range: range
            )
            if !revealSyntax {
                hideSyntaxRanges([NSRange(location: range.location, length: 2), NSRange(location: range.upperBound - 2, length: 2)], in: attributedLine)
            }
        }

        apply(regex: boldRegex, to: attributedLine, in: line) { _, range in
            applyFontTrait(.boldFontMask, to: attributedLine, range: range)
            if !revealSyntax {
                hideSyntaxRanges([NSRange(location: range.location, length: 2), NSRange(location: range.upperBound - 2, length: 2)], in: attributedLine)
            }
        }

        apply(regex: strikethroughRegex, to: attributedLine, in: line) { _, range in
            attributedLine.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            if !revealSyntax {
                hideSyntaxRanges([NSRange(location: range.location, length: 2), NSRange(location: range.upperBound - 2, length: 2)], in: attributedLine)
            }
        }

        apply(regex: italicRegex, to: attributedLine, in: line) { _, range in
            applyFontTrait(.italicFontMask, to: attributedLine, range: range)
            if !revealSyntax {
                hideSyntaxRanges([NSRange(location: range.location, length: 1), NSRange(location: range.upperBound - 1, length: 1)], in: attributedLine)
            }
        }

        guard fullRange.length == attributedLine.length else { return }
    }

    private static func apply(
        regex: NSRegularExpression?,
        to attributedLine: NSMutableAttributedString,
        in line: String,
        body: (NSTextCheckingResult, NSRange) -> Void
    ) {
        guard let regex else { return }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        for match in regex.matches(in: line, range: range) {
            body(match, match.range)
        }
    }

    private static func applyFontTrait(
        _ trait: NSFontTraitMask,
        to attributedLine: NSMutableAttributedString,
        range: NSRange
    ) {
        guard let currentFont = font(at: range.location, in: attributedLine) else { return }
        let convertedFont = NSFontManager.shared.convert(currentFont, toHaveTrait: trait)
        attributedLine.addAttribute(.font, value: convertedFont, range: range)
    }

    private static func font(at location: Int, in attributedLine: NSAttributedString) -> NSFont? {
        guard attributedLine.length > 0 else { return nil }
        let safeLocation = min(max(location, 0), attributedLine.length - 1)
        return attributedLine.attribute(.font, at: safeLocation, effectiveRange: nil) as? NSFont
    }

    private static func hideSyntaxRanges(_ ranges: [NSRange], in attributedLine: NSMutableAttributedString) {
        for range in ranges where NSMaxRange(range) <= attributedLine.length {
            attributedLine.addAttributes(
                [
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 1)
                ],
                range: range
            )
        }
    }

    private static func headingMarkerRange(in line: String) -> NSRange? {
        let nsLine = line as NSString
        var markerStart = 0
        let hash = Character("#").utf16.first ?? 0
        let space = Character(" ").utf16.first ?? 0

        while markerStart < nsLine.length {
            let scalar = UnicodeScalar(Int(nsLine.character(at: markerStart)))
            guard let scalar, CharacterSet.whitespaces.contains(scalar) else { break }
            markerStart += 1
        }

        var level = 0
        while markerStart + level < nsLine.length,
              nsLine.character(at: markerStart + level) == hash {
            level += 1
        }

        guard (1...6).contains(level),
              markerStart + level < nsLine.length,
              nsLine.character(at: markerStart + level) == space else {
            return nil
        }

        return NSRange(location: markerStart, length: level + 1)
    }

    private static func headingLevel(in line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0

        for character in trimmed {
            if character == "#" {
                level += 1
                continue
            }

            guard character == " ", (1...6).contains(level) else {
                return nil
            }

            return level
        }

        return nil
    }

    private static func cachedImage(for link: String, maxWidth: CGFloat) -> NSImage? {
        VaultStore.cachedImage(forMediaLink: link, maxPixelWidth: maxWidth * 2)
    }
}

private final class MediaScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

private protocol MediaTextViewDelegate: AnyObject {
    func mediaTextViewDidRequestPasteMedia(_ textView: MediaTextView) -> Bool
    func mediaTextView(_ textView: MediaTextView, didReceiveDrop pasteboard: NSPasteboard) -> Bool
}

private protocol MarkdownCommandTextViewDelegate: AnyObject {
    func mediaTextView(_ textView: MediaTextView, didRequestMarkdownWrapper wrapper: String)
}

final class MediaTextView: NSTextView {
    fileprivate weak var mediaDelegate: MediaTextViewDelegate?
    fileprivate weak var markdownCommandDelegate: MarkdownCommandTextViewDelegate?
    private var retainedTextContentStorage: NSTextContentStorage?

    init() {
        let contentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )

        contentStorage.addTextLayoutManager(textLayoutManager)
        textLayoutManager.textContainer = textContainer

        super.init(frame: .zero, textContainer: textContainer)
        retainedTextContentStorage = contentStorage
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setRenderedAttributedString(_ attributedString: NSAttributedString) {
        if let textContentStorage = retainedTextContentStorage ?? textContentStorage {
            textContentStorage.attributedString = attributedString
        } else {
            textStorage?.setAttributedString(attributedString)
        }
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
        let usedRect: CGRect
        if let textLayoutManager {
            textLayoutManager.ensureLayout(
                for: CGRect(
                    origin: .zero,
                    size: CGSize(width: max(80, frame.width), height: CGFloat.greatestFiniteMagnitude)
                )
            )
            usedRect = textLayoutManager.usageBoundsForTextContainer
        } else if let layoutManager, let textContainer {
            layoutManager.ensureLayout(for: textContainer)
            usedRect = layoutManager.usedRect(for: textContainer)
        } else {
            return
        }

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
        case "s":
            markdownCommandDelegate?.mediaTextView(self, didRequestMarkdownWrapper: "~~")
            return true
        case "h":
            markdownCommandDelegate?.mediaTextView(self, didRequestMarkdownWrapper: "==")
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private final class MarkdownMediaTextAttachment: NSTextAttachment {
    let markdown: String
    var isPreviewOnly = false

    init(markdown: String, image: NSImage) {
        self.markdown = markdown
        super.init(data: nil, ofType: nil)
        attachmentCell = NSTextAttachmentCell(imageCell: image)
    }

    required init?(coder: NSCoder) {
        markdown = ""
        super.init(coder: coder)
    }
}

private extension NSAttributedString.Key {
    static let markdownPreviewOnly = NSAttributedString.Key("markdownPreviewOnly")
}
