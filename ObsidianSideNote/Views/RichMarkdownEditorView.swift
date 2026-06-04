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

        func mediaTextViewDidRequestPasteMedia(_ textView: MediaTextView) -> Bool {
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

        func mediaTextView(_ textView: MediaTextView, didReceiveDrop pasteboard: NSPasteboard) -> Bool {
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

        func mediaTextView(_ textView: MediaTextView, didRequestMarkdownWrapper wrapper: String) {
            MarkdownEditorCommandApplier.wrapSelection(in: textView, wrapper: wrapper)
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            render(renderedText)
        }

        func mediaTextView(_ textView: MediaTextView, didRequestTaskToggleAtVisibleLocation location: Int) {
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

        private func apply(_ command: MarkdownEditorCommand, in textView: NSTextView) {
            MarkdownEditorCommandApplier.apply(command, in: textView)
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
