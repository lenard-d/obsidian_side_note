import Testing
import Foundation
import AppKit
import SwiftUI
import Defaults
import KeyboardShortcuts
import WebKit
@testable import ObsidianSideNote

extension ObsidianSideNoteTests {
    @Test func markdownEditorResourceInlinesJavaScriptForSandboxedWKWebView() {
        let html = MarkdownEditorResource.inlineHTML(
            indexHTML: """
            <html>
              <body>
                <main id="editor"></main>
                <script src="editor.js"></script>
              </body>
            </html>
            """,
            editorJavaScript: "window.editor = {}; console.log('</script>');"
        )

        #expect(!html.contains(#"<script src="editor.js"></script>"#))
        #expect(html.contains("window.editor = {};"))
        #expect(html.contains("<\\/script>"))
    }

    @MainActor
    @Test func markdownFormattingCommandsToggleWithoutNesting() async throws {
        let html = try MarkdownEditorResource.bundledHTML(testing: true)
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let resultJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              const wrappers = ["**", "*", "==", "`"];
              const results = [];
              for (const wrapper of wrappers) {
                window.editor.setMarkdown("plain");
                window.editorTest.setSelectionRange(0, 5);
                const wrapped = window.editor.applyCommand({type: "wrap", wrapper});

                window.editorTest.setSelectionRange(0, wrapped.length);
                const unwrappedIncludingMarkers = window.editor.applyCommand({type: "wrap", wrapper});

                window.editor.setMarkdown(`${wrapper}plain${wrapper}`);
                window.editorTest.setSelectionRange(wrapper.length, wrapper.length + 5);
                const unwrappedAroundSelection = window.editor.applyCommand({type: "wrap", wrapper});

                window.editor.setMarkdown("plain");
                window.editorTest.setSelection(2);
                const emptySelection = window.editor.applyCommand({type: "wrap", wrapper});
                const emptySelectionRange = window.editorTest.getSelection();
                const toggledEmptySelection = window.editor.applyCommand({type: "wrap", wrapper});
                const toggledEmptySelectionRange = window.editorTest.getSelection();

                results.push({
                  wrapper,
                  wrapped,
                  unwrappedIncludingMarkers,
                  unwrappedAroundSelection,
                  emptySelection,
                  emptySelectionRange,
                  toggledEmptySelection,
                  toggledEmptySelectionRange
                });
              }
              return JSON.stringify(results);
            })();
            """
        ) as? String)
        let data = try #require(resultJSON.data(using: .utf8))
        let results = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        #expect(results.count == 4)
        for result in results {
            let wrapper = try #require(result["wrapper"] as? String)
            #expect(result["wrapped"] as? String == "\(wrapper)plain\(wrapper)")
            #expect(result["unwrappedIncludingMarkers"] as? String == "plain")
            #expect(result["unwrappedAroundSelection"] as? String == "plain")
            #expect(result["emptySelection"] as? String == "pl\(wrapper)\(wrapper)ain")
            let selection = try #require(result["emptySelectionRange"] as? [String: Int])
            #expect(selection["anchor"] == 2 + wrapper.utf16.count)
            #expect(selection["head"] == 2 + wrapper.utf16.count)
            #expect(result["toggledEmptySelection"] as? String == "plain")
            let toggledSelection = try #require(result["toggledEmptySelectionRange"] as? [String: Int])
            #expect(toggledSelection["anchor"] == 2)
            #expect(toggledSelection["head"] == 2)
        }
    }

    @MainActor
    @Test func markdownEditorReadOnlyModeKeepsLivePreviewButRejectsEditingCommands() async throws {
        let html = try MarkdownEditorResource.bundledHTML(testing: true)
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let resultJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              const source = "# Preview\\n\\n**Bold** and [Target](Target.md)";
              window.editor.setMarkdown(source);
              window.editor.setReadOnly(true);
              window.editorTest.setSelection(source.indexOf("[Target]") + 2);
              const selectionBeforeFocusEnd = window.editorTest.getSelection();
              window.editor.focusEnd();
              const visibleText = window.editorTest.visibleText();
              const afterCommand = window.editor.applyCommand({type: "insertText", text: "changed"});
              return JSON.stringify({
                contentEditable: document.querySelector(".cm-content")?.getAttribute("contenteditable"),
                visibleText,
                linkCount: document.querySelectorAll(".osn-markdown-link").length,
                selectionBeforeFocusEnd,
                selectionAfterFocusEnd: window.editorTest.getSelection(),
                afterCommand
              });
            })();
            """
        ) as? String)
        let data = try #require(resultJSON.data(using: .utf8))
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(result["contentEditable"] as? String == "false")
        #expect((result["visibleText"] as? String)?.contains("Bold and Target") == true)
        #expect(result["linkCount"] as? Int == 1)
        let selectionBeforeFocusEnd = try #require(result["selectionBeforeFocusEnd"] as? [String: Any])
        let selectionAfterFocusEnd = try #require(result["selectionAfterFocusEnd"] as? [String: Any])
        #expect(selectionAfterFocusEnd["anchor"] as? Int == selectionBeforeFocusEnd["anchor"] as? Int)
        #expect(selectionAfterFocusEnd["head"] as? Int == selectionBeforeFocusEnd["head"] as? Int)
        #expect(result["afterCommand"] as? String == "# Preview\n\n**Bold** and [Target](Target.md)")
    }

    @MainActor
    @Test func markdownEditorBundledHTMLInitializesInWKWebViewAndRoundTripsMarkdown() async throws {
        let html = try MarkdownEditorResource.bundledHTML(testing: true)
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let markdown = "# Inbox\n\n- [ ] visible content"
        try await webView.evaluateJavaScript("window.editor.setMarkdown(\(javaScriptStringLiteral(markdown)));")
        let result = try await webView.evaluateJavaScript("window.editorTest.getMarkdown();") as? String

        #expect(result == markdown)

        let blankAreaClickMovedCursorToDocumentEnd = try await webView.evaluateJavaScript(
            """
            (() => {
              window.editorTest.setSelection(0);
              const handled = window.editorTest.simulateBlankAreaMouseDown();
              const after = window.editorTest.getSelection();
              return handled === true &&
                after.head === after.docLength &&
                after.anchor === after.docLength;
            })();
            """
        ) as? Bool

        #expect(blankAreaClickMovedCursorToDocumentEnd == true)

        let editorPresentationJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              const source = "# One\\n## Two\\n### Heading\\n\\n- [ ] Task\\n- [x] Done\\n- Plain\\n\\nBefore **Bold** after";
              window.editor.setMarkdown(source);
              window.editorTest.setSelection(source.length);
              const inactiveText = window.editorTest.visibleText();
              const boldTextElement = [...document.querySelectorAll(".cm-content span")]
                .find((element) => element.textContent === "Bold");
              const inactiveBoldFontWeight = boldTextElement
                ? getComputedStyle(boldTextElement).fontWeight
                : null;
              window.editorTest.setSelection(source.indexOf("Bold") + 1);
              const activeBoldText = window.editorTest.visibleText();
              window.editorTest.setSelection(source.length);
              const checkboxCount = window.editorTest.taskCheckboxCount();
              const bulletCount = window.editorTest.bulletMarkerCount();
              const colors = window.editorTest.textColors();
              const styles = window.editorTest.presentationStyles();
              const checkboxToken = source.indexOf("[ ]");
              window.editorTest.setSelection(checkboxToken);
              const activeCheckboxText = window.editorTest.visibleText();
              window.editorTest.setSelection(source.indexOf("Task"));
              const checkboxSpacerText = window.editorTest.visibleText();
              const checkboxSpacerCount = window.editorTest.taskCheckboxCount();
              const bulletToken = source.indexOf("- Plain");
              window.editorTest.setSelection(bulletToken + 1);
              const activeBulletText = window.editorTest.visibleText();
              window.editorTest.setSelection(bulletToken + 2);
              const bulletSpacerText = window.editorTest.visibleText();
              const bulletSpacerCount = window.editorTest.bulletMarkerCount();
              window.editorTest.setSelection(source.indexOf("###") + 4);
              const activeHeadingText = window.editorTest.visibleText();
              window.editorTest.selectAll();
              const selectAllText = window.editorTest.visibleText();
              window.editorTest.setSelection(source.length);
              const checkboxAlignment = window.editorTest.taskCheckboxAlignment();
              const checkboxToggle = window.editorTest.firstTaskCheckboxMetrics();
              window.editor.setMarkdown("Paragraph\\n- ");
              window.editorTest.setSelection("Paragraph\\n- ".length);
              const transientHeadingLayout = window.editorTest.lineLayout();
              window.editor.setMarkdown("abbr");
              window.editorTest.setSelection(4);
              window.editorTest.setTextReplacements({abbr: "expanded text"});
              const replacementHandled = window.editorTest.applyTextInput(" ");
              const replacementMarkdown = window.editorTest.getMarkdown();
              window.editor.setMarkdown("hello");
              window.editorTest.setSelection(5);
              const toolbarMarkdown = window.editor.applyCommand({type: "wrap", wrapper: "**"});
              return JSON.stringify({
                inactiveText,
                inactiveBoldFontWeight,
                activeBoldText,
                activeCheckboxText,
                checkboxSpacerText,
                checkboxSpacerCount,
                activeBulletText,
                bulletSpacerText,
                bulletSpacerCount,
                activeHeadingText,
                selectAllText,
                checkboxCount,
                bulletCount,
                colors,
                styles,
                checkboxAlignment,
                checkboxToggle,
                transientHeadingLayout,
                replacementHandled,
                replacementMarkdown,
                toolbarMarkdown
              });
            })();
            """
        ) as? String)
        let editorPresentationData = try #require(editorPresentationJSON.data(using: .utf8))
        let editorPresentation = try #require(
            JSONSerialization.jsonObject(with: editorPresentationData) as? [String: Any]
        )
        let inactiveText = try #require(editorPresentation["inactiveText"] as? String)
        let inactiveBoldFontWeight = try #require(editorPresentation["inactiveBoldFontWeight"] as? String)
        let activeBoldText = try #require(editorPresentation["activeBoldText"] as? String)
        let activeCheckboxText = try #require(editorPresentation["activeCheckboxText"] as? String)
        let checkboxSpacerText = try #require(editorPresentation["checkboxSpacerText"] as? String)
        let checkboxSpacerCount = try #require(editorPresentation["checkboxSpacerCount"] as? Int)
        let activeBulletText = try #require(editorPresentation["activeBulletText"] as? String)
        let bulletSpacerText = try #require(editorPresentation["bulletSpacerText"] as? String)
        let bulletSpacerCount = try #require(editorPresentation["bulletSpacerCount"] as? Int)
        let activeHeadingText = try #require(editorPresentation["activeHeadingText"] as? String)
        let selectAllText = try #require(editorPresentation["selectAllText"] as? String)
        let checkboxCount = try #require(editorPresentation["checkboxCount"] as? Int)
        let bulletCount = try #require(editorPresentation["bulletCount"] as? Int)
        let colors = try #require(editorPresentation["colors"] as? [String])
        let styles = try #require(editorPresentation["styles"] as? [String: Any])
        let checkboxStyles = try #require(styles["checkbox"] as? [String: String])
        let bulletStyles = try #require(styles["bullet"] as? [String: Any])
        let headingLines = try #require(styles["headingLines"] as? [[String: Any]])
        let checkboxAlignment = try #require(editorPresentation["checkboxAlignment"] as? [[String: Any]])
        let checkboxToggle = try #require(editorPresentation["checkboxToggle"] as? [String: Any])
        let toggleBefore = try #require(checkboxToggle["before"] as? [String: Int])
        let toggleAfter = try #require(checkboxToggle["after"] as? [String: Int])
        let toggledMarkdown = try #require(checkboxToggle["markdown"] as? String)
        let transientHeadingLayout = try #require(editorPresentation["transientHeadingLayout"] as? [[String: Any]])
        let scrollerLineHeight = try #require(styles["scrollerLineHeight"] as? String)
        let headingFontSizes = headingLines.compactMap { line -> Double? in
            guard let fontSize = line["fontSize"] as? String else { return nil }
            return Double(fontSize.replacingOccurrences(of: "px", with: ""))
        }
        let headingFontWeights = headingLines.compactMap { line -> Double? in
            guard let fontWeight = line["fontWeight"] as? String else { return nil }
            return Double(fontWeight)
        }

        #expect(inactiveText.contains("Heading"))
        #expect(inactiveText.contains("Before Bold after"))
        #expect(!inactiveText.contains("**Bold**"))
        #expect(Double(inactiveBoldFontWeight) ?? 0 >= 700)
        #expect(activeBoldText.contains("Before **Bold** after"))
        #expect(!inactiveText.contains("###"))
        #expect(!inactiveText.contains("- [ ]"))
        #expect(!inactiveText.contains("- Plain"))
        #expect(activeCheckboxText.contains("[ ] Task"))
        #expect(!checkboxSpacerText.contains("[ ]"))
        #expect(checkboxSpacerCount == 2)
        #expect(activeBulletText.contains("- Plain"))
        #expect(!bulletSpacerText.contains("- Plain"))
        #expect(bulletSpacerCount == 1)
        #expect(activeHeadingText.contains("### Heading"))
        #expect(selectAllText.contains("### Heading"))
        #expect(selectAllText.contains("- Plain"))
        #expect(checkboxCount == 2)
        #expect(bulletCount == 1)
        #expect(colors.allSatisfy { $0 == "rgb(255, 255, 255)" })
        #expect(checkboxStyles["borderColor"] == "rgb(255, 255, 255)")
        #expect(checkboxStyles["display"] == "inline-flex")
        #expect(checkboxStyles["alignItems"] == "center")
        #expect(checkboxStyles["justifyContent"] == "center")
        #expect(bulletStyles["dotCount"] as? Int == 1)
        #expect(bulletStyles["color"] as? String == "rgb(255, 255, 255)")
        #expect(bulletStyles["display"] as? String == "inline-block")
        #expect(bulletStyles["usesCapHeight"] as? Bool == true)
        let bulletHeight = Double((bulletStyles["height"] as? String ?? "").replacingOccurrences(of: "px", with: "")) ?? 0
        #expect(bulletHeight > 0 && bulletHeight < 15)
        #expect(bulletStyles["verticalAlign"] as? String == "baseline")
        #expect(Double(scrollerLineHeight.replacingOccurrences(of: "px", with: "")) ?? 0 > 24)
        #expect(headingFontSizes.count == 3)
        #expect(headingFontSizes[0] > headingFontSizes[1])
        #expect(headingFontSizes[1] > headingFontSizes[2])
        #expect(headingFontSizes[2] > 18)
        #expect(headingFontWeights.count == 3)
        #expect(headingFontWeights[0] > headingFontWeights[1])
        #expect(headingFontWeights[1] > headingFontWeights[2])
        #expect(headingFontWeights[2] >= 700)
        let uncheckedCheckbox = try #require(checkboxAlignment.first { ($0["checked"] as? Bool) == false })
        let checkedCheckbox = try #require(checkboxAlignment.first { ($0["checked"] as? Bool) == true })
        let uncheckedWidth = try #require(uncheckedCheckbox["width"] as? Double)
        let checkedWidth = try #require(checkedCheckbox["width"] as? Double)
        let uncheckedHeight = try #require(uncheckedCheckbox["height"] as? Double)
        let checkedHeight = try #require(checkedCheckbox["height"] as? Double)
        let uncheckedCenterDelta = try #require(uncheckedCheckbox["centerDelta"] as? Double)
        let checkedCenterDelta = try #require(checkedCheckbox["centerDelta"] as? Double)
        let uncheckedTopWithinLine = try #require(uncheckedCheckbox["topWithinLine"] as? Double)
        let checkedTopWithinLine = try #require(checkedCheckbox["topWithinLine"] as? Double)
        #expect(abs(uncheckedWidth - checkedWidth) < 0.5)
        #expect(abs(uncheckedHeight - checkedHeight) < 0.5)
        #expect(abs(uncheckedCenterDelta - checkedCenterDelta) < 0.5)
        #expect(abs(uncheckedTopWithinLine - checkedTopWithinLine) < 0.5)
        #expect(toggleBefore == toggleAfter)
        #expect(
            toggledMarkdown == "# One\n## Two\n### Heading\n\n- [x] Task\n- [x] Done\n- Plain\n\nBefore **Bold** after"
        )
        #expect(transientHeadingLayout.first?["fontWeight"] as? String == "400")
        #expect(transientHeadingLayout.last?["isList"] as? Bool == true)
        let transientListPadding = Double(
            (transientHeadingLayout.last?["paddingLeft"] as? String ?? "")
                .replacingOccurrences(of: "px", with: "")
        ) ?? 0
        let transientListIndent = Double(
            (transientHeadingLayout.last?["textIndent"] as? String ?? "")
                .replacingOccurrences(of: "px", with: "")
        ) ?? 0
        #expect(transientListPadding > 20)
        #expect(transientListIndent < 0)
        #expect(editorPresentation["replacementHandled"] as? Bool == true)
        #expect(editorPresentation["replacementMarkdown"] as? String == "expanded text ")
        #expect(editorPresentation["toolbarMarkdown"] as? String == "hello****")
    }

    @MainActor
    @Test func markdownListMarkersKeepSharedGeometryAcrossRawAndPreview() async throws {
        let html = try MarkdownEditorResource.bundledHTML(testing: true)
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let resultJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              const source = "Paragraph\\n- Stable content\\n1. Ordered\\n- [ ] Task";
              const textStartX = (needle) => {
                const walker = document.createTreeWalker(
                  document.querySelector(".cm-content"),
                  NodeFilter.SHOW_TEXT
                );
                while (walker.nextNode()) {
                  const index = walker.currentNode.textContent.indexOf(needle);
                  if (index < 0) continue;
                  const range = document.createRange();
                  range.setStart(walker.currentNode, index);
                  range.setEnd(walker.currentNode, index + 1);
                  return range.getBoundingClientRect().left;
                }
                return null;
              };

              const textRect = (needle) => {
                const walker = document.createTreeWalker(
                  document.querySelector(".cm-content"),
                  NodeFilter.SHOW_TEXT
                );
                while (walker.nextNode()) {
                  const index = walker.currentNode.textContent.indexOf(needle);
                  if (index < 0) continue;
                  const range = document.createRange();
                  range.setStart(walker.currentNode, index);
                  range.setEnd(walker.currentNode, index + needle.length);
                  const rect = range.getBoundingClientRect();
                  return {left: rect.left, top: rect.top, width: rect.width, height: rect.height};
                }
                return null;
              };

              const markerState = (position) => {
                window.editorTest.setSelection(position);
                const previewMarker = document.querySelector(".list-bullet-marker");
                const rawMarker = document.querySelector(".list-bullet-source");
                const marker = previewMarker || rawMarker;
                const markerRect = marker?.getBoundingClientRect();
                const dotRect = previewMarker
                  ?.querySelector(".list-bullet-dot")
                  ?.getBoundingClientRect();
                let rawGlyphRect = null;
                if (rawMarker?.firstChild) {
                  const range = document.createRange();
                  range.selectNodeContents(rawMarker.firstChild);
                  rawGlyphRect = range.getBoundingClientRect();
                }
                return {
                  preview: Boolean(previewMarker),
                  raw: Boolean(rawMarker),
                  markerX: markerRect?.left ?? null,
                  markerWidth: markerRect?.width ?? null,
                  markerHeight: markerRect?.height ?? null,
                  visualCenterX: dotRect
                    ? dotRect.left + dotRect.width / 2
                    : rawGlyphRect
                      ? rawGlyphRect.left + rawGlyphRect.width / 2
                      : null,
                  contentX: textStartX("Stable")
                };
              };

              const taskState = (position) => {
                window.editorTest.setSelection(position);
                const widget = document.querySelector(".task-checkbox");
                const rawSource = document.querySelector(".list-task-source");
                const marker = widget || rawSource;
                const line = marker?.closest(".cm-line");
                const lineRect = line?.getBoundingClientRect();
                const markerRect = marker?.getBoundingClientRect();
                const taskRect = textRect("Task");
                let glyphRect = null;
                if (rawSource?.firstChild) {
                  const range = document.createRange();
                  range.selectNodeContents(rawSource.firstChild);
                  const rect = range.getBoundingClientRect();
                  glyphRect = {left: rect.left, top: rect.top, width: rect.width, height: rect.height};
                }
                const rawStyle = rawSource ? getComputedStyle(rawSource) : null;
                const lineStyle = line ? getComputedStyle(line) : null;
                const baselineY = (element) => {
                  if (!element) return null;
                  const probe = document.createElement("span");
                  probe.style.cssText = [
                    "display:inline-block",
                    "width:0",
                    "height:0",
                    "margin:0",
                    "padding:0",
                    "border:0",
                    "vertical-align:baseline"
                  ].join(";");
                  element.appendChild(probe);
                  const baseline = probe.getBoundingClientRect().top;
                  probe.remove();
                  return baseline;
                };
                const lineBaseline = baselineY(line);
                const rawBaseline = baselineY(rawSource);
                return {
                  preview: Boolean(widget),
                  raw: Boolean(rawSource),
                  markerX: markerRect?.left ?? null,
                  markerWidth: markerRect?.width ?? null,
                  markerTopWithinLine: markerRect && lineRect ? markerRect.top - lineRect.top : null,
                  lineHeight: lineRect?.height ?? null,
                  contentX: taskRect?.left ?? null,
                  textTopWithinLine: taskRect && lineRect ? taskRect.top - lineRect.top : null,
                  textHeight: taskRect?.height ?? null,
                  glyphTopWithinLine: glyphRect && lineRect ? glyphRect.top - lineRect.top : null,
                  glyphHeight: glyphRect?.height ?? null,
                  rawLineHeight: rawStyle?.lineHeight ?? null,
                  lineStyleHeight: lineStyle?.lineHeight ?? null,
                  verticalAlign: rawStyle?.verticalAlign ?? null,
                  fontFamily: rawStyle?.fontFamily ?? null,
                  fontSize: rawStyle?.fontSize ?? null,
                  baselineDelta: rawBaseline != null && lineBaseline != null
                    ? rawBaseline - lineBaseline
                    : null
                };
              };

              window.editor.setMarkdown(source);
              window.editorTest.setSelection(source.length);
              const bulletStart = source.indexOf("- Stable");
              const preview = markerState(source.length);
              const marker = document.querySelector(".list-bullet-marker");
              const dot = marker?.querySelector(".list-bullet-dot");
              const markerRect = marker?.getBoundingClientRect();
              const dotRect = dot?.getBoundingClientRect();
              const capProbe = document.createElement("span");
              capProbe.style.cssText = "display:inline-block;width:0;height:1cap;vertical-align:baseline";
              marker?.after(capProbe);
              const capRect = capProbe.getBoundingClientRect();
              capProbe.remove();

              const rawLeft = markerState(bulletStart);
              const rawRight = markerState(bulletStart + 1);
              const afterSpace = markerState(bulletStart + 2);
              const taskToken = source.indexOf("[ ]");
              const taskPreview = taskState(source.length);
              const taskRaw = taskState(taskToken + 1);
              window.editorTest.setSelection(source.length);

              const paragraphX = textStartX("Paragraph");
              const orderedX = textStartX("1. Ordered");
              const checkboxRect = document
                .querySelector(".task-checkbox")
                ?.getBoundingClientRect();
              const lineHeights = [...document.querySelectorAll(".cm-line")]
                .map((line) => line.getBoundingClientRect().height);
              const fontProbe = document.createElement("span");
              fontProbe.textContent = " ";
              fontProbe.style.cssText = [
                "position:fixed",
                "visibility:hidden",
                "white-space:pre",
                `font:${getComputedStyle(document.querySelector(".cm-line")).font}`
              ].join(";");
              document.body.appendChild(fontProbe);
              const spaceWidth = fontProbe.getBoundingClientRect().width;
              fontProbe.remove();

              return JSON.stringify({
                markdown: window.editorTest.getMarkdown(),
                preview,
                rawLeft,
                rawRight,
                afterSpace,
                taskPreview,
                taskRaw,
                paragraphX,
                orderedX,
                checkboxX: checkboxRect?.left ?? null,
                lineHeights,
                spaceWidth,
                bulletCenterDelta: markerRect && dotRect
                  ? (dotRect.top + dotRect.height / 2) - (markerRect.top + markerRect.height / 2)
                  : null,
                bulletCapCenterDelta: dotRect
                  ? (dotRect.top + dotRect.height / 2) - (capRect.top + capRect.height / 2)
                  : null
              });
            })();
            """
        ) as? String)
        let data = try #require(resultJSON.data(using: .utf8))
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let preview = try #require(result["preview"] as? [String: Any])
        let rawLeft = try #require(result["rawLeft"] as? [String: Any])
        let rawRight = try #require(result["rawRight"] as? [String: Any])
        let afterSpace = try #require(result["afterSpace"] as? [String: Any])
        let taskPreview = try #require(result["taskPreview"] as? [String: Any])
        let taskRaw = try #require(result["taskRaw"] as? [String: Any])
        let paragraphX = try #require(result["paragraphX"] as? Double)
        let orderedX = try #require(result["orderedX"] as? Double)
        let checkboxX = try #require(result["checkboxX"] as? Double)
        let spaceWidth = try #require(result["spaceWidth"] as? Double)
        let lineHeights = try #require(result["lineHeights"] as? [Double])
        let bulletCenterDelta = try #require(result["bulletCenterDelta"] as? Double)
        let bulletCapCenterDelta = try #require(result["bulletCapCenterDelta"] as? Double)

        #expect(result["markdown"] as? String == "Paragraph\n- Stable content\n1. Ordered\n- [ ] Task")
        #expect(preview["preview"] as? Bool == true)
        #expect(preview["raw"] as? Bool == false)
        #expect(rawLeft["preview"] as? Bool == false)
        #expect(rawLeft["raw"] as? Bool == true)
        #expect(rawRight["preview"] as? Bool == false)
        #expect(rawRight["raw"] as? Bool == true)
        #expect(afterSpace["preview"] as? Bool == true)
        #expect(afterSpace["raw"] as? Bool == false)
        #expect(taskPreview["preview"] as? Bool == true)
        #expect(taskPreview["raw"] as? Bool == false)
        #expect(taskRaw["preview"] as? Bool == false)
        #expect(taskRaw["raw"] as? Bool == true)

        let previewContentX = try #require(preview["contentX"] as? Double)
        let previewMarkerX = try #require(preview["markerX"] as? Double)
        let previewMarkerWidth = try #require(preview["markerWidth"] as? Double)
        let previewMarkerHeight = try #require(preview["markerHeight"] as? Double)
        let previewVisualCenterX = try #require(preview["visualCenterX"] as? Double)
        for state in [rawLeft, rawRight, afterSpace] {
            let contentX = try #require(state["contentX"] as? Double)
            let markerX = try #require(state["markerX"] as? Double)
            let markerWidth = try #require(state["markerWidth"] as? Double)
            let markerHeight = try #require(state["markerHeight"] as? Double)
            #expect(abs(contentX - previewContentX) < 0.5, "Bullet content shifted by \(contentX - previewContentX) px")
            #expect(abs(markerX - previewMarkerX) < 0.5)
            #expect(abs(markerWidth - previewMarkerWidth) < 0.5)
            #expect(abs(markerHeight - previewMarkerHeight) < 0.5)
        }

        let rawLeftVisualCenterX = try #require(rawLeft["visualCenterX"] as? Double)
        let rawRightVisualCenterX = try #require(rawRight["visualCenterX"] as? Double)
        #expect(abs(rawLeftVisualCenterX - previewVisualCenterX) < 0.5)
        #expect(abs(rawRightVisualCenterX - previewVisualCenterX) < 0.5)
        #expect(abs((previewMarkerX - paragraphX) - spaceWidth) < 0.5)
        #expect(abs(orderedX - previewMarkerX) < 0.5)
        #expect(abs(checkboxX - previewMarkerX) < 0.5)
        #expect(lineHeights.allSatisfy { abs($0 - lineHeights[0]) < 0.5 })
        let taskPreviewContentX = try #require(taskPreview["contentX"] as? Double)
        let taskRawContentX = try #require(taskRaw["contentX"] as? Double)
        let taskPreviewLineHeight = try #require(taskPreview["lineHeight"] as? Double)
        let taskRawLineHeight = try #require(taskRaw["lineHeight"] as? Double)
        let taskTextTop = try #require(taskRaw["textTopWithinLine"] as? Double)
        let taskRawGlyphTop = try #require(taskRaw["glyphTopWithinLine"] as? Double)
        let taskTextHeight = try #require(taskRaw["textHeight"] as? Double)
        let taskRawGlyphHeight = try #require(taskRaw["glyphHeight"] as? Double)
        let taskRawBaselineDelta = try #require(taskRaw["baselineDelta"] as? Double)
        #expect(abs(taskRawContentX - taskPreviewContentX) < 0.5)
        #expect(abs(taskRawLineHeight - taskPreviewLineHeight) < 0.5)
        #expect(
            abs(taskRawGlyphTop - taskTextTop) < 0.5,
            "Raw checkbox brackets shifted vertically by \(taskRawGlyphTop - taskTextTop) px"
        )
        #expect(abs(taskRawGlyphHeight - taskTextHeight) < 0.5)
        #expect(
            abs(taskRawBaselineDelta) < 0.5,
            "Raw checkbox brackets use a baseline shifted by \(taskRawBaselineDelta) px"
        )
        #expect(abs(bulletCenterDelta) < 0.5)
        #expect(
            abs(bulletCapCenterDelta) < 0.5,
            "Bullet center missed the baseline-to-cap-height center by \(bulletCapCenterDelta) px"
        )
    }

    @MainActor
    @Test func markdownLivePreviewRevealsOnlyTheFormattingAtTheCursor() async throws {
        let html = try MarkdownEditorResource.bundledHTML(testing: true)
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let resultJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              const source = "Start **bold** middle *italic* then ==mark== and `code` end";
              window.editor.setMarkdown(source);
              const visibleAt = (needle, offset = 1) => {
                window.editorTest.setSelection(source.indexOf(needle) + offset);
                return window.editorTest.visibleText();
              };

              const away = visibleAt("middle", 2);
              const bold = visibleAt("bold");
              const italic = visibleAt("italic");
              const highlight = visibleAt("mark");
              const code = visibleAt("code");

              const terminalSource = "First **bold**\\nNext";
              const firstLineEnd = terminalSource.indexOf("\\n");
              const boldPosition = terminalSource.indexOf("bold") + 2;
              const lineEndNavigation = (key, modifiers) => {
                window.editor.setMarkdown(terminalSource);
                window.editorTest.setSelection(boldPosition);
                const handled = window.editorTest.dispatchKey(key, modifiers);
                return {
                  handled,
                  selection: window.editorTest.getSelection(),
                  visibleText: window.editorTest.visibleText()
                };
              };
              const commandRight = lineEndNavigation("ArrowRight", {metaKey: true});
              const endKey = lineEndNavigation("End");
              const controlE = lineEndNavigation("e", {ctrlKey: true});
              const shiftCommandRight = lineEndNavigation("ArrowRight", {
                metaKey: true,
                shiftKey: true
              });
              const terminalSyntaxCases = [
                {name: "bold", source: "Only **bold**", content: "bold", closingLength: 2},
                {name: "italic", source: "Only _italic_", content: "italic", closingLength: 1},
                {name: "highlight", source: "Only ==highlight==", content: "highlight", closingLength: 2},
                {name: "monospace", source: "Only `monospace`", content: "monospace", closingLength: 1},
                {name: "markdownLink", source: "Only [Link](target.md)", content: "Link", closingLength: 1},
                {name: "wikiLink", source: "Only [[Link]]", content: "Link", closingLength: 2}
              ];
              const terminalSyntaxEndStates = terminalSyntaxCases.map((testCase) => {
                window.editor.setMarkdown(testCase.source);
                window.editorTest.setSelection(
                  testCase.source.indexOf(testCase.content) + 1
                );
                const keyHandled = window.editorTest.dispatchKey("ArrowRight", {metaKey: true});
                const keySelection = window.editorTest.getSelection();
                const visibleAfterKey = window.editorTest.visibleText();

                window.editorTest.setSelection(testCase.source.length - testCase.closingLength);
                const arrowHandled = window.editorTest.dispatchKey("ArrowRight");
                const arrowSelection = window.editorTest.getSelection();
                const visibleAfterArrow = window.editorTest.visibleText();

                window.editorTest.setSelection(
                  testCase.source.indexOf(testCase.content) + 1
                );
                window.editor.focusEnd();
                return {
                  name: testCase.name,
                  source: testCase.source,
                  end: testCase.source.length,
                  keyHandled,
                  keySelection,
                  visibleAfterKey,
                  arrowHandled,
                  arrowSelection,
                  visibleAfterArrow,
                  focusSelection: window.editorTest.getSelection(),
                  visibleAfterFocus: window.editorTest.visibleText()
                };
              });

              window.editor.setMarkdown(source);
              const styleFor = (className) => {
                const element = document.querySelector(`.${className}`);
                if (!element) return null;
                const style = getComputedStyle(element);
                return {
                  fontWeight: style.fontWeight,
                  fontStyle: style.fontStyle,
                  fontFamily: style.fontFamily,
                  backgroundColor: style.backgroundColor
                };
              };

              window.editorTest.setSelection(source.indexOf("middle") + 2);
              return JSON.stringify({
                away,
                bold,
                italic,
                highlight,
                code,
                strongStyle: styleFor("osn-inline-strong"),
                emphasisStyle: styleFor("osn-inline-emphasis"),
                highlightStyle: styleFor("osn-inline-highlight"),
                codeStyle: styleFor("osn-inline-code"),
                firstLineEnd,
                boldPosition,
                commandRight,
                endKey,
                controlE,
                shiftCommandRight,
                terminalSyntaxEndStates
              });
            })();
            """
        ) as? String)
        let data = try #require(resultJSON.data(using: .utf8))
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let away = try #require(result["away"] as? String)
        let bold = try #require(result["bold"] as? String)
        let italic = try #require(result["italic"] as? String)
        let highlight = try #require(result["highlight"] as? String)
        let code = try #require(result["code"] as? String)
        let strongStyle = try #require(result["strongStyle"] as? [String: String])
        let emphasisStyle = try #require(result["emphasisStyle"] as? [String: String])
        let highlightStyle = try #require(result["highlightStyle"] as? [String: String])
        let codeStyle = try #require(result["codeStyle"] as? [String: String])
        let firstLineEnd = try #require(result["firstLineEnd"] as? Int)
        let boldPosition = try #require(result["boldPosition"] as? Int)

        #expect(away.contains("Start bold middle italic then mark and code end"))
        #expect(!away.contains("**"))
        #expect(!away.contains("=="))
        #expect(!away.contains("`"))
        #expect(bold.contains("**bold**"))
        #expect(!bold.contains("*italic*"))
        #expect(italic.contains("*italic*"))
        #expect(!italic.contains("**bold**"))
        #expect(highlight.contains("==mark=="))
        #expect(!highlight.contains("**bold**"))
        #expect(code.contains("`code`"))
        #expect(!code.contains("==mark=="))
        #expect(Double(strongStyle["fontWeight"] ?? "") ?? 0 >= 700)
        #expect(emphasisStyle["fontStyle"] == "italic")
        #expect(highlightStyle["backgroundColor"] != "rgba(0, 0, 0, 0)")
        #expect(codeStyle["fontFamily"]?.lowercased().contains("mono") == true)

        for key in ["commandRight", "endKey", "controlE"] {
            let navigation = try #require(result[key] as? [String: Any])
            let selection = try #require(navigation["selection"] as? [String: Any])
            #expect(navigation["handled"] as? Bool == true)
            #expect(selection["anchor"] as? Int == firstLineEnd)
            #expect(selection["head"] as? Int == firstLineEnd)
            #expect((navigation["visibleText"] as? String)?.contains("**bold**") == true)
        }

        let shiftedNavigation = try #require(result["shiftCommandRight"] as? [String: Any])
        let shiftedSelection = try #require(shiftedNavigation["selection"] as? [String: Any])
        #expect(shiftedNavigation["handled"] as? Bool == true)
        #expect(shiftedSelection["anchor"] as? Int == boldPosition)
        #expect(shiftedSelection["head"] as? Int == firstLineEnd)

        let terminalSyntaxEndStates = try #require(result["terminalSyntaxEndStates"] as? [[String: Any]])
        #expect(terminalSyntaxEndStates.count == 6)
        for endState in terminalSyntaxEndStates {
            let name = endState["name"] as? String ?? "unknown syntax"
            let source = try #require(endState["source"] as? String)
            let end = try #require(endState["end"] as? Int)
            let keySelection = try #require(endState["keySelection"] as? [String: Any])
            let arrowSelection = try #require(endState["arrowSelection"] as? [String: Any])
            let focusSelection = try #require(endState["focusSelection"] as? [String: Any])
            #expect(endState["keyHandled"] as? Bool == true, "End jump was not handled for \(name)")
            #expect(keySelection["anchor"] as? Int == end, "Key cursor stopped inside \(name)")
            #expect(keySelection["head"] as? Int == end, "Key cursor stopped inside \(name)")
            #expect(endState["visibleAfterKey"] as? String == source)
            #expect(endState["arrowHandled"] as? Bool == true, "Closing marker was not skipped for \(name)")
            #expect(arrowSelection["anchor"] as? Int == end, "Arrow cursor stopped inside \(name)")
            #expect(arrowSelection["head"] as? Int == end, "Arrow cursor stopped inside \(name)")
            #expect(endState["visibleAfterArrow"] as? String == source)
            #expect(focusSelection["anchor"] as? Int == end, "Focus cursor stopped inside \(name)")
            #expect(focusSelection["head"] as? Int == end, "Focus cursor stopped inside \(name)")
            #expect(endState["visibleAfterFocus"] as? String == source)
        }
    }

    @MainActor
    @Test func markdownLivePreviewRendersClickableWikiLinksInStructuredMarkdown() async throws {
        let html = try MarkdownEditorResource.bundledHTML(testing: true)
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let resultJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              const source = "# [[Folder/Target#Heading|Heading alias]]\\n- **[[Other]]**\\nOutside";
              window.editor.setMarkdown(source);
              window.editorTest.setSelection(source.length);
              const links = [...document.querySelectorAll(".osn-wiki-link")];
              const firstStyle = links[0] ? getComputedStyle(links[0]) : null;
              const result = {
                visibleText: window.editorTest.visibleText(),
                labels: links.map((link) => link.textContent),
                color: firstStyle?.color ?? null,
                textDecorationLine: firstStyle?.textDecorationLine ?? null
              };
              links[0]?.dispatchEvent(new MouseEvent("click", {
                bubbles: true,
                cancelable: true
              }));
              links[1]?.dispatchEvent(new MouseEvent("click", {
                bubbles: true,
                cancelable: true,
                metaKey: true
              }));
              return JSON.stringify(result);
            })();
            """
        ) as? String)
        let data = try #require(resultJSON.data(using: .utf8))
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let visibleText = try #require(result["visibleText"] as? String)
        let labels = try #require(result["labels"] as? [String])
        let wikiMessages = messageHandler.receivedMessages.filter {
            $0["type"] as? String == "wikiLink"
        }

        #expect(labels == ["Heading alias", "Other"])
        #expect(visibleText.contains("Heading alias"))
        #expect(visibleText.contains("Other"))
        #expect(!visibleText.contains("[["))
        #expect(result["color"] as? String == "rgb(64, 156, 255)")
        #expect((result["textDecorationLine"] as? String)?.contains("underline") == true)
        #expect(wikiMessages.count == 2)
        #expect(wikiMessages[0]["target"] as? String == "Folder/Target#Heading")
        #expect(wikiMessages[0]["newWindow"] as? Bool == false)
        #expect(wikiMessages[1]["target"] as? String == "Other")
        #expect(wikiMessages[1]["newWindow"] as? Bool == true)
    }

    @MainActor
    @Test func markdownLivePreviewRendersClickableStandardMarkdownLinks() async throws {
        let html = try MarkdownEditorResource.bundledHTML(testing: true)
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let resultJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              const source = "# [Inbox](0009 Persönliches/00 Inbox/00 Inbox.md)\\n- **[Target](<Folder/Target.md>)**\\n![Preview](image.png)\\nOutside";
              window.editor.setMarkdown(source);
              window.editorTest.setSelection(source.length);
              const links = [...document.querySelectorAll(".osn-markdown-link")];
              const firstStyle = links[0] ? getComputedStyle(links[0]) : null;
              const result = {
                visibleText: window.editorTest.visibleText(),
                labels: links.map((link) => link.textContent),
                color: firstStyle?.color ?? null,
                textDecorationLine: firstStyle?.textDecorationLine ?? null
              };
              links[0]?.dispatchEvent(new MouseEvent("click", {
                bubbles: true,
                cancelable: true
              }));
              links[1]?.dispatchEvent(new MouseEvent("click", {
                bubbles: true,
                cancelable: true,
                metaKey: true
              }));
              return JSON.stringify(result);
            })();
            """
        ) as? String)
        let data = try #require(resultJSON.data(using: .utf8))
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let visibleText = try #require(result["visibleText"] as? String)
        let labels = try #require(result["labels"] as? [String])
        let markdownLinkMessages = messageHandler.receivedMessages.filter {
            $0["type"] as? String == "markdownLink"
        }

        #expect(labels == ["Inbox", "Target"])
        #expect(visibleText.contains("Inbox"))
        #expect(visibleText.contains("Target"))
        #expect(!visibleText.contains("](0009"))
        #expect(!visibleText.contains("](<Folder"))
        #expect(result["color"] as? String == "rgb(64, 156, 255)")
        #expect((result["textDecorationLine"] as? String)?.contains("underline") == true)
        #expect(markdownLinkMessages.count == 2)
        let firstMessage = try #require(markdownLinkMessages.first)
        let secondMessage = try #require(markdownLinkMessages.dropFirst().first)
        #expect(firstMessage["target"] as? String == "0009 Persönliches/00 Inbox/00 Inbox.md")
        #expect(firstMessage["newWindow"] as? Bool == false)
        #expect(secondMessage["target"] as? String == "Folder/Target.md")
        #expect(secondMessage["newWindow"] as? Bool == true)
    }

    @MainActor
    @Test func wrappedLivePreviewLinksStayLeftAlignedAndDoNotMoveTheEditorOnClick() async throws {
        let html = try MarkdownEditorResource.bundledHTML(testing: true)
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 150, height: 180),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let resultJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              const source = "[A deliberately long Markdown link label that wraps](Target.md)\\n\\nTail";
              window.editor.setMarkdown(source);
              window.editorTest.setSelection(source.length);
              const link = document.querySelector(".osn-markdown-link");
              if (!link) return null;

              const before = window.editorTest.getSelection();
              const scroller = document.querySelector(".cm-scroller");
              const scrollTopBefore = scroller.scrollTop;
              const focusedBefore = before.focused;
              const style = getComputedStyle(link);
              const rect = link.getBoundingClientRect();

              link.dispatchEvent(new MouseEvent("mousedown", {
                bubbles: true,
                cancelable: true,
                button: 0
              }));
              link.dispatchEvent(new MouseEvent("mouseup", {
                bubbles: true,
                cancelable: true,
                button: 0
              }));
              link.dispatchEvent(new MouseEvent("click", {
                bubbles: true,
                cancelable: true,
                button: 0
              }));

              const after = window.editorTest.getSelection();
              return JSON.stringify({
                textAlign: style.textAlign,
                wraps: rect.height > parseFloat(style.lineHeight) * 1.5,
                selectionUnchanged: before.anchor === after.anchor && before.head === after.head,
                focusUnchanged: focusedBefore === after.focused,
                scrollUnchanged: Math.abs(scroller.scrollTop - scrollTopBefore) < 0.5
              });
            })();
            """
        ) as? String)
        let data = try #require(resultJSON.data(using: .utf8))
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(result["wraps"] as? Bool == true)
        #expect(result["textAlign"] as? String == "left")
        #expect(result["selectionUnchanged"] as? Bool == true)
        #expect(result["focusUnchanged"] as? Bool == true)
        #expect(result["scrollUnchanged"] as? Bool == true)
    }

    @MainActor
    @Test func livePreviewLinksReportHoverSessionsWithoutChangingTheEditor() async throws {
        let html = try MarkdownEditorResource.bundledHTML(testing: true)
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let editorStateJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              const source = "[Target](Folder/Target.md) and [[Other]]";
              window.editor.setMarkdown(source);
              window.editorTest.setSelection(source.indexOf(" and ") + 2);
              const before = window.editorTest.getSelection();
              const markdownLink = document.querySelector(".osn-markdown-link");
              const wikiLink = document.querySelector(".osn-wiki-link");
              for (const link of [markdownLink, wikiLink]) {
                link?.dispatchEvent(new MouseEvent("mouseenter", {clientX: 30, clientY: 40}));
                link?.dispatchEvent(new MouseEvent("mouseleave", {clientX: 30, clientY: 40}));
              }
              const after = window.editorTest.getSelection();
              return JSON.stringify({before, after});
            })();
            """
        ) as? String)
        let editorStateData = try #require(editorStateJSON.data(using: .utf8))
        let editorState = try #require(JSONSerialization.jsonObject(with: editorStateData) as? [String: Any])
        let before = try #require(editorState["before"] as? [String: Any])
        let after = try #require(editorState["after"] as? [String: Any])
        let hoverMessages = messageHandler.receivedMessages.filter {
            $0["type"] as? String == "linkPreviewHover"
        }

        #expect(before["anchor"] as? Int == after["anchor"] as? Int)
        #expect(before["head"] as? Int == after["head"] as? Int)
        #expect(hoverMessages.count == 4)
        #expect(hoverMessages.map { $0["phase"] as? String } == ["entered", "exited", "entered", "exited"])
        #expect(hoverMessages.map { $0["kind"] as? String } == ["markdown", "markdown", "wiki", "wiki"])
        #expect(hoverMessages[0]["target"] as? String == "Folder/Target.md")
        #expect(hoverMessages[2]["target"] as? String == "Other")
        #expect(hoverMessages[0]["sessionID"] as? String == hoverMessages[1]["sessionID"] as? String)
        #expect(hoverMessages[2]["sessionID"] as? String == hoverMessages[3]["sessionID"] as? String)
        #expect(hoverMessages[0]["anchor"] as? [String: Double] != nil)
    }

    @MainActor
    @Test func markdownEditorDisplaysInsertedImageEmbedWhileKeepingMarkdownSource() async throws {
        let html = try MarkdownEditorResource.bundledHTML(testing: true)
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let imageDataURL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        let resultJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              window.editor.setMarkdown("Intro");
              window.editorTest.setSelection("Intro".length);
              window.editor.setMediaEmbeds({"Attachments/pasted.png": "\(imageDataURL)"});
              window.editor.insertMediaEmbed("![[Attachments/pasted.png]]");
              const selection = window.editorTest.getSelection();
              const markdown = window.editorTest.getMarkdown();
              const imageCount = window.editorTest.imageEmbedCount();
              const imageSources = window.editorTest.imageEmbedSources();
              return JSON.stringify({selection, markdown, imageCount, imageSources});
            })();
            """
        ) as? String)
        let resultData = try #require(resultJSON.data(using: .utf8))
        let result = try #require(JSONSerialization.jsonObject(with: resultData) as? [String: Any])
        let selection = try #require(result["selection"] as? [String: Any])
        let markdown = try #require(result["markdown"] as? String)
        let imageSources = try #require(result["imageSources"] as? [String])

        #expect(markdown == "Intro\n![[Attachments/pasted.png]]\n")
        #expect(result["imageCount"] as? Int == 1)
        #expect(imageSources == [imageDataURL])
        #expect(selection["head"] as? Int == markdown.utf16.count)
    }

    @MainActor
    @Test func markdownEditorHandlesListIndentationKeysInWebView() async throws {
        let html = try MarkdownEditorResource.bundledHTML(testing: true)
        let messageHandler = MarkdownEditorReadyMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(messageHandler, name: "editor")
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(3)
        while !messageHandler.isReady && messageHandler.errorMessage == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(messageHandler.errorMessage == nil)
        #expect(messageHandler.isReady)

        let indentationJSON = try #require(try await webView.evaluateJavaScript(
            """
            (() => {
              window.editor.setMarkdown("- Item");
              window.editorTest.setSelection(6);
              const tabHandled = window.editorTest.dispatchKey("Tab");
              const afterTab = window.editorTest.getMarkdown();

              window.editorTest.setSelection(afterTab.length);
              const enterHandled = window.editorTest.dispatchKey("Enter");
              const afterEnter = window.editorTest.getMarkdown();

              window.editor.setMarkdown("  - Item");
              window.editorTest.setSelection("  - Item".length);
              const commandShiftTabHandled = window.editorTest.dispatchKey("Tab", {
                metaKey: true,
                shiftKey: true
              });
              const afterCommandShiftTab = window.editorTest.getMarkdown();

              window.editor.setMarkdown("    - ");
              window.editorTest.setSelection("    - ".length);
              const backspaceHandled = window.editorTest.dispatchKey("Backspace");
              const afterBackspace = window.editorTest.getMarkdown();

              window.editor.setMarkdown("- First\\n- Second\\n- ");
              window.editorTest.setSelection("- First\\n- Second\\n- ".length);
              const emptyEnterHandled = window.editorTest.dispatchKey("Enter");
              const afterEmptyEnter = window.editorTest.getMarkdown();
              const afterEmptyEnterSelection = window.editorTest.getSelection();

              window.editor.setMarkdown("1. Ordered");
              window.editorTest.setSelection("1. Ordered".length);
              const orderedEnterHandled = window.editorTest.dispatchKey("Enter");
              const afterOrderedEnter = window.editorTest.getMarkdown();

              window.editor.setMarkdown("- [ ] Task");
              window.editorTest.setSelection("- [ ] Task".length);
              const taskEnterHandled = window.editorTest.dispatchKey("Enter");
              const afterTaskEnter = window.editorTest.getMarkdown();

              return JSON.stringify({
                tabHandled,
                afterTab,
                enterHandled,
                afterEnter,
                commandShiftTabHandled,
                afterCommandShiftTab,
                backspaceHandled,
                afterBackspace,
                emptyEnterHandled,
                afterEmptyEnter,
                afterEmptyEnterSelection,
                orderedEnterHandled,
                afterOrderedEnter,
                taskEnterHandled,
                afterTaskEnter
              });
            })();
            """
        ) as? String)
        let indentationData = try #require(indentationJSON.data(using: .utf8))
        let indentation = try #require(
            JSONSerialization.jsonObject(with: indentationData) as? [String: Any]
        )

        #expect(indentation["tabHandled"] as? Bool == true)
        #expect(indentation["afterTab"] as? String == "  - Item")
        #expect(indentation["enterHandled"] as? Bool == true)
        #expect(indentation["afterEnter"] as? String == "  - Item\n  - ")
        #expect(indentation["commandShiftTabHandled"] as? Bool == true)
        #expect(indentation["afterCommandShiftTab"] as? String == "- Item")
        #expect(indentation["backspaceHandled"] as? Bool == true)
        #expect(indentation["afterBackspace"] as? String == "  - ")
        #expect(indentation["emptyEnterHandled"] as? Bool == true)
        #expect(indentation["afterEmptyEnter"] as? String == "- First\n- Second\n")
        let emptyEnterSelection = try #require(indentation["afterEmptyEnterSelection"] as? [String: Any])
        #expect(emptyEnterSelection["head"] as? Int == ("- First\n- Second\n" as NSString).length)
        #expect(indentation["orderedEnterHandled"] as? Bool == true)
        #expect(indentation["afterOrderedEnter"] as? String == "1. Ordered\n2. ")
        #expect(indentation["taskEnterHandled"] as? Bool == true)
        #expect(indentation["afterTaskEnter"] as? String == "- [ ] Task\n- [ ] ")
    }

    @MainActor
    @Test func titleFieldReturnCommitsAndRequestsEditorFocus() async throws {
        var title = "Old Title"
        var didCommit = false
        let binding = Binding<String>(
            get: { title },
            set: { title = $0 }
        )
        let coordinator = SelectAllOnFocusTextField.Coordinator(text: binding)
        coordinator.onCommit = { _ in
            didCommit = true
        }
        let textField = NSTextField()
        let fieldEditor = NSTextView()
        fieldEditor.string = "New Title"

        let handled = coordinator.control(
            textField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        #expect(handled)
        #expect(title == "New Title")
        #expect(textField.stringValue == "New Title")
        try await Task.sleep(nanoseconds: 1_000_000)
        #expect(didCommit)
    }

    @MainActor
    @Test func appDelegateBuildsDistinctCascadedEditorWindows() {
        let delegate = AppDelegate()
        let first = delegate.getOrBuildWindow(mode: .newNote)
        let second = delegate.getOrBuildWindow(mode: .newNote)
        defer {
            first.close()
            second.close()
        }

        #expect(first !== second)
        #expect(first.frame.origin.x - second.frame.origin.x == 22)
        #expect(first.frame.origin.y - second.frame.origin.y == 22)
    }

    @MainActor
    @Test func appDelegateNavigatesWikiLinksInTheCurrentOrANewVaultWindow() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folderURL = temporaryVaultURL.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let linkedURL = folderURL.appendingPathComponent("Target.md")
        try "# Target".write(to: linkedURL, atomically: true, encoding: .utf8)
        VaultStore.saveVaultURL(temporaryVaultURL)

        let delegate = AppDelegate()
        let sourceWindow = delegate.getOrBuildWindow(mode: .newNote)
        var openedWindow: NSWindow?
        defer {
            sourceWindow.close()
            openedWindow?.close()
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            UserDefaults.standard.removeObject(forKey: NoteMode.editVaultFile.draftTitleKey)
            UserDefaults.standard.removeObject(forKey: NoteMode.editVaultFile.draftTextKey)
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.search")
        }

        let currentWindow = try #require(delegate.openWikiLink(
            "Folder/Target#Details|Alias",
            from: sourceWindow,
            inNewWindow: false
        ))
        #expect(currentWindow === sourceWindow)
        #expect(delegate.mode(for: currentWindow) == .editVaultFile)
        #expect(UserDefaults.standard.string(forKey: NoteMode.editVaultFile.draftTitleKey) == "Folder/Target.md")

        openedWindow = try #require(delegate.openWikiLink(
            "Folder/Target#Details",
            from: sourceWindow,
            inNewWindow: true
        ))
        #expect(openedWindow !== sourceWindow)
        #expect(delegate.mode(for: try #require(openedWindow)) == .editVaultFile)
    }

    @MainActor
    @Test func appDelegateNavigatesStandardMarkdownLinksInTheCurrentOrANewVaultWindow() throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folderURL = temporaryVaultURL.appendingPathComponent("0009 Persönliches/00 Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let linkedURL = folderURL.appendingPathComponent("00 Inbox.md")
        try "# Inbox".write(to: linkedURL, atomically: true, encoding: .utf8)
        VaultStore.saveVaultURL(temporaryVaultURL)

        let delegate = AppDelegate()
        let sourceWindow = delegate.getOrBuildWindow(mode: .newNote)
        var openedWindow: NSWindow?
        defer {
            sourceWindow.close()
            openedWindow?.close()
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
            UserDefaults.standard.removeObject(forKey: NoteMode.editVaultFile.draftTitleKey)
            UserDefaults.standard.removeObject(forKey: NoteMode.editVaultFile.draftTextKey)
            UserDefaults.standard.removeObject(forKey: "draft.editVaultFile.search")
        }

        let currentWindow = try #require(delegate.openMarkdownLink(
            "0009 Persönliches/00 Inbox/00 Inbox.md#Heading",
            from: sourceWindow,
            inNewWindow: false
        ))
        #expect(currentWindow === sourceWindow)
        #expect(delegate.mode(for: currentWindow) == .editVaultFile)
        #expect(
            UserDefaults.standard.string(forKey: NoteMode.editVaultFile.draftTitleKey)
                == "0009 Persönliches/00 Inbox/00 Inbox.md"
        )

        openedWindow = try #require(delegate.openMarkdownLink(
            "0009 Persönliches/00 Inbox/00 Inbox.md",
            from: sourceWindow,
            inNewWindow: true
        ))
        #expect(openedWindow !== sourceWindow)
        #expect(delegate.mode(for: try #require(openedWindow)) == .editVaultFile)
    }

    @MainActor
    @Test func appDelegateOpensExternalMarkdownLinksAtTheWorkspaceBoundary() throws {
        let delegate = AppDelegate()
        var openedURL: URL?
        delegate.externalURLOpener = { url in
            openedURL = url
            return true
        }

        let window = delegate.openMarkdownLink(
            "https://example.com/notes?id=42#details",
            from: nil,
            inNewWindow: false
        )

        #expect(window == nil)
        #expect(openedURL == URL(string: "https://example.com/notes?id=42#details"))
    }

    @MainActor
    @Test func linkPreviewControllerShowsANonActivatingReadOnlyVaultNoteAndDismissesItAfterExit() async throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        let noteURL = temporaryVaultURL.appendingPathComponent("Target.md")
        try "# Preview body\n\n[Child](Child.md)".write(to: noteURL, atomically: true, encoding: .utf8)
        VaultStore.saveVaultURL(temporaryVaultURL)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        let controller = LinkPreviewController(
            hoverDelayProvider: { 0 },
            dismissalDelay: 0.05
        )
        let sourceWindow = NSWindow()
        let anchor = NSRect(x: 400, y: 400, width: 80, height: 20)
        let entered = LinkPreviewHoverEvent(
            phase: .entered,
            sessionID: "source-target",
            kind: .markdown,
            target: "Target.md",
            anchorScreenRect: anchor
        )

        controller.handle(entered, from: sourceWindow)
        try await Task.sleep(nanoseconds: 30_000_000)

        let previewWindow = try #require(controller.visibleWindows.first)
        #expect(controller.visibleWindows.count == 1)
        #expect(previewWindow.isVisible)
        #expect(!previewWindow.canBecomeKey)
        #expect(previewWindow.title == "Target")
        #expect(!previewWindow.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)))

        let editorDeadline = Date().addingTimeInterval(2)
        var previewEditor = firstDescendant(of: WKWebView.self, in: previewWindow.contentView)
        while previewEditor == nil && Date() < editorDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
            previewEditor = firstDescendant(of: WKWebView.self, in: previewWindow.contentView)
        }
        let previewWebView = try #require(previewEditor)
        var previewPresentation: [String: Any]?
        var lastPreviewCandidate: [String: Any]?
        while previewPresentation == nil && Date() < editorDeadline {
            if let json = try? await previewWebView.evaluateJavaScript(
                """
                window.editor ? JSON.stringify({
                  contentEditable: document.querySelector(".cm-content")?.getAttribute("contenteditable"),
                  visibleText: document.querySelector(".cm-content")?.innerText,
                  linkCount: document.querySelectorAll(".osn-markdown-link").length
                }) : null;
                """
            ) as? String,
               let data = json.data(using: .utf8) {
                let candidate = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                lastPreviewCandidate = candidate
                if candidate?["contentEditable"] as? String == "false",
                   (candidate?["visibleText"] as? String)?.contains("Preview body") == true,
                   candidate?["linkCount"] as? Int == 1 {
                    previewPresentation = candidate
                }
            }
            if previewPresentation == nil {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        let presentation = try #require(
            previewPresentation,
            "Last preview state: \(String(describing: lastPreviewCandidate))"
        )
        #expect(presentation["contentEditable"] as? String == "false")
        #expect((presentation["visibleText"] as? String)?.contains("Preview body") == true)
        #expect(presentation["linkCount"] as? Int == 1)

        controller.handle(
            LinkPreviewHoverEvent(
                phase: .exited,
                sessionID: "source-target",
                kind: .markdown,
                target: "Target.md",
                anchorScreenRect: anchor
            ),
            from: sourceWindow
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(controller.visibleWindows.isEmpty)
    }

    @MainActor
    @Test func recursiveLinkPreviewsStayOpenAcrossPointerTransitionsAndCloseAsASubtree() async throws {
        let temporaryVaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryVaultURL, withIntermediateDirectories: true)
        try "[Child](Child.md)".write(
            to: temporaryVaultURL.appendingPathComponent("Target.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Child body".write(
            to: temporaryVaultURL.appendingPathComponent("Child.md"),
            atomically: true,
            encoding: .utf8
        )
        VaultStore.saveVaultURL(temporaryVaultURL)
        defer {
            try? FileManager.default.removeItem(at: temporaryVaultURL)
            UserDefaults.standard.removeObject(forKey: VaultStore.pathKey)
            UserDefaults.standard.removeObject(forKey: VaultStore.bookmarkKey)
            UserDefaults.standard.removeObject(forKey: "obsidianVault")
        }

        let controller = LinkPreviewController(
            hoverDelayProvider: { 0 },
            dismissalDelay: 0.05
        )
        let sourceWindow = NSWindow()
        let anchor = NSRect(x: 400, y: 400, width: 80, height: 20)
        let targetEntered = LinkPreviewHoverEvent(
            phase: .entered,
            sessionID: "source-target",
            kind: .markdown,
            target: "Target.md",
            anchorScreenRect: anchor
        )
        controller.handle(targetEntered, from: sourceWindow)
        try await Task.sleep(nanoseconds: 30_000_000)
        let targetPreview = try #require(controller.visibleWindows.first { $0.title == "Target" })

        controller.handle(
            LinkPreviewHoverEvent(
                phase: .exited,
                sessionID: targetEntered.sessionID,
                kind: targetEntered.kind,
                target: targetEntered.target,
                anchorScreenRect: anchor
            ),
            from: sourceWindow
        )
        controller.pointerEntered(targetPreview)

        let childEntered = LinkPreviewHoverEvent(
            phase: .entered,
            sessionID: "target-child",
            kind: .markdown,
            target: "Child.md",
            anchorScreenRect: NSRect(x: targetPreview.frame.maxX - 80, y: targetPreview.frame.midY, width: 60, height: 18)
        )
        controller.handle(childEntered, from: targetPreview)
        try await Task.sleep(nanoseconds: 30_000_000)
        let childPreview = try #require(controller.visibleWindows.first { $0.title == "Child" })

        controller.handle(
            LinkPreviewHoverEvent(
                phase: .exited,
                sessionID: childEntered.sessionID,
                kind: childEntered.kind,
                target: childEntered.target,
                anchorScreenRect: childEntered.anchorScreenRect
            ),
            from: targetPreview
        )
        controller.pointerExited(targetPreview)
        controller.pointerEntered(childPreview)
        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(Set(controller.visibleWindows.map(\.title)) == ["Target", "Child"])

        controller.pointerExited(childPreview)
        controller.pointerEntered(targetPreview)
        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(controller.visibleWindows.map(\.title) == ["Target"])

        controller.pointerExited(targetPreview)
        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(controller.visibleWindows.isEmpty)
    }

    @MainActor
    @Test func contentViewModelRoutesLocalKeyEventsOnlyToItsOwnWindow() throws {
        let ownWindow = NSWindow()
        let otherWindow = NSWindow()
        let viewModel = ContentViewModel(mode: .editVaultFile)
        viewModel.setEventWindowNumber(ownWindow.windowNumber)

        let ownEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: ownWindow.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
        let otherEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: otherWindow.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))

        #expect(viewModel.eventBelongsToWindow(ownEvent))
        #expect(!viewModel.eventBelongsToWindow(otherEvent))
    }

    @MainActor
    @Test func titleFieldReturnIgnoringFieldEditorCommitsAndRequestsEditorFocus() async throws {
        var title = "Old Title"
        var didCommit = false
        let binding = Binding<String>(
            get: { title },
            set: { title = $0 }
        )
        let coordinator = SelectAllOnFocusTextField.Coordinator(text: binding)
        coordinator.onCommit = { _ in
            didCommit = true
        }
        let textField = NSTextField()
        let fieldEditor = NSTextView()
        fieldEditor.string = "New Title"

        let handled = coordinator.control(
            textField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
        )

        #expect(handled)
        #expect(title == "New Title")
        #expect(textField.stringValue == "New Title")
        try await Task.sleep(nanoseconds: 1_000_000)
        #expect(didCommit)
    }

    @MainActor
    @Test func titleFieldDirectReturnKeyCommitsAndRequestsEditorFocus() async throws {
        var title = "Old Title"
        var didCommit = false
        let binding = Binding<String>(
            get: { title },
            set: { title = $0 }
        )
        let coordinator = SelectAllOnFocusTextField.Coordinator(text: binding)
        coordinator.onCommit = { _ in
            didCommit = true
        }
        let textField = ReturnCommittingTextField()
        textField.stringValue = "New Title"

        coordinator.commitReturn(from: textField)

        #expect(title == "New Title")
        #expect(textField.stringValue == "New Title")
        try await Task.sleep(nanoseconds: 1_000_000)
        #expect(didCommit)
    }

    @MainActor
    @Test func titleFieldReturnCommitAlsoWorksThroughEndEditingNotification() async throws {
        var title = "Old Title"
        var didCommit = false
        let binding = Binding<String>(
            get: { title },
            set: { title = $0 }
        )
        let coordinator = SelectAllOnFocusTextField.Coordinator(text: binding)
        coordinator.onCommit = { _ in
            didCommit = true
        }
        let textField = NSTextField()
        textField.stringValue = "New Title"

        coordinator.controlTextDidEndEditing(
            Notification(
                name: NSText.didEndEditingNotification,
                object: textField,
                userInfo: ["NSTextMovement": NSReturnTextMovement]
            )
        )

        #expect(title == "New Title")
        try await Task.sleep(nanoseconds: 1_000_000)
        #expect(didCommit)
    }

    @Test func shortcutPolicyRejectsCommandOnlyGlobalShortcuts() {
        #expect(ShortcutPolicy.validationMessage(for: .newNote, key: "n", modifiers: .command) != nil)
        #expect(ShortcutPolicy.validationMessage(for: .newNote, key: "n", modifiers: [.command, .option]) == nil)
        #expect(ShortcutPolicy.validationMessage(for: .settings, key: ",", modifiers: .command) == nil)
    }

    @Test func shortcutNormalizationKeepsSingleLowercaseKey() {
        #expect(ShortcutPreference.normalized(" N ") == "n")
        #expect(ShortcutPreference.normalized(" ") == "space")
        #expect(ShortcutPreference.normalized("space") == "space")
        #expect(ShortcutPreference.normalized("", fallback: "d") == "d")
    }

    @MainActor
    @Test func globalShortcutPreferencesSupportSpaceKey() {
        KeyboardShortcuts.reset(.createNewNote)
        defer {
            KeyboardShortcuts.reset(.createNewNote)
        }

        ShortcutPreference.set("space", modifiers: [.command, .option, .control], for: .newNote)
        let shortcut = ShortcutPreference.definition(for: .newNote)

        #expect(shortcut.key == "space")
        #expect(shortcut.modifiers == [.command, .option, .control])
        #expect(shortcut.displayValue == "⌃⌥⌘ Space")
    }

    @Test func spaceShortcutUsesLiteralSpaceForMenuKeyEquivalent() {
        #expect(ShortcutDefinition(key: "space", modifiers: [.command, .option, .control]).menuKeyEquivalent == " ")
        #expect(ShortcutDefinition(key: "s", modifiers: [.command, .option, .control]).menuKeyEquivalent == "s")
    }

    @Test func emptyModifierFlagsDoNotBecomeCommandShortcuts() {
        #expect(ShortcutPreference.menuModifierFlags(from: []) == [])
        #expect(ShortcutPreference.menuModifierFlags(from: .command) == .command)
        #expect(ShortcutPreference.menuModifierFlags(from: [.command, .option]) == [.command, .option])
    }

    @Test func shortcutPolicyRejectsEmptyGlobalShortcutModifiers() {
        let message = ShortcutPolicy.validationMessage(for: .newNote, key: "n", modifiers: [])

        #expect(message == "Global shortcuts need Control or Option so they do not steal normal app commands.")
    }

    @Test @MainActor func keyboardRoutingLetsFocusedTextInputReceivePlainLetters() {
        let window = NSWindow()
        let textView = NSTextView()
        textView.isEditable = true
        window.contentView = textView
        window.makeFirstResponder(textView)

        let plainEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        )

        #expect(plainEvent != nil)
        #expect(KeyboardEventRouting.shouldHandleLocalShortcut(plainEvent!) == false)
    }

    @Test @MainActor func keyboardRoutingStillHandlesModifiedShortcutsInTextInput() {
        let window = NSWindow()
        let textView = NSTextView()
        textView.isEditable = true
        window.contentView = textView
        window.makeFirstResponder(textView)

        let commandEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        )

        #expect(commandEvent != nil)
        #expect(KeyboardEventRouting.shouldHandleLocalShortcut(commandEvent!) == true)
    }

    @Test @MainActor func keyboardRoutingHandlesCommandCommaForSettings() {
        let commandCommaEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: 43
        )

        #expect(commandCommaEvent != nil)
        #expect(KeyboardEventRouting.shouldHandleLocalShortcut(commandCommaEvent!) == true)
        #expect(ShortcutPreference.normalized(commandCommaEvent?.charactersIgnoringModifiers ?? "") == ShortcutAction.settings.defaultKey)
    }

}

@MainActor
private func firstDescendant<ViewType: NSView>(
    of type: ViewType.Type,
    in root: NSView?
) -> ViewType? {
    guard let root else { return nil }
    if let match = root as? ViewType {
        return match
    }
    for subview in root.subviews {
        if let match = firstDescendant(of: type, in: subview) {
            return match
        }
    }
    return nil
}
