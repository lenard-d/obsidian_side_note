# Architecture

Obsidian Side Note is a small SwiftUI/AppKit macOS app. The architecture is intentionally simple: SwiftUI owns the UI, AppKit handles menu-bar and window behavior, and small store/service types isolate persistence, file-system work, hotkeys, media import, and Obsidian URI construction.

## High-Level Flow

```text
Menu bar / global shortcut
        |
        v
AppDelegate
        |
        v
FloatingWindow + ContentView
        |
        +--> SettingsView
        +--> MarkdownEditorView
        +--> VaultSearchPanel
        +--> RichMarkdownEditorView
        |
        v
ContentViewModel
        |
        v
Stores and services
```

## App Entry

`ObsidianSideNoteApp.swift` contains the SwiftUI `App` entry point and the `AppDelegate`.

The `AppDelegate` owns:

- `NSStatusItem` menu-bar lifecycle.
- Menu item creation.
- Window creation and reuse.
- Global shortcut dispatch for note workflows.
- Local shortcut dispatch for Settings and Quit while the app is active.
- New Note resume-versus-force-new behavior.

The app uses a borderless `FloatingWindow` so the editor can stay compact, become key, and float above normal app windows.

## Models

`Models/` contains small value types and enums:

- `NoteMode`: current editor mode, draft key mapping, and titles.
- `ShortcutAction`: supported shortcut actions, preference keys, and global-shortcut mappings.
- `ShortcutDefinition`: display and storage shape for key combinations.
- `VaultNote`: a Markdown note found inside the selected vault.

These types should stay small and dependency-light.

## Stores

`Stores/` contains persistence and local file-system access:

- `VaultStore`: vault file indexing, file read/write, note creation, and attachment copy. It remains the compatibility facade used by the app.
- `VaultSelectionStore`: lowest-level bookmark/path persistence and security-scoped access checks. Both `VaultStore` and `AppConfigStore` depend on it, removing their previous cyclic dependency.
- `VaultPathResolver`: the single path-normalization and containment boundary for vault files, including symlink-escape rejection and Unicode path repair.
- `VaultMediaStore`: Markdown/wiki media resolution, bounded image caching, downsampling, and fallback vault scans behind the `VaultStore` facade.
- `VaultNoteSearch`: directory-scope parsing, fuzzy scoring, ranking, and result limiting for Edit Vault File suggestions.
- `ShortcutPreference`: UserDefaults-backed shortcut storage and normalization.
- `NewNotePreferences`: UserDefaults-backed New Note resume interval and draft metadata.
- `AppConfigStore`: JSON-backed persistence mirror for vault selection, shortcuts, resume interval, and login-item intent so rebuilds can restore setup state.
- `AppSettingsPersistenceCoordinator`: one-way orchestration for restoring and snapshotting independent preference stores into `AppConfigStore`; leaf stores never need to be read back by the config repository.
- `ShortcutPolicy`: shortcut validation rules, including collision and global-shortcut safety checks.
- `SetupDiagnostics`: setup/status labels derived from vault access, Obsidian detection, shortcuts, and login-item state.
- `LoginItemStore`: launch-at-login status and mutation. The `SMAppService` system change is the transaction boundary; intent is persisted only after macOS accepts the change.

Store types are static because the app has a single active vault. AppKit owns a registry of independent floating windows, while each window owns its own `ContentViewModel`, editor state, autosave work, and file monitor.

## Services

`Services/` contains integrations that are not UI views:

- `GlobalHotKeyManager`: registers configured note-workflow shortcuts as global Carbon hotkeys.
- `MediaAttachmentImporter`: normalizes paste/drop/import sources for local files, pasteboard images, and remote media URLs. Its public asynchronous result preserves unsupported, provider-load, download, response-validation, and vault-save failures instead of collapsing them to `nil`.
- `RemoteMediaDownloader`: isolated `URLSession` transport adapter for remote media, with an explicit byte limit and response preservation for diagnostics.
- `VaultNoteFileMonitor`: watches the active Markdown file for external writes and atomic replacements so edits made in Obsidian can update the open Side Note editor.
- `ObsidianURIBuilder`: builds Obsidian URIs for opening daily notes and files in Obsidian.
- `AppLogger`: central structured logging with `debug`, `info`, `warn`, and `error` levels, privacy-safe error summaries, and a bounded diagnostic buffer. XCTest output defaults to `off` while diagnostics remain inspectable after a failure.

The app edits local Markdown files directly where possible. Obsidian URI is reserved for workflows that need Obsidian itself, such as opening the daily note, opening a selected note, or rewriting inline wiki links for rendered Markdown.

Only Append to Daily Note, Create New Note, and Edit Vault File are global. Settings and Quit are intentionally local to avoid stealing standard shortcuts from the foreground app.

The global shortcut layer deliberately follows the pattern used by established launcher/menu-bar apps: globally trigger only explicit workflow commands, keep app-management commands local, store user choices in `UserDefaults`, mirror persistent setup choices into `Application Support/ObsidianSideNote/config.json`, and reject Command-only global shortcuts because they commonly collide with foreground-app menu commands.

## Views

`Views/` contains SwiftUI surfaces:

- `SettingsView`: vault picker, New Note interval, and shortcut rows.
- `SetupView`: first-run setup and diagnostic checklist.
- `KeyboardShortcutRow`: shortcut recorder UI.
- `MarkdownEditorView`: Markdown toolbar, rich text editor shell, and paste/drop handling.
- `RichMarkdownEditorView`: WKWebView bridge for the editable Markdown surface. SwiftUI owns the Markdown string and focus requests; the embedded CodeMirror editor owns text editing, selection, command application, task-checkbox widgets, bullet-marker widgets, heading line styling, and Markdown key handling.
- `MarkdownEditorResource`: validates and inlines the bundled CodeMirror HTML/JavaScript resources.
- `MarkdownEditorWebView`: the AppKit drag/drop and first-responder boundary around WKWebView.
- `MarkdownEditor/`: bundled HTML and generated CodeMirror JavaScript loaded by the WKWebView editor.
- `EditorWeb/src/editor-test-adapter.js`: WebKit inspection helpers exposed as `window.editorTest` only when tests explicitly request test-enabled HTML. The production `window.editor` bridge contains only commands used by the Swift adapter.
- `EditorWeb/src/editor-theme.js`: CodeMirror visual theme and Markdown syntax highlighting, kept separate from editor transactions and presentation behavior.
- `Models/EmbeddedMedia`: parsing for image/video embeds that the CodeMirror adapter preloads.
- `NoteEditorChrome`: shared header, search panel, and missing-vault prompt.

`ContentView.swift` composes these views. `ContentViewModel` owns the active editor state, draft loading, search results, note selection, autosave scheduling, media insertion, and Obsidian-open commands for the current mode.

## Autosave Behavior

New Note mode:

1. Title and body are stored as a local draft.
2. No file is created while the body is empty.
3. Once the body has content, `VaultStore.createOrUpdateNote` creates the Markdown file.
4. Subsequent body changes write to the same created note.
5. Once a note file exists, the active file is watched while open. External writes from Obsidian reload the editor text and cancel any pending stale autosave.

Edit Vault File mode:

1. Search returns `VaultNote` values from the selected vault.
2. Selecting a note loads its current Markdown text.
3. Editor changes are debounced and written on one serial persistence queue.
4. The selected file is watched while open. External reads and autosaves share the persistence queue, so an in-flight stale write cannot overwrite a detected Obsidian edit.

Append to Daily Note mode:

1. The editor resolves today's daily note from Obsidian's Daily Notes settings.
2. If the file is missing, the app creates it directly in the configured daily-note folder and applies the configured template when available.
3. Editor changes autosave directly to that Markdown file.
4. The daily note file is watched while open, so external Obsidian edits are pulled into the editor before subsequent Side Note autosaves.
5. Opening the daily note in Obsidian is a separate command.

## Media Handling

Paste and drag-and-drop handling live in `MarkdownEditorView` and are normalized by `MediaAttachmentImporter`.

- Pasted images are converted to PNG.
- Pasted and dropped media files are copied as-is when supported.
- Remote media URLs are accepted only for supported extensions, bounded to 25 MB, and rejected when an explicit `Content-Type` is not an image/video match.
- Files are stored in Obsidian's configured attachment folder when it is a safe vault-relative path, otherwise in the vault root.
- The editor inserts a Markdown embed pointing at the vault-relative attachment path.
- Plain text paste is left to CodeMirror/WKWebView. Media paste/drop is detected by the WebKit bridge and routed through `MediaAttachmentImporter`.
- Import failures are returned as typed results, recorded through the central media log channel without URLs or file contents, and shown to the user by the SwiftUI editor shell.

- The editable editor intentionally keeps the raw Markdown string as the CodeMirror document.
- Inline syntax presentation is data-driven: each supported syntax node maps its marker type to a presentation class. Bold text is rendered with strong emphasis while inactive, and its `**` markers are replaced visually. Moving the cursor into that syntax range reveals the markers for predictable source editing. Further inline styles can use the same mapping instead of adding feature-specific editor branches.
- Task checkboxes are rendered as CodeMirror replacement widgets over the `[ ]` / `[x]` marker. The marker remains in the document source, and CodeMirror maps cursor/selection through the widget range.
- When the cursor is adjacent to the checkbox marker, the raw marker is revealed so source editing remains predictable without turning the whole task line back into text.
- Image embeds on their own line are rendered as CodeMirror block widgets when the cursor is outside that line. Swift resolves local vault images into bounded data URLs for the web editor, while the Markdown embed line remains the document source and is revealed for editing when selected.
- Embed lines such as `![Title](path-or-url)` are parsed for image preloading when their extension is supported.
- Local relative paths are resolved through `VaultStore.url(forMarkdownLink:)` and `VaultStore.url(forWikiLink:)`, with vault-bound path validation.

## Testing

`ObsidianSideNoteTests/` covers:

- Empty New Note protection.
- Markdown file creation.
- Vault search indexing, directory-scoped fuzzy ranking, and lazy suggestion limiting.
- Vault file writes.
- Obsidian Daily Note URI construction.
- Shortcut storage and hotkey mapping.
- New Note resume interval.
- Markdown media parsing.
- Media attachment type detection.
- Relative vault media URL resolution.
- Vault-relative path traversal rejection for Markdown links and Obsidian-configured folders.
- Remote media byte-limit and content-type checks.
- Two-way active-note sync, including New Note, Edit Vault File, atomic external writes, and cancellation of stale pending autosaves.
- Rich Markdown editor rendering, command application, heading hierarchy, task-list toggling, bullet-marker presentation, smart list editing, and media preload behavior.
- Inline image embed rendering in the bundled CodeMirror editor.
- Structured log levels, quiet test configuration, and diagnostic-buffer bounds.
- Launch-at-login rejection without falsely persisted enabled state.
- Typed media failures at the `NSItemProvider`, network-transport, and vault-save boundaries.

The serialized Swift Testing suite is split by responsibility into vault/session, media/configuration, editor/window, logging, and shared-support files. `ObsidianSideNoteUITests/` exercises repeated app launch plus an end-to-end Edit Vault File flow that verifies typing and toolbar commands reach the Markdown file on disk.

Run:

```bash
xcodebuild test \
  -project ObsidianSideNote.xcodeproj \
  -scheme ObsidianSideNote \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES
```

## Design Principles

- Keep UI state in SwiftUI views.
- Keep file-system and UserDefaults access in stores.
- Keep Obsidian URI construction out of views.
- Prefer small, testable helpers over broad manager objects.
- Avoid creating empty Markdown files.
- Preserve Obsidian compatibility by writing normal Markdown files into the vault.
- Treat Obsidian-configured folders and Markdown links as vault-relative paths; reject path traversal instead of following paths outside the selected vault.
- Route all vault URL construction through `VaultPathResolver`; never duplicate containment checks at call sites.
