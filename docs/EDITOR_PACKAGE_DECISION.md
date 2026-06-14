# Editor Package Decision

Date: 2026-06-10

## Decision

Use CodeMirror 6 inside a native `WKWebView` as the production editor foundation.

The app remains a SwiftUI/AppKit macOS app. Only the editable Markdown surface moves to a bundled web editor. SwiftUI still owns the note text, focus requests, media import integration, and autosave lifecycle; CodeMirror owns document editing, selection/caret behavior, command application, task-checkbox widgets, and Markdown key handling.

## Package Evaluation

### CodeMirror 6

Sources: https://codemirror.net/docs/guide/, https://codemirror.net/docs/ref/, https://github.com/codemirror/lang-markdown

CodeMirror is the best match for the app's editor bug class because document source, selections, transactions, widgets, and keymaps share one editor state model. It gives the app a stable way to render task checkboxes as widgets while preserving the Markdown source offsets underneath.

Fit:
- Strong source-fidelity fit for Obsidian-compatible Markdown files.
- Mature cursor/selection/change mapping, including replacement widgets for task boxes.
- Viewport-based rendering is a better foundation for large notes than custom attributed-string rerendering.
- Markdown package includes Markdown language support and keymaps.

Risk:
- Requires a small Swift-to-JavaScript bridge and bundled JS build step.
- Media paste/drop still needs native routing because the app saves files into the selected Obsidian vault.

### SwiftMarkdownEngine

Source: https://github.com/nodes-app/swift-markdown-engine

SwiftMarkdownEngine is the strongest native alternative. It includes live styling, wiki-link support, task checkboxes, embedded images, TextKit 2, and SwiftUI bridging. Its architecture is much closer to a real Markdown editor than custom regex rendering.

Fit:
- Strong feature overlap with the target editor experience.
- Could replace more custom Markdown rendering code than STTextView.
- Native AppKit/TextKit integration would avoid the WKWebView bridge.

Risk:
- Lower maturity than CodeMirror.
- Broader migration surface because it would replace both editor mechanics and Markdown behavior.
- Needs deeper validation against Obsidian-specific attachment paths and source round-tripping.

### STTextView

Source: https://github.com/krzyzanowskim/STTextView

STTextView remains useful as a native TextKit 2 text surface and is still present in the project for existing regression coverage, but it does not solve Markdown parsing, task-widget rendering, or source/selection semantics by itself. Keeping all of that logic custom is the path that produced the current editor edge cases.

## Migration Path

1. Keep the public SwiftUI editor boundary as `RichMarkdownEditorView`.
2. Bundle CodeMirror under `ObsidianSideNote/MarkdownEditor`.
3. Use `EditorWeb/` as the source package for the generated `editor.js` bundle.
4. Route focus requests, markdown changes, toolbar commands, task-checkbox toggles, and media paste/drop through the WKWebView bridge.
5. Keep the old native helper tests until their coverage is replaced by WebKit-facing tests or removed with the old native editor code.

## Current Status

The production editor path now loads CodeMirror in `WKWebView`. `script/build_and_run.sh` rebuilds the WebEditor bundle before Xcode builds the app.
