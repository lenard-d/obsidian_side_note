import AppKit
import OSLog
import SwiftUI
import WebKit

enum MarkdownEditorResource {
    enum ResourceError: Error {
        case missingIndexHTML
        case missingEditorJavaScript
        case unreadableResource(URL)
    }

    static func bundledHTML() throws -> String {
        let indexURL = try resourceURL(named: "index", extension: "html")
        let editorURL = try resourceURL(named: "editor", extension: "js")

        guard let indexHTML = try? String(contentsOf: indexURL, encoding: .utf8) else {
            throw ResourceError.unreadableResource(indexURL)
        }
        guard let editorJavaScript = try? String(contentsOf: editorURL, encoding: .utf8) else {
            throw ResourceError.unreadableResource(editorURL)
        }

        return inlineHTML(indexHTML: indexHTML, editorJavaScript: editorJavaScript)
    }

    static func inlineHTML(indexHTML: String, editorJavaScript: String) -> String {
        let escapedJavaScript = editorJavaScript.replacingOccurrences(of: "</script", with: "<\\/script")
        let inlineScript = "<script>\n\(escapedJavaScript)\n</script>"
        let externalScript = #"<script src="editor.js"></script>"#

        if indexHTML.contains(externalScript) {
            return indexHTML.replacingOccurrences(of: externalScript, with: inlineScript)
        }

        return indexHTML.replacingOccurrences(of: "</body>", with: "\(inlineScript)\n  </body>")
    }

    private static func resourceURL(named name: String, extension fileExtension: String) throws -> URL {
        if let nestedURL = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "MarkdownEditor"
        ) {
            return nestedURL
        }

        if let flatURL = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            return flatURL
        }

        throw fileExtension == "html" ? ResourceError.missingIndexHTML : ResourceError.missingEditorJavaScript
    }
}

struct RichMarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @Binding var focusRequestID: Int
    @Binding var cursorEndRequestID: Int
    @Binding var commandRequest: MarkdownEditorCommandRequest?
    let insertMedia: (String) -> Void
    let didInsertMedia: () -> Void

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

    func makeNSView(context: Context) -> MarkdownEditorWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "editor")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = MarkdownEditorWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.editorDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.registerForDraggedTypes(MediaAttachmentImporter.pasteboardTypes)

        context.coordinator.webView = webView
        context.coordinator.observeFocusRequests()
        context.coordinator.loadEditor()

        return webView
    }

    func updateNSView(_ webView: MarkdownEditorWebView, context: Context) {
        context.coordinator.webView = webView
        context.coordinator.syncMarkdownToWebViewIfNeeded(text)
        context.coordinator.syncAppearanceToWebViewIfNeeded()
        context.coordinator.applyFocusIfNeeded()
        context.coordinator.applyFocusRequestIfNeeded()
        context.coordinator.applyCursorEndRequestIfNeeded()
        context.coordinator.applyCommandRequestIfNeeded()
    }

    static func dismantleNSView(_ webView: MarkdownEditorWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        coordinator.stopObserving()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, MarkdownEditorWebViewDelegate {
        @Binding private var text: String
        @FocusState.Binding private var isFocused: Bool
        @Binding private var focusRequestID: Int
        @Binding private var cursorEndRequestID: Int
        @Binding private var commandRequest: MarkdownEditorCommandRequest?
        private let insertMedia: (String) -> Void
        private let didInsertMedia: () -> Void
        fileprivate weak var webView: MarkdownEditorWebView?
        private var loadedResourceURL: URL?
        private var isReady = false
        private var markdownInWebView = ""
        private var pendingMarkdownInWebView: String?
        private var pendingFocusAtEnd = false
        private var appliedAppearanceScheme: String?
        private var appliedFocusRequestID = 0
        private var appliedCursorEndRequestID = 0
        private var appliedCommandRequestID = 0
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
            stopObserving()
        }

        func loadEditor() {
            guard loadedResourceURL == nil, let webView else { return }
            do {
                let html = try MarkdownEditorResource.bundledHTML()
                loadedResourceURL = Bundle.main.bundleURL
                webView.loadHTMLString(html, baseURL: nil)
            } catch {
                AppLogger.app.error("Failed to load bundled markdown editor: \(error.localizedDescription, privacy: .public)")
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
                    AppLogger.app.error("Failed to sync markdown into web editor: \(error.localizedDescription, privacy: .public)")
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

        func applyCommandRequestIfNeeded() {
            guard isReady,
                  let commandRequest,
                  commandRequest.id != appliedCommandRequestID else {
                return
            }

            appliedCommandRequestID = commandRequest.id
            callEditorFunction("applyCommand", argument: webCommand(for: commandRequest.command))
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
                syncMarkdownToWebViewIfNeeded(text)
                syncAppearanceToWebViewIfNeeded()
                applyFocusIfNeeded()
                applyFocusRequestIfNeeded()
                applyCursorEndRequestIfNeeded()
                applyCommandRequestIfNeeded()
                if pendingFocusAtEnd {
                    focusEditorAtEnd()
                }
            case "change":
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
            case "error":
                let message = body["message"] as? String ?? "Unknown editor error"
                AppLogger.app.error("Markdown editor error: \(message, privacy: .public)")
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            isReady = false
            appliedAppearanceScheme = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            isReady = false
            AppLogger.app.error("Markdown editor navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            isReady = false
            AppLogger.app.error("Markdown editor provisional navigation failed: \(error.localizedDescription, privacy: .public)")
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
            MediaAttachmentImporter.importFromPasteboard(pasteboard) { [weak self] relativePath in
                DispatchQueue.main.async {
                    guard let self, let relativePath else { return }
                    self.insertMediaLink(relativePath)
                }
            }
        }

        private func insertMediaLink(_ relativePath: String) {
            let insertion = "![[\(relativePath)]]"
            if isReady {
                callEditorFunction("insertMarkdown", argument: insertion)
            } else {
                insertMedia(relativePath)
            }
            didInsertMedia()
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
                    AppLogger.app.error("Markdown editor command \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        private func callEditorFunction(_ name: String, argument: Any, completion: ((Error?) -> Void)? = nil) {
            guard isReady, let webView else { return }
            let argumentJSON = Self.javaScriptLiteral(for: argument)
            webView.evaluateJavaScript("window.editor?.\(name)(\(argumentJSON));") { _, error in
                if let error {
                    AppLogger.app.error("Markdown editor command \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
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
            guard JSONSerialization.isValidJSONObject(value) || value is String else {
                return "null"
            }

            let object: Any
            if let string = value as? String {
                object = [string]
            } else {
                object = value
            }

            guard let data = try? JSONSerialization.data(withJSONObject: object),
                  var literal = String(data: data, encoding: .utf8) else {
                return "null"
            }

            if value is String {
                literal.removeFirst()
                literal.removeLast()
            }
            return literal
        }
    }
}

protocol MarkdownEditorWebViewDelegate: AnyObject {
    func markdownEditorWebViewDidRequestPasteMedia(_ webView: MarkdownEditorWebView) -> Bool
    func markdownEditorWebView(_ webView: MarkdownEditorWebView, didReceiveDrop pasteboard: NSPasteboard) -> Bool
}

final class MarkdownEditorWebView: WKWebView {
    weak var editorDelegate: MarkdownEditorWebViewDelegate?

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if MediaAttachmentImporter.canImportFromPasteboard(sender.draggingPasteboard) {
            return .copy
        }

        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if editorDelegate?.markdownEditorWebView(self, didReceiveDrop: sender.draggingPasteboard) == true {
            return true
        }

        if MediaAttachmentImporter.canImportFromPasteboard(sender.draggingPasteboard) {
            return true
        }

        return super.performDragOperation(sender)
    }
}
