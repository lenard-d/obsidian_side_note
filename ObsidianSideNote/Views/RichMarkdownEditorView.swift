import AppKit
import STTextView
import SwiftUI

struct RichMarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @Binding var focusRequestID: Int
    @Binding var cursorEndRequestID: Int
    @Binding var commandRequest: MarkdownEditorCommandRequest?
    let insertMedia: (String) -> Void
    let didInsertMedia: () -> Void
    private let horizontalEditorPadding: CGFloat = 10
    private let topEditorPadding: CGFloat = 8

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: $isFocused,
            focusRequestID: $focusRequestID,
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
        scrollView.configureEditorTopPadding(topEditorPadding)
        scrollView.focusTextView = { [weak coordinator = context.coordinator] in
            coordinator?.focusEditorAtEnd()
        }
        scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let scrollView else { return }
            coordinator?.updateLayout(contentSize: scrollView.contentSize)
        }

        let textView = MediaTextView()
        textView.textDelegate = context.coordinator
        textView.mediaDelegate = context.coordinator
        textView.markdownCommandDelegate = context.coordinator
        textView.taskListDelegate = context.coordinator
        textView.listEditingDelegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .textColor
        textView.configureHorizontalEditorPadding(horizontalEditorPadding)
        textView.configureForVerticalScrolling(contentSize: NSSize(width: 560, height: 320))
        textView.registerForDraggedTypes(MediaAttachmentImporter.pasteboardTypes)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.observeEditingNotifications(for: textView)
        context.coordinator.observeFocusRequests()
        context.coordinator.render(text)
        DispatchQueue.main.async {
            context.coordinator.applyFocusIfNeeded()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if context.coordinator.renderedText != text {
            context.coordinator.render(text)
        }
        context.coordinator.applyFocusIfNeeded()
        context.coordinator.applyFocusRequestIfNeeded()
        context.coordinator.applyCursorEndRequestIfNeeded()
        context.coordinator.applyCommandRequestIfNeeded()
    }

    final class Coordinator: NSObject, STTextViewDelegate, MediaTextViewDelegate, MarkdownCommandTextViewDelegate, TaskListTextViewDelegate, MarkdownListEditingTextViewDelegate {
        @Binding private var text: String
        @FocusState.Binding private var isFocused: Bool
        @Binding private var focusRequestID: Int
        @Binding private var cursorEndRequestID: Int
        @Binding private var commandRequest: MarkdownEditorCommandRequest?
        private let insertMedia: (String) -> Void
        private let didInsertMedia: () -> Void
        fileprivate weak var textView: MediaTextView?
        fileprivate var renderedText = ""
        private var pendingSelectionAfterRender: NSRange?
        private var mediaWidth: CGFloat = 560
        private var isRendering = false
        private var appliedFocusRequestID = 0
        private var appliedCursorEndRequestID = 0
        private var appliedCommandRequestID = 0
        private var pendingMediaLoads: Set<String> = []
        private var editingNotificationObservers: [NSObjectProtocol] = []
        private var focusRequestObserver: NSObjectProtocol?

        init(
            text: Binding<String>,
            isFocused: FocusState<Bool>.Binding,
            focusRequestID: Binding<Int>,
            cursorEndRequestID: Binding<Int>,
            commandRequest: Binding<MarkdownEditorCommandRequest?>,
            insertMedia: @escaping (String) -> Void,
            didInsertMedia: @escaping () -> Void
        ) {
            _text = text
            _isFocused = isFocused
            _focusRequestID = focusRequestID
            _cursorEndRequestID = cursorEndRequestID
            _commandRequest = commandRequest
            self.insertMedia = insertMedia
            self.didInsertMedia = didInsertMedia
        }

        deinit {
            for observer in editingNotificationObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            if let focusRequestObserver {
                NotificationCenter.default.removeObserver(focusRequestObserver)
            }
        }

        func render(_ source: String) {
            guard let textView else { return }
            isRendering = true
            renderedText = source
            let selectedRange = pendingSelectionAfterRender ?? textView.selectedRange()
            pendingSelectionAfterRender = nil
            textView.setAttributedString(
                MarkdownEditorTextRenderer.attributedString(
                    from: source,
                    mediaWidth: mediaWidth
                )
            )
            textView.typingAttributes = MarkdownEditorTextRenderer.typingAttributes
            textView.setSelectedRange(Self.clamped(range: selectedRange, length: textView.string.utf16.count))
            textView.resizeToFitTextContent()
            isRendering = false

            applyFocusIfNeeded()

            preloadMissingMedia(in: source)
        }

        func textViewDidChangeText(_ notification: Notification) {
            guard !isRendering, let textView else { return }
            let markdown = MarkdownEditorTextRenderer.markdownString(from: textView.attributedString())
            renderedText = markdown
            text = markdown
            textView.resizeToFitTextContent()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isRendering, let textView else { return }
            syncRenderedTextFromTextViewIfNeeded(textView)
        }

        private func syncRenderedTextFromTextViewIfNeeded(_ textView: MediaTextView) {
            let markdown = MarkdownEditorTextRenderer.markdownString(from: textView.attributedString())
            guard markdown != renderedText else { return }
            renderedText = markdown
            text = markdown
        }

        func observeEditingNotifications(for textView: MediaTextView) {
            for observer in editingNotificationObservers {
                NotificationCenter.default.removeObserver(observer)
            }

            let center = NotificationCenter.default
            editingNotificationObservers = [
                center.addObserver(
                    forName: NSText.didBeginEditingNotification,
                    object: textView,
                    queue: .main
                ) { [weak self] notification in
                    self?.textViewDidBeginEditing(notification)
                },
                center.addObserver(
                    forName: NSText.didEndEditingNotification,
                    object: textView,
                    queue: .main
                ) { [weak self] notification in
                    self?.textViewDidEndEditing(notification)
                },
            ]
        }

        private func textViewDidBeginEditing(_ notification: Notification) {
            isFocused = true
        }

        private func textViewDidEndEditing(_ notification: Notification) {
            guard !isRendering else { return }
            isFocused = false
        }

        func observeFocusRequests() {
            if let focusRequestObserver {
                NotificationCenter.default.removeObserver(focusRequestObserver)
            }

            focusRequestObserver = NotificationCenter.default.addObserver(
                forName: .editorShouldFocus,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                if let targetWindow = notification.object as? NSWindow,
                   let textWindow = self.textView?.window,
                   targetWindow !== textWindow {
                    return
                }

                self.focusEditorAtEnd()
                DispatchQueue.main.async { [weak self] in
                    self?.focusEditorAtEnd()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                    self?.focusEditorAtEnd()
                }
            }
        }

        func updateMediaWidth(_ width: CGFloat) {
            let adjustedWidth = max(80, floor(width - (textView?.horizontalEditorPadding ?? 0) * 2))
            guard abs(adjustedWidth - mediaWidth) > 1 else { return }
            mediaWidth = adjustedWidth
            render(renderedText)
        }

        func updateLayout(contentSize: NSSize) {
            textView?.configureForVerticalScrolling(contentSize: contentSize)
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
            textViewDidChangeText(Notification(name: NSText.didChangeNotification, object: textView))
            render(renderedText)
        }

        func applyFocusIfNeeded() {
            guard isFocused,
                  let textView,
                  let window = textView.window,
                  window.firstResponder !== textView else {
                return
            }

            focusEditorAtEnd()
        }

        func applyFocusRequestIfNeeded() {
            guard appliedFocusRequestID != focusRequestID else { return }
            appliedFocusRequestID = focusRequestID
            focusEditorAtEnd()
        }

        func focusEditorAtEnd() {
            guard let textView else { return }
            isFocused = true
            if let window = textView.window {
                window.endEditing(for: nil)
                window.makeFirstResponder(textView)
            }
            let end = textView.string.utf16.count
            textView.setSelectedRange(NSRange(location: end, length: 0))
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
            textViewDidChangeText(Notification(name: NSText.didChangeNotification, object: textView))
            render(renderedText)
        }

        func mediaTextView(_ textView: MediaTextView, didRequestTaskToggleAtVisibleLocation location: Int) {
            let lineIndex = MarkdownEditingEngine.lineIndex(in: textView.string, at: location)
            guard let toggledText = MarkdownEditingEngine.toggledTaskListItem(in: renderedText, lineIndex: lineIndex) else {
                return
            }

            let previousText = renderedText
            textView.undoManager?.registerUndo(withTarget: self) { coordinator in
                coordinator.replaceMarkdown(previousText)
            }
            replaceMarkdown(toggledText)
        }

        func mediaTextViewDidRequestSmartNewline(_ textView: MediaTextView) -> Bool {
            syncRenderedTextFromTextViewIfNeeded(textView)
            guard let edit = MarkdownEditingEngine.smartNewline(
                in: renderedText,
                selectedRange: sourceSelectionRange(from: textView)
            ) else {
                return false
            }

            apply(edit, in: textView)
            return true
        }

        func mediaTextViewDidRequestIndent(_ textView: MediaTextView) -> Bool {
            syncRenderedTextFromTextViewIfNeeded(textView)
            guard let edit = MarkdownEditingEngine.indentLines(
                in: renderedText,
                selectedRange: sourceSelectionRange(from: textView)
            ) else {
                return false
            }

            apply(edit, in: textView)
            return true
        }

        func mediaTextViewDidRequestOutdent(_ textView: MediaTextView) -> Bool {
            syncRenderedTextFromTextViewIfNeeded(textView)
            guard let edit = MarkdownEditingEngine.outdentLines(
                in: renderedText,
                selectedRange: sourceSelectionRange(from: textView)
            ) else {
                return false
            }

            apply(edit, in: textView)
            return true
        }

        private static func clamped(range: NSRange, length: Int) -> NSRange {
            NSRange(location: min(range.location, length), length: min(range.length, max(0, length - range.location)))
        }

        private func apply(_ command: MarkdownEditorCommand, in textView: MediaTextView) {
            MarkdownEditorCommandApplier.apply(command, in: textView)
        }

        private func apply(_ edit: MarkdownEditingEngine.Edit, in textView: MediaTextView) {
            let previousText = renderedText
            textView.undoManager?.registerUndo(withTarget: self) { coordinator in
                coordinator.replaceMarkdown(previousText)
            }
            pendingSelectionAfterRender = edit.selectedRange
            replaceMarkdown(edit.markdown)
        }

        private func sourceSelectionRange(from textView: MediaTextView) -> NSRange {
            textView.selectedRange()
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
