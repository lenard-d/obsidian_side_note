# Editor Package Decision

Date: 2026-06-04

## Decision

Use STTextView as the preferred package candidate for a future replacement of the current custom `NSTextView` bridge.

Do not migrate the production editor in-place without a dedicated behavior-parity pass. The current editor has app-specific behavior for Markdown source restoration, active-line syntax reveal, pasted media import, image preloading, task-checkbox toggling, and Obsidian attachment paths. STTextView can replace the lower-level TextKit/AppKit editing surface, but those behaviors still need to remain owned by this app.

## Package Evaluation

### STTextView

Source: https://github.com/krzyzanowskim/STTextView

Swift Package Index reports STTextView as an active TextKit 2 text view replacement with recent package activity, macOS support, 118 releases, and zero data-race safety errors as of the 2026-06-04 review.

Fit:
- Best match for replacing `MediaTextView` and reducing hand-maintained `NSTextView` subclass behavior.
- Keeps a native AppKit/TextKit editing model, which matches the current implementation and test surface.
- Better long-term foundation for line-level editor behavior than a display-only Markdown renderer.

Risk:
- It is not a drop-in Markdown editor for this app's Obsidian-specific rendering and source-preservation rules.
- TextKit 2 migration can change cursor mapping, selection ranges, attachment layout, undo behavior, and drag/paste handling.

### MarkdownEngine

Source: https://swiftpackageregistry.com/nodes-app/swift-markdown-engine

MarkdownEngine is a closer conceptual match for a native Markdown editor and includes live styling, wiki-link support, task checkboxes, embedded images, and SwiftUI bridging. It is currently a younger package, reviewed at version 0.4.0 on 2026-06-04.

Fit:
- Strong feature overlap with the target editor experience.
- Could replace more custom Markdown rendering code than STTextView.

Risk:
- Lower maturity than STTextView.
- Broader migration surface because it would replace both editor mechanics and Markdown behavior.
- Needs deeper validation against Obsidian-specific attachment paths and source round-tripping.

### CodeEditTextView and CodeEditorView

These are better fits for code-editor workloads than the current note-focused Markdown editor. CodeEditTextView's own package description points users who need system text-view parity toward STTextView or `NSTextView`.

## Migration Path

1. Keep `MediaTextView` isolated from `RichMarkdownEditorView` so the editing surface can be replaced without touching the SwiftUI coordinator and renderer at the same time.
2. Add focused parity tests before introducing STTextView:
   - selection survives active-line re-rendering
   - Markdown source round-trips through image attachments
   - task checkbox clicks update source text
   - paste/drop media still inserts Obsidian-relative attachment links
   - undo/redo remains native and local to the editor
3. Introduce STTextView behind the existing coordinator callbacks.
4. Port one behavior at a time: sizing, paste/drop, keyboard shortcuts, checkbox hit testing, source rendering.
5. Keep MarkdownEngine as a future candidate only if the goal changes from replacing the editing surface to replacing the full Markdown editor/rendering model.

## Current Status

The current codebase is prepared for the first migration step by separating `MediaTextView` into `ObsidianSideNote/Views/MediaTextView.swift`. No external editor dependency is added yet because the next step requires behavior-parity tests and a dedicated migration commit.
