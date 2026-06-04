import AppKit
import SwiftUI

struct RichMarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @Binding var cursorEndRequestID: Int
    @Binding var commandRequest: MarkdownEditorCommandRequest?
    let insertMedia: (String) -> Void
    let didInsertMedia: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: $isFocused,
            cursorEndRequestID: $cursorEndRequestID,
            commandRequest: $commandRequest,
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
        textView.taskListDelegate = context.coordinator
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
        context.coordinator.applyCommandRequestIfNeeded()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, MediaTextViewDelegate, MarkdownCommandTextViewDelegate, TaskListTextViewDelegate {
        @Binding private var text: String
        @FocusState.Binding private var isFocused: Bool
        @Binding private var cursorEndRequestID: Int
        @Binding private var commandRequest: MarkdownEditorCommandRequest?
        private let insertMedia: (String) -> Void
        private let didInsertMedia: () -> Void
        fileprivate weak var textView: NSTextView?
        fileprivate var renderedText = ""
        private var activeLineIndex: Int?
        private var pendingSelectionAfterRender: NSRange?
        private var mediaWidth: CGFloat = 560
        private var isRendering = false
        private var appliedCursorEndRequestID = 0
        private var appliedCommandRequestID = 0
        private var pendingMediaLoads: Set<String> = []

        init(
            text: Binding<String>,
            isFocused: FocusState<Bool>.Binding,
            cursorEndRequestID: Binding<Int>,
            commandRequest: Binding<MarkdownEditorCommandRequest?>,
            insertMedia: @escaping (String) -> Void,
            didInsertMedia: @escaping () -> Void
        ) {
            _text = text
            _isFocused = isFocused
            _cursorEndRequestID = cursorEndRequestID
            _commandRequest = commandRequest
            self.insertMedia = insertMedia
            self.didInsertMedia = didInsertMedia
        }

        func render(_ source: String) {
            guard let textView else { return }
            isRendering = true
            renderedText = source
            let selectedRange = pendingSelectionAfterRender ?? textView.selectedRange()
            pendingSelectionAfterRender = nil
            textView.textStorage?.setAttributedString(
                MarkdownEditorTextRenderer.attributedString(
                    from: source,
                    mediaWidth: mediaWidth,
                    activeLineIndex: activeLineIndex
                )
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
            guard !isRendering, let textView else { return }
            let selectedRange = textView.selectedRange()
            let lineIndex = Self.lineIndex(in: textView.string, at: selectedRange.location)
            guard activeLineIndex != lineIndex else { return }
            pendingSelectionAfterRender = Self.sourceSelectionRange(
                from: selectedRange,
                visibleText: textView.string,
                sourceText: renderedText,
                lineIndex: lineIndex
            )
            activeLineIndex = lineIndex
            render(renderedText)
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

        func applyCommandRequestIfNeeded() {
            guard let commandRequest,
                  commandRequest.id != appliedCommandRequestID,
                  let textView else {
                return
            }

            appliedCommandRequestID = commandRequest.id
            apply(commandRequest.command, in: textView)
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            render(renderedText)
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
            guard MediaAttachmentImporter.canImportFromPasteboard() else {
                return false
            }

            MediaAttachmentImporter.importFromPasteboard { [weak self] relativePath in
                DispatchQueue.main.async {
                    guard let self, let relativePath else { return }
                    self.insertMedia(relativePath)
                    self.didInsertMedia()
                }
            }
            return true
        }

        fileprivate func mediaTextView(_ textView: MediaTextView, didReceiveDrop pasteboard: NSPasteboard) -> Bool {
            guard MediaAttachmentImporter.canImportFromPasteboard(pasteboard) else {
                return false
            }

            MediaAttachmentImporter.importFromPasteboard(pasteboard) { [weak self] relativePath in
                DispatchQueue.main.async {
                    guard let self, let relativePath else { return }
                    self.insertMedia(relativePath)
                    self.didInsertMedia()
                }
            }
            return true
        }

        fileprivate func mediaTextView(_ textView: MediaTextView, didRequestMarkdownWrapper wrapper: String) {
            Self.wrapSelection(in: textView, wrapper: wrapper)
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            render(renderedText)
        }

        fileprivate func mediaTextView(_ textView: MediaTextView, didRequestTaskToggleAtVisibleLocation location: Int) {
            let lineIndex = Self.lineIndex(in: textView.string, at: location)
            guard let toggledText = MarkdownEditorTextRenderer.toggledTaskListItem(in: renderedText, lineIndex: lineIndex) else {
                return
            }

            let previousText = renderedText
            textView.undoManager?.registerUndo(withTarget: self) { coordinator in
                coordinator.replaceMarkdown(previousText)
            }
            replaceMarkdown(toggledText)
        }

        private static func clamped(range: NSRange, length: Int) -> NSRange {
            NSRange(location: min(range.location, length), length: min(range.length, max(0, length - range.location)))
        }

        private static func lineIndex(in string: String, at location: Int) -> Int {
            let clampedLocation = min(max(location, 0), (string as NSString).length)
            let prefix = (string as NSString).substring(to: clampedLocation)
            return prefix.reduce(0) { count, character in
                character == "\n" ? count + 1 : count
            }
        }

        private static func sourceSelectionRange(
            from visibleRange: NSRange,
            visibleText: String,
            sourceText: String,
            lineIndex: Int
        ) -> NSRange {
            let visibleLineStart = lineStartLocation(in: visibleText, lineIndex: lineIndex)
            let visibleOffset = max(0, visibleRange.location - visibleLineStart)
            let sourceLineStart = lineStartLocation(in: sourceText, lineIndex: lineIndex)
            let sourceLine = line(at: lineIndex, in: sourceText)
            let sourceOffset = MarkdownEditorTextRenderer.sourceOffset(forVisibleOffset: visibleOffset, in: sourceLine)
            return NSRange(location: sourceLineStart + sourceOffset, length: 0)
        }

        private static func lineStartLocation(in string: String, lineIndex: Int) -> Int {
            guard lineIndex > 0 else { return 0 }
            var currentLine = 0
            var utf16Location = 0

            for character in string {
                if currentLine == lineIndex {
                    return utf16Location
                }
                utf16Location += character.utf16.count
                if character == "\n" {
                    currentLine += 1
                }
            }

            return utf16Location
        }

        private static func line(at lineIndex: Int, in string: String) -> String {
            let lines = string.components(separatedBy: .newlines)
            guard lines.indices.contains(lineIndex) else { return "" }
            return lines[lineIndex]
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

        private func apply(_ command: MarkdownEditorCommand, in textView: NSTextView) {
            switch command {
            case let .wrap(wrapper):
                Self.wrapSelection(in: textView, wrapper: wrapper)
            case .insertLink:
                Self.replaceSelection(in: textView, with: "[link text](url)", selectedPlaceholder: "link text")
            case let .insertPrefix(prefix):
                Self.insertLinePrefix(prefix, in: textView)
            }
        }

        private static func replaceSelection(in textView: NSTextView, with replacement: String, selectedPlaceholder: String? = nil) {
            let selectedRange = textView.selectedRange()
            let text = textView.string as NSString
            let selectedText = selectedRange.length > 0 ? text.substring(with: selectedRange) : replacement
            let finalReplacement = selectedRange.length > 0 && selectedPlaceholder != nil
                ? replacement.replacingOccurrences(of: selectedPlaceholder ?? "", with: selectedText)
                : selectedText

            textView.shouldChangeText(in: selectedRange, replacementString: finalReplacement)
            textView.replaceCharacters(in: selectedRange, with: finalReplacement)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: selectedRange.location, length: finalReplacement.utf16.count))
        }

        private static func insertLinePrefix(_ prefix: String, in textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            let nsString = textView.string as NSString
            let lineRange = nsString.lineRange(for: selectedRange)
            let replacement = prefix + nsString.substring(with: lineRange)

            textView.shouldChangeText(in: lineRange, replacementString: replacement)
            textView.replaceCharacters(in: lineRange, with: replacement)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: selectedRange.location + prefix.utf16.count, length: selectedRange.length))
        }

        private func replaceMarkdown(_ markdown: String) {
            renderedText = markdown
            text = markdown
            render(markdown)
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
    private static let italicRegex = try? NSRegularExpression(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
    private static let strikethroughRegex = try? NSRegularExpression(pattern: #"~~([^~\n]+)~~"#)
    private static let taskMarkerRegex = try? NSRegularExpression(pattern: #"^(\s*[-*+]\s+\[[ xX]\]\s+)"#)
    @MainActor
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
        var restoredSourceLines: Set<ObjectIdentifier> = []
        attributedString.enumerateAttributes(
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { attributes, range, _ in
            if attributes[.markdownPreviewOnly] != nil {
                return
            }

            if let sourceLine = attributes[.markdownSourceLine] as? MarkdownSourceLine {
                let id = ObjectIdentifier(sourceLine)
                guard !restoredSourceLines.contains(id) else { return }
                restoredSourceLines.insert(id)
                markdown += sourceLine.markdown
            } else if let attachment = attributes[.attachment] as? MarkdownMediaTextAttachment {
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

    static func sourceOffset(forVisibleOffset visibleOffset: Int, in sourceLine: String) -> Int {
        if let taskMarkerRange = taskMarkerRange(in: sourceLine) {
            let markerEnd = taskMarkerRange.upperBound
            return markerEnd + max(0, visibleOffset - taskCheckboxPrefixLength)
        }

        let nsLine = sourceLine as NSString
        let hiddenRanges = hiddenSyntaxRanges(in: sourceLine)
        var visibleUTF16Offset = 0
        var sourceUTF16Offset = 0

        while sourceUTF16Offset < nsLine.length {
            if let hiddenRange = hiddenRanges.first(where: { $0.range.location == sourceUTF16Offset }) {
                if hiddenRange.skipAtBoundary || visibleUTF16Offset < visibleOffset {
                    sourceUTF16Offset = hiddenRange.range.upperBound
                    continue
                }
                return sourceUTF16Offset
            }

            guard visibleUTF16Offset < visibleOffset else {
                return sourceUTF16Offset
            }

            sourceUTF16Offset += 1
            visibleUTF16Offset += 1
        }

        return sourceUTF16Offset
    }

    static func toggledTaskListItem(in source: String, lineIndex: Int) -> String? {
        var lines = source.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex),
              let taskMarkerRange = taskMarkerRange(in: lines[lineIndex]) else {
            return nil
        }

        let nsLine = lines[lineIndex] as NSString
        let marker = nsLine.substring(with: taskMarkerRange)
        let toggledMarker = taskMarkerIsChecked(marker)
            ? marker.replacingOccurrences(of: #"\[[xX]\]"#, with: "[ ]", options: .regularExpression)
            : marker.replacingOccurrences(of: #"\[ \]"#, with: "[x]", options: .regularExpression)
        lines[lineIndex] = nsLine.replacingCharacters(in: taskMarkerRange, with: toggledMarker)
        return lines.joined(separator: "\n")
    }

    private struct HiddenSyntaxRange {
        let range: NSRange
        let skipAtBoundary: Bool
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
        if !revealSyntax, let hiddenLine = hiddenSyntaxLine(from: line) {
            return hiddenLine
        }

        let attributedLine = NSMutableAttributedString(string: line, attributes: blockAttributes(for: line))
        applyInlineStyles(to: attributedLine, in: line, revealSyntax: revealSyntax)
        return attributedLine
    }

    private static func hiddenSyntaxLine(from line: String) -> NSAttributedString? {
        guard let renderedLine = renderedLineByRemovingSyntax(from: line),
              renderedLine != line else {
            return nil
        }

        let sourceLine = MarkdownSourceLine(markdown: line)
        let attributedLine = NSMutableAttributedString(
            string: renderedLine,
            attributes: blockAttributes(for: line).merging([.markdownSourceLine: sourceLine]) { current, _ in current }
        )
        applyHiddenInlineStyles(to: attributedLine, sourceLine: line, renderedLine: renderedLine)
        return attributedLine
    }

    private static func renderedLineByRemovingSyntax(from line: String) -> String? {
        if let headingMarkerRange = headingMarkerRange(in: line) {
            let nsLine = line as NSString
            return nsLine.replacingCharacters(in: headingMarkerRange, with: "")
        }

        if let taskMarkerRange = taskMarkerRange(in: line) {
            let nsLine = line as NSString
            let marker = nsLine.substring(with: taskMarkerRange)
            let indentation = leadingWhitespace(in: marker)
            let checkbox = taskMarkerIsChecked(marker) ? "\u{2611}" : "\u{2610}"
            return indentation + checkbox + " " + nsLine.substring(from: taskMarkerRange.upperBound)
        }

        var renderedLine = line
        renderedLine = renderedLine.replacingOccurrences(of: #"==([^=\n]+)=="#, with: "$1", options: .regularExpression)
        renderedLine = renderedLine.replacingOccurrences(of: #"\*\*([^*\n]+)\*\*"#, with: "$1", options: .regularExpression)
        renderedLine = renderedLine.replacingOccurrences(of: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#, with: "$1", options: .regularExpression)
        renderedLine = renderedLine.replacingOccurrences(of: #"~~([^~\n]+)~~"#, with: "$1", options: .regularExpression)
        renderedLine = renderedLine.replacingOccurrences(of: #"`([^`\n]+)`"#, with: "$1", options: .regularExpression)
        return renderedLine
    }

    private static func applyHiddenInlineStyles(
        to attributedLine: NSMutableAttributedString,
        sourceLine: String,
        renderedLine: String
    ) {
        if let taskMarkerRange = taskMarkerRange(in: sourceLine) {
            let marker = (sourceLine as NSString).substring(with: taskMarkerRange)
            let indentationLength = (leadingWhitespace(in: marker) as NSString).length
            let checkboxRange = NSRange(location: indentationLength, length: 1)
            if checkboxRange.upperBound <= attributedLine.length {
                attributedLine.addAttributes(
                    [
                        .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                        .foregroundColor: taskMarkerIsChecked(marker) ? NSColor.systemGreen : NSColor.secondaryLabelColor,
                        .markdownTaskCheckbox: true
                    ],
                    range: checkboxRange
                )
            }
        }

        var searchLocation = 0

        applyVisibleCapture(regex: inlineCodeRegex, sourceLine: sourceLine, renderedLine: renderedLine, searchLocation: &searchLocation) { range in
            let fontSize = font(at: range.location, in: attributedLine)?.pointSize ?? 16
            attributedLine.addAttributes(
                [
                    .font: NSFont.monospacedSystemFont(ofSize: max(13, fontSize - 1), weight: .regular),
                    .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.75)
                ],
                range: range
            )
        }

        searchLocation = 0
        applyVisibleCapture(regex: highlightRegex, sourceLine: sourceLine, renderedLine: renderedLine, searchLocation: &searchLocation) { range in
            attributedLine.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.35),
                range: range
            )
        }

        searchLocation = 0
        applyVisibleCapture(regex: boldRegex, sourceLine: sourceLine, renderedLine: renderedLine, searchLocation: &searchLocation) { range in
            applyFontTrait(.boldFontMask, to: attributedLine, range: range)
        }

        searchLocation = 0
        applyVisibleCapture(regex: italicRegex, sourceLine: sourceLine, renderedLine: renderedLine, searchLocation: &searchLocation) { range in
            applyFontTrait(.italicFontMask, to: attributedLine, range: range)
        }
    }

    private static func applyVisibleCapture(
        regex: NSRegularExpression?,
        sourceLine: String,
        renderedLine: String,
        searchLocation: inout Int,
        body: (NSRange) -> Void
    ) {
        guard let regex else { return }
        let sourceRange = NSRange(sourceLine.startIndex..<sourceLine.endIndex, in: sourceLine)
        let renderedNSString = renderedLine as NSString

        for match in regex.matches(in: sourceLine, range: sourceRange) {
            guard match.numberOfRanges > 1 else { continue }
            let visibleText = (sourceLine as NSString).substring(with: match.range(at: 1))
            let remainingRange = NSRange(
                location: min(searchLocation, renderedNSString.length),
                length: max(0, renderedNSString.length - min(searchLocation, renderedNSString.length))
            )
            let renderedRange = renderedNSString.range(of: visibleText, options: [], range: remainingRange)
            guard renderedRange.location != NSNotFound else { continue }
            body(renderedRange)
            searchLocation = renderedRange.upperBound
        }
    }

    private static func hiddenSyntaxRanges(in line: String) -> [HiddenSyntaxRange] {
        var ranges: [HiddenSyntaxRange] = []

        if let headingMarkerRange = headingMarkerRange(in: line) {
            ranges.append(HiddenSyntaxRange(range: headingMarkerRange, skipAtBoundary: true))
        }

        if let taskMarkerRange = taskMarkerRange(in: line) {
            ranges.append(HiddenSyntaxRange(range: taskMarkerRange, skipAtBoundary: true))
        }

        ranges.append(contentsOf: hiddenDelimiterRanges(regex: highlightRegex, markerLength: 2, in: line))
        ranges.append(contentsOf: hiddenDelimiterRanges(regex: boldRegex, markerLength: 2, in: line))
        ranges.append(contentsOf: hiddenDelimiterRanges(regex: strikethroughRegex, markerLength: 2, in: line))
        ranges.append(contentsOf: hiddenDelimiterRanges(regex: inlineCodeRegex, markerLength: 1, in: line))
        ranges.append(contentsOf: hiddenDelimiterRanges(regex: italicRegex, markerLength: 1, in: line))

        return ranges.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length > rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
    }

    private static func hiddenDelimiterRanges(
        regex: NSRegularExpression?,
        markerLength: Int,
        in line: String
    ) -> [HiddenSyntaxRange] {
        guard let regex else { return [] }
        let sourceRange = NSRange(line.startIndex..<line.endIndex, in: line)

        return regex.matches(in: line, range: sourceRange).flatMap { match -> [HiddenSyntaxRange] in
            guard match.range.length >= markerLength * 2 else { return [] }
            return [
                HiddenSyntaxRange(
                    range: NSRange(location: match.range.location, length: markerLength),
                    skipAtBoundary: true
                ),
                HiddenSyntaxRange(
                    range: NSRange(location: match.range.upperBound - markerLength, length: markerLength),
                    skipAtBoundary: false
                )
            ]
        }
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

    private static var taskCheckboxPrefixLength: Int {
        ("\u{2610} " as NSString).length
    }

    private static func taskMarkerRange(in line: String) -> NSRange? {
        guard let taskMarkerRegex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = taskMarkerRegex.firstMatch(in: line, range: range) else { return nil }
        return match.range(at: 1)
    }

    private static func taskMarkerIsChecked(_ marker: String) -> Bool {
        marker.range(of: #"\[[xX]\]"#, options: .regularExpression) != nil
    }

    private static func leadingWhitespace(in string: String) -> String {
        String(string.prefix { $0 == " " || $0 == "\t" })
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
        }

        apply(regex: boldRegex, to: attributedLine, in: line) { _, range in
            applyFontTrait(.boldFontMask, to: attributedLine, range: range)
        }

        apply(regex: italicRegex, to: attributedLine, in: line) { _, range in
            applyFontTrait(.italicFontMask, to: attributedLine, range: range)
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

private protocol TaskListTextViewDelegate: AnyObject {
    func mediaTextView(_ textView: MediaTextView, didRequestTaskToggleAtVisibleLocation location: Int)
}

final class MediaTextView: NSTextView {
    fileprivate weak var mediaDelegate: MediaTextViewDelegate?
    fileprivate weak var markdownCommandDelegate: MarkdownCommandTextViewDelegate?
    fileprivate weak var taskListDelegate: TaskListTextViewDelegate?

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

private final class MarkdownSourceLine {
    let markdown: String

    init(markdown: String) {
        self.markdown = markdown
    }
}

private extension NSAttributedString.Key {
    static let markdownPreviewOnly = NSAttributedString.Key("markdownPreviewOnly")
    static let markdownSourceLine = NSAttributedString.Key("markdownSourceLine")
    static let markdownTaskCheckbox = NSAttributedString.Key("markdownTaskCheckbox")
}
