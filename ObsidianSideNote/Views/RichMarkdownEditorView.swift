import AppKit
import OSLog
import SwiftUI
import WebKit

struct RichMarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @Binding var focusRequestID: Int
    @Binding var cursorEndRequestID: Int
    let commandDispatcher: MarkdownEditorCommandDispatcher
    let insertMedia: (String) -> Void
    let didInsertMedia: () -> Void
    let didFailMediaImport: (MediaAttachmentImportError) -> Void
    let openWikiLink: (String, Bool) -> Void
    let openMarkdownLink: (String, Bool) -> Void
    let isReadOnly: Bool
    let linkPreviewHover: (LinkPreviewHoverEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: $isFocused,
            focusRequestID: $focusRequestID,
            cursorEndRequestID: $cursorEndRequestID,
            commandDispatcher: commandDispatcher,
            insertMedia: insertMedia,
            didInsertMedia: didInsertMedia,
            didFailMediaImport: didFailMediaImport,
            openWikiLink: openWikiLink,
            openMarkdownLink: openMarkdownLink,
            isReadOnly: isReadOnly,
            linkPreviewHover: linkPreviewHover
        )
    }

    func makeNSView(context: Context) -> MarkdownEditorWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "editor")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = MarkdownEditorWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.editorDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        if !isReadOnly {
            webView.registerForDraggedTypes(MediaAttachmentImporter.pasteboardTypes)
        }

        context.coordinator.webView = webView
        context.coordinator.observeFocusRequests()
        context.coordinator.loadEditor()

        return webView
    }

    func updateNSView(_ webView: MarkdownEditorWebView, context: Context) {
        context.coordinator.webView = webView
        context.coordinator.syncMediaEmbedsToWebViewIfNeeded(text)
        context.coordinator.syncMarkdownToWebViewIfNeeded(text)
        context.coordinator.syncAppearanceToWebViewIfNeeded()
        context.coordinator.syncReadOnlyModeToWebViewIfNeeded()
        context.coordinator.applyFocusIfNeeded()
        context.coordinator.applyFocusRequestIfNeeded()
        context.coordinator.applyCursorEndRequestIfNeeded()
    }

    static func dismantleNSView(_ webView: MarkdownEditorWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        coordinator.disconnectCommandDispatcher()
        coordinator.stopObserving()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, MarkdownEditorWebViewDelegate {
        @Binding private var text: String
        @FocusState.Binding private var isFocused: Bool
        @Binding private var focusRequestID: Int
        @Binding private var cursorEndRequestID: Int
        private let commandDispatcher: MarkdownEditorCommandDispatcher
        private let insertMedia: (String) -> Void
        private let didInsertMedia: () -> Void
        private let didFailMediaImport: (MediaAttachmentImportError) -> Void
        private let openWikiLink: (String, Bool) -> Void
        private let openMarkdownLink: (String, Bool) -> Void
        private let isReadOnly: Bool
        private let linkPreviewHover: (LinkPreviewHoverEvent) -> Void
        fileprivate weak var webView: MarkdownEditorWebView?
        private var loadedResourceURL: URL?
        private var isReady = false
        private var markdownInWebView = ""
        private var pendingMarkdownInWebView: String?
        private var pendingFocusAtEnd = false
        private var appliedAppearanceScheme: String?
        private var appliedReadOnlyMode: Bool?
        private var appliedFocusRequestID = 0
        private var appliedCursorEndRequestID = 0
        private var pendingCommand: MarkdownEditorCommand?
        private var mediaEmbedsInWebView: [String: String] = [:]
        private var textReplacementsInWebView: [String: String] = [:]
        private var imageEmbedDataURLCache: [String: String] = [:]
        private var focusRequestObserver: NSObjectProtocol?
        private static let maxInlineImageEmbeds = 24

        init(
            text: Binding<String>,
            isFocused: FocusState<Bool>.Binding,
            focusRequestID: Binding<Int>,
            cursorEndRequestID: Binding<Int>,
            commandDispatcher: MarkdownEditorCommandDispatcher,
            insertMedia: @escaping (String) -> Void,
            didInsertMedia: @escaping () -> Void,
            didFailMediaImport: @escaping (MediaAttachmentImportError) -> Void,
            openWikiLink: @escaping (String, Bool) -> Void,
            openMarkdownLink: @escaping (String, Bool) -> Void,
            isReadOnly: Bool,
            linkPreviewHover: @escaping (LinkPreviewHoverEvent) -> Void
        ) {
            _text = text
            _isFocused = isFocused
            _focusRequestID = focusRequestID
            _cursorEndRequestID = cursorEndRequestID
            self.commandDispatcher = commandDispatcher
            self.insertMedia = insertMedia
            self.didInsertMedia = didInsertMedia
            self.didFailMediaImport = didFailMediaImport
            self.openWikiLink = openWikiLink
            self.openMarkdownLink = openMarkdownLink
            self.isReadOnly = isReadOnly
            self.linkPreviewHover = linkPreviewHover
            super.init()
            commandDispatcher.connect(owner: self) { [weak self] command in
                self?.requestCommand(command)
            }
        }

        deinit {
            stopObserving()
        }

        func loadEditor() {
            guard loadedResourceURL == nil, let webView else { return }
            do {
                let html = try MarkdownEditorResource.bundledHTML()
                loadedResourceURL = Bundle.main.bundleURL
                webView.loadHTMLString(html, baseURL: nil)
            } catch {
                AppLogger.app.error("Failed to load bundled markdown editor: \(AppLogger.errorSummary(error))")
                assertionFailure("Missing or unreadable bundled MarkdownEditor resources")
            }
        }

        func syncMarkdownToWebViewIfNeeded(_ markdown: String) {
            guard isReady else { return }
            guard markdown != markdownInWebView else { return }
            guard markdown != pendingMarkdownInWebView else { return }

            pendingMarkdownInWebView = markdown
            callEditorFunction("setMarkdown", argument: markdown) { [weak self] error in
                guard let self else { return }
                if self.pendingMarkdownInWebView == markdown {
                    self.pendingMarkdownInWebView = nil
                }

                if let error {
                    AppLogger.app.error("Failed to sync markdown into web editor: \(AppLogger.errorSummary(error))")
                    return
                }

                self.markdownInWebView = markdown
            }
        }

        func syncAppearanceToWebViewIfNeeded() {
            guard isReady, let webView else { return }
            let isDark = webView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let scheme = isDark ? "dark" : "light"
            guard scheme != appliedAppearanceScheme else { return }

            appliedAppearanceScheme = scheme
            callEditorFunction("setAppearance", argument: scheme)
            syncTextReplacementsToWebViewIfNeeded()
        }

        func syncReadOnlyModeToWebViewIfNeeded() {
            guard isReady, appliedReadOnlyMode != isReadOnly else { return }
            appliedReadOnlyMode = isReadOnly
            callEditorFunction("setReadOnly", argument: isReadOnly)
        }

        private func syncTextReplacementsToWebViewIfNeeded() {
            guard isReady else { return }
            let replacements = Self.systemTextReplacements()
            guard replacements != textReplacementsInWebView else { return }
            textReplacementsInWebView = replacements
            callEditorFunction("setTextReplacements", argument: replacements)
        }

        func applyFocusIfNeeded() {
            guard isFocused else { return }
            focusEditor()
        }

        func applyFocusRequestIfNeeded() {
            guard isReady, appliedFocusRequestID != focusRequestID else { return }
            appliedFocusRequestID = focusRequestID
            focusEditorAtEnd()
        }

        func applyCursorEndRequestIfNeeded() {
            guard isReady, appliedCursorEndRequestID != cursorEndRequestID else { return }
            appliedCursorEndRequestID = cursorEndRequestID
            focusEditorAtEnd()
        }

        func requestCommand(_ command: MarkdownEditorCommand) {
            guard isReady else {
                pendingCommand = command
                return
            }
            applyWebCommand(webCommand(for: command))
        }

        func disconnectCommandDispatcher() {
            commandDispatcher.disconnect(owner: self)
        }

        private func applyPendingCommandIfNeeded() {
            guard isReady, let pendingCommand else { return }
            self.pendingCommand = nil
            applyWebCommand(webCommand(for: pendingCommand))
        }

        private func applyWebCommand(_ command: [String: Any]) {
            guard isReady, let webView else { return }
            let argumentJSON = Self.javaScriptLiteral(for: command)
            webView.evaluateJavaScript("window.editor?.applyCommand(\(argumentJSON));") { [weak self] result, error in
                guard let self else { return }
                if let error {
                    AppLogger.app.error("Markdown editor toolbar command failed: \(AppLogger.errorSummary(error))")
                    return
                }

                guard let markdown = result as? String else { return }
                self.pendingMarkdownInWebView = nil
                self.markdownInWebView = markdown
                if markdown != self.text {
                    self.text = markdown
                }
            }
        }

        func observeFocusRequests() {
            if focusRequestObserver != nil {
                stopObserving()
            }

            focusRequestObserver = NotificationCenter.default.addObserver(
                forName: .editorShouldFocus,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                if let targetWindow = notification.object as? NSWindow,
                   let editorWindow = self.webView?.window,
                   targetWindow !== editorWindow {
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

        func stopObserving() {
            if let focusRequestObserver {
                NotificationCenter.default.removeObserver(focusRequestObserver)
                self.focusRequestObserver = nil
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            switch type {
            case "ready":
                isReady = true
                AppLogger.app.info("Markdown editor ready")
                markdownInWebView = ""
                pendingMarkdownInWebView = nil
                appliedAppearanceScheme = nil
                appliedReadOnlyMode = nil
                mediaEmbedsInWebView = [:]
                textReplacementsInWebView = [:]
                syncMediaEmbedsToWebViewIfNeeded(text)
                syncMarkdownToWebViewIfNeeded(text)
                syncAppearanceToWebViewIfNeeded()
                syncReadOnlyModeToWebViewIfNeeded()
                applyFocusIfNeeded()
                applyFocusRequestIfNeeded()
                applyCursorEndRequestIfNeeded()
                applyPendingCommandIfNeeded()
                if pendingFocusAtEnd {
                    focusEditorAtEnd()
                }
            case "change":
                guard !isReadOnly else { return }
                guard let markdown = body["text"] as? String else { return }
                pendingMarkdownInWebView = nil
                markdownInWebView = markdown
                if markdown != text {
                    text = markdown
                }
            case "focus":
                isFocused = true
            case "blur":
                isFocused = false
            case "pasteMedia":
                importMediaFromPasteboard(.general)
            case "dropMedia":
                break
            case "wikiLink":
                guard let target = body["target"] as? String else { return }
                openWikiLink(target, body["newWindow"] as? Bool ?? false)
            case "markdownLink":
                guard let target = body["target"] as? String else { return }
                openMarkdownLink(target, body["newWindow"] as? Bool ?? false)
            case "linkPreviewHover":
                handleLinkPreviewHover(body)
            case "error":
                AppLogger.app.error("Markdown editor reported an internal error")
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            isReady = false
            appliedAppearanceScheme = nil
            appliedReadOnlyMode = nil
            mediaEmbedsInWebView = [:]
            textReplacementsInWebView = [:]
        }

        private func handleLinkPreviewHover(_ body: [String: Any]) {
            guard let phaseValue = body["phase"] as? String,
                  let phase = LinkPreviewHoverEvent.Phase(rawValue: phaseValue),
                  let sessionID = body["sessionID"] as? String,
                  let kindValue = body["kind"] as? String,
                  let kind = LinkPreviewHoverEvent.LinkKind(rawValue: kindValue),
                  let target = body["target"] as? String,
                  let anchor = body["anchor"] as? [String: Any],
                  let x = (anchor["x"] as? NSNumber)?.doubleValue,
                  let y = (anchor["y"] as? NSNumber)?.doubleValue,
                  let width = (anchor["width"] as? NSNumber)?.doubleValue,
                  let height = (anchor["height"] as? NSNumber)?.doubleValue,
                  let webView,
                  let window = webView.window else {
                return
            }

            let localRect = NSRect(
                x: x,
                y: webView.bounds.height - y - height,
                width: width,
                height: height
            )
            let windowRect = webView.convert(localRect, to: nil)
            let screenRect = window.convertToScreen(windowRect)
            linkPreviewHover(
                LinkPreviewHoverEvent(
                    phase: phase,
                    sessionID: sessionID,
                    kind: kind,
                    target: target,
                    anchorScreenRect: screenRect
                )
            )
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            isReady = false
            AppLogger.app.error("Markdown editor navigation failed: \(AppLogger.errorSummary(error))")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            isReady = false
            AppLogger.app.error("Markdown editor provisional navigation failed: \(AppLogger.errorSummary(error))")
        }

        func markdownEditorWebViewDidRequestPasteMedia(_ webView: MarkdownEditorWebView) -> Bool {
            guard MediaAttachmentImporter.canImportFromPasteboard() else {
                return false
            }

            importMediaFromPasteboard(.general)
            return true
        }

        func markdownEditorWebView(_ webView: MarkdownEditorWebView, didReceiveDrop pasteboard: NSPasteboard) -> Bool {
            guard MediaAttachmentImporter.canImportFromPasteboard(pasteboard) else {
                return false
            }

            importMediaFromPasteboard(pasteboard)
            return true
        }

        private func importMediaFromPasteboard(_ pasteboard: NSPasteboard) {
            MediaAttachmentImporter.importFromPasteboard(pasteboard) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case let .success(relativePath):
                        self.insertMediaLink(relativePath)
                    case let .failure(error):
                        self.didFailMediaImport(error)
                    }
                }
            }
        }

        private func insertMediaLink(_ relativePath: String) {
            let insertion = "![[\(relativePath)]]"
            if isReady {
                ensureMediaEmbedSource(for: relativePath)
                insertMediaEmbedInWebEditor(insertion, fallbackRelativePath: relativePath)
            } else {
                insertMedia(relativePath)
            }
            didInsertMedia()
        }

        func syncMediaEmbedsToWebViewIfNeeded(_ markdown: String) {
            guard isReady else { return }
            let sources = imageEmbedSources(in: markdown)
            guard sources != mediaEmbedsInWebView else { return }

            mediaEmbedsInWebView = sources
            callEditorFunction("setMediaEmbeds", argument: sources)
        }

        private func ensureMediaEmbedSource(for link: String) {
            guard isReady, let source = imageEmbedSource(for: link) else { return }
            guard mediaEmbedsInWebView[link] != source else { return }

            mediaEmbedsInWebView[link] = source
            callEditorFunction("setMediaEmbeds", argument: mediaEmbedsInWebView)
        }

        private func imageEmbedSources(in markdown: String) -> [String: String] {
            var sources: [String: String] = [:]

            for line in markdown.components(separatedBy: .newlines) {
                guard sources.count < Self.maxInlineImageEmbeds,
                      let media = EmbeddedMedia(markdownLine: line),
                      media.type == .image,
                      sources[media.link] == nil,
                      let source = imageEmbedSource(for: media.link) else {
                    continue
                }

                sources[media.link] = source
            }

            return sources
        }

        private func imageEmbedSource(for link: String) -> String? {
            if let url = URL(string: link),
               let scheme = url.scheme?.lowercased(),
               ["http", "https", "data"].contains(scheme) {
                return url.absoluteString
            }

            if let cachedDataURL = imageEmbedDataURLCache[link] {
                return cachedDataURL
            }

            guard let image = VaultStore.image(forMediaLink: link, maxPixelWidth: 1200),
                  let data = Self.pngData(from: image) else {
                return nil
            }

            let dataURL = "data:image/png;base64,\(data.base64EncodedString())"
            imageEmbedDataURLCache[link] = dataURL
            return dataURL
        }

        private func insertMediaEmbedInWebEditor(_ insertion: String, fallbackRelativePath: String) {
            guard isReady, let webView else {
                insertMedia(fallbackRelativePath)
                return
            }

            let argumentJSON = Self.javaScriptLiteral(for: insertion)
            webView.evaluateJavaScript("window.editor?.insertMediaEmbed(\(argumentJSON));") { [weak self] result, error in
                guard let self else { return }
                if let error {
                    AppLogger.app.error("Markdown editor media insert failed: \(AppLogger.errorSummary(error))")
                    self.insertMedia(fallbackRelativePath)
                    return
                }

                guard let markdown = result as? String else { return }
                self.pendingMarkdownInWebView = nil
                self.markdownInWebView = markdown
                if markdown != self.text {
                    self.text = markdown
                }
            }
        }

        private func focusEditor() {
            guard isReady, let webView else {
                pendingFocusAtEnd = true
                return
            }
            pendingFocusAtEnd = false
            isFocused = true
            webView.window?.endEditing(for: nil)
            webView.window?.makeFirstResponder(webView)
            webView.becomeFirstResponder()
            callEditorFunction("focus")
        }

        private func focusEditorAtEnd() {
            guard isReady, let webView else {
                pendingFocusAtEnd = true
                return
            }
            pendingFocusAtEnd = false
            isFocused = true
            webView.window?.endEditing(for: nil)
            webView.window?.makeFirstResponder(webView)
            webView.becomeFirstResponder()
            callEditorFunction("focusEnd")
        }

        private func callEditorFunction(_ name: String) {
            guard isReady, let webView else { return }
            webView.evaluateJavaScript("window.editor?.\(name)();") { _, error in
                if let error {
                    AppLogger.app.error("Markdown editor command \(name) failed: \(AppLogger.errorSummary(error))")
                }
            }
        }

        private func callEditorFunction(_ name: String, argument: Any, completion: ((Error?) -> Void)? = nil) {
            guard isReady, let webView else { return }
            let argumentJSON = Self.javaScriptLiteral(for: argument)
            webView.evaluateJavaScript("window.editor?.\(name)(\(argumentJSON));") { _, error in
                if let error {
                    AppLogger.app.error("Markdown editor command \(name) failed: \(AppLogger.errorSummary(error))")
                }
                completion?(error)
            }
        }

        private func webCommand(for command: MarkdownEditorCommand) -> [String: Any] {
            switch command {
            case let .wrap(wrapper):
                return ["type": "wrap", "wrapper": wrapper]
            case .insertLink:
                return ["type": "insertLink"]
            case let .insertPrefix(prefix):
                return ["type": "insertPrefix", "prefix": prefix]
            }
        }

        private static func javaScriptLiteral(for value: Any) -> String {
            guard let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.fragmentsAllowed]
            ),
                  let literal = String(data: data, encoding: .utf8) else {
                return "null"
            }
            return literal
        }

        private static func pngData(from image: NSImage) -> Data? {
            var proposedRect = NSRect(origin: .zero, size: image.size)
            guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
                return nil
            }

            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            bitmap.size = image.size
            return bitmap.representation(using: .png, properties: [:])
        }

        private static func systemTextReplacements() -> [String: String] {
            let items = UserDefaults.standard.array(forKey: "NSUserDictionaryReplacementItems") as? [[String: Any]] ?? []
            return items.reduce(into: [:]) { replacements, item in
                guard (item["on"] as? Bool) != false,
                      let shortcut = item["replace"] as? String,
                      !shortcut.isEmpty,
                      let replacement = item["with"] as? String else {
                    return
                }
                replacements[shortcut] = replacement
            }
        }
    }
}
