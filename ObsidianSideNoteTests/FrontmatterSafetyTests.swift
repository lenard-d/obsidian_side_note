import AppKit
import Foundation
import Testing
import WebKit
@testable import ObsidianSideNote

extension ObsidianSideNoteTests {
    @MainActor
    @Test func firstBodyInputPreservesPropertiesWithoutATrailingNewline() async throws {
        let (webView, _) = try await frontmatterTestEditor()
        let result = try await webView.evaluateJavaScript("""
        (() => {
          const source = '---\\ncreated: 2026-10-13\\n---';
          window.editor.setMarkdown(source);
          window.editorTest.setSelection(source.length);
          window.editorTest.replaceSelection('Body');
          return window.editorTest.getMarkdown() === source + '\\nBody'
            && window.editor.getProperties().entries[0].key === 'created';
        })();
        """) as? Bool
        #expect(result == true)
    }

    @MainActor
    @Test func hiddenPropertiesSurviveBackspaceAndBodyReplacement() async throws {
        let (webView, _) = try await frontmatterTestEditor()
        let result = try await webView.evaluateJavaScript("""
        (() => {
          const prefix = '---\\ncreated: 2026-10-13\\n---\\n';
          const preserved = ['', '\\n'].map((spacing) => {
            const source = prefix + spacing + 'Body';
            window.editor.setMarkdown(source);
            window.editorTest.setSelection(prefix.length);
            window.editorTest.dispatchKey('Backspace');
            return window.editorTest.getMarkdown() === source;
          });
          window.editorTest.selectAll();
          window.editorTest.replaceSelection('New body');
          const replaced = window.editorTest.getMarkdown() === prefix + 'New body';
          window.editor.togglePropertiesSource();
          window.editorTest.setSelectionRange(4, 11);
          window.editorTest.replaceSelection('updated');
          const editedSource = window.editorTest.getMarkdown().includes('updated: 2026-10-13');
          window.editor.togglePropertiesSource();
          window.editor.setMarkdown('A different note');
          return preserved.every(Boolean) && replaced && editedSource
            && window.editorTest.getMarkdown() === 'A different note';
        })();
        """) as? Bool
        #expect(result == true)
    }

    @MainActor
    @Test func cyclicPropertiesStillSendBodyEditsToSwift() async throws {
        let (webView, handler) = try await frontmatterTestEditor()
        let result = try await webView.evaluateJavaScript("""
        (() => {
          return ['a: &a\\n  b: *a', 'a: &a [*a]'].every((yaml) => {
            const source = '---\\n' + yaml + '\\n---\\nBody';
            window.editor.setMarkdown(source);
            const properties = window.editor.getProperties();
            window.editorTest.setSelection(source.length);
            window.editorTest.replaceSelection(' saved');
            return properties.entries[0].value.includes('[Circular reference]')
              && window.editorTest.getMarkdown() === source + ' saved';
          });
        })();
        """) as? Bool
        #expect(result == true)
        #expect(handler.errorMessage == nil)
        let deadline = Date().addingTimeInterval(2)
        while handler.receivedMessages.filter({ $0["type"] as? String == "change" }).count < 2,
              Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let changes = handler.receivedMessages.filter { $0["type"] as? String == "change" }
        #expect(changes.count == 2)
        #expect(changes.allSatisfy { ($0["text"] as? String)?.hasSuffix("Body saved") == true })
    }
}

@MainActor
private func frontmatterTestEditor() async throws -> (WKWebView, MarkdownEditorReadyMessageHandler) {
    let handler = MarkdownEditorReadyMessageHandler()
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.userContentController.add(handler, name: "editor")
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
    webView.loadHTMLString(try MarkdownEditorResource.bundledHTML(testing: true), baseURL: nil)
    let deadline = Date().addingTimeInterval(3)
    while !handler.isReady && handler.errorMessage == nil && Date() < deadline {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(handler.isReady)
    return (webView, handler)
}
