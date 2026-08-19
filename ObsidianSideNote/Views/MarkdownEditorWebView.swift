import AppKit
import WebKit

protocol MarkdownEditorWebViewDelegate: AnyObject {
    func markdownEditorWebViewDidRequestPasteMedia(_ webView: MarkdownEditorWebView) -> Bool
    func markdownEditorWebView(_ webView: MarkdownEditorWebView, didReceiveDrop pasteboard: NSPasteboard) -> Bool
}

final class MarkdownEditorWebView: WKWebView {
    weak var editorDelegate: MarkdownEditorWebViewDelegate?

    override var mouseDownCanMoveWindow: Bool {
        false
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
