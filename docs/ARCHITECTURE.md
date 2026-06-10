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
- `ShortcutAction`: supported shortcut actions and hotkey identifiers.
- `ShortcutDefinition`: display and storage shape for key combinations.
- `VaultNote`: a Markdown note found inside the selected vault.

These types should stay small and dependency-light.

## Stores

`Stores/` contains persistence and local file-system access:

- `VaultStore`: selected vault bookmark, vault search, file read/write, note creation, attachment copy, and Markdown media URL resolution.
- `ShortcutPreference`: UserDefaults-backed shortcut storage and normalization.
- `NewNotePreferences`: UserDefaults-backed New Note resume interval and draft metadata.
- `AppConfigStore`: JSON-backed persistence mirror for vault selection, shortcuts, resume interval, and login-item intent so rebuilds can restore setup state.
- `ShortcutPolicy`: shortcut validation rules, including collision and global-shortcut safety checks.
- `SetupDiagnostics`: setup/status labels derived from vault access, Obsidian detection, shortcuts, and login-item state.
- `LoginItemStore`: launch-at-login status and mutation.

Store types are static because the app currently has a single active vault and a single editor window.

## Services

`Services/` contains integrations that are not UI views:

- `GlobalHotKeyManager`: registers configured note-workflow shortcuts as global Carbon hotkeys.
- `MediaAttachmentImporter`: normalizes paste/drop/import sources for local files, pasteboard images, remote media URLs, and media size/content-type checks.
- `RemoteMediaDownloader`: downloads remote media with an explicit byte limit.
- `ObsidianURIBuilder`: builds Obsidian URIs for opening daily notes and files in Obsidian.
- `AppLogger`: central OSLog categories.

The app edits local Markdown files directly where possible. Obsidian URI is reserved for workflows that need Obsidian itself, such as opening the daily note, opening a selected note, or rewriting inline wiki links for rendered Markdown.

Only Append to Daily Note, Create New Note, and Edit Vault File are global. Settings and Quit are intentionally local to avoid stealing standard shortcuts from the foreground app.

The global shortcut layer deliberately follows the pattern used by established launcher/menu-bar apps: globally trigger only explicit workflow commands, keep app-management commands local, store user choices in `UserDefaults`, mirror persistent setup choices into `Application Support/ObsidianSideNote/config.json`, and reject Command-only global shortcuts because they commonly collide with foreground-app menu commands.

## Views

`Views/` contains SwiftUI surfaces:

- `SettingsView`: vault picker, New Note interval, and shortcut rows.
- `SetupView`: first-run setup and diagnostic checklist.
- `KeyboardShortcutRow`: shortcut recorder UI.
- `MarkdownEditorView`: Markdown toolbar, rich text editor shell, and paste/drop handling.
- `RichMarkdownEditorView`: AppKit/STTextView bridge that renders source-preserving Markdown attributes, handles focus, media preloading, paste/drop callbacks, and coordinates editor commands.
- `MediaTextView`: STTextView subclass for media paste/drop routing, Markdown shortcut routing, list-editing command routing, scrolling, and task-checkbox hit testing.
- `MarkdownEditingEngine`: pure Markdown editing rules for list markers, task toggles, smart Return behavior, and list indent/outdent.
- `MarkdownEditorTextRenderer`: source-preserving Markdown-to-attributed-text renderer. It styles the exact Markdown string held by the editor instead of replacing syntax with shorter display text, so native selection, arrow navigation, undo, and click handling operate on the same offsets that are written to disk.
- `RichMarkdownView`: Markdown rendering plus line-level image/video embed rendering.
- `NoteEditorChrome`: shared header, search panel, and missing-vault prompt.

`ContentView.swift` composes these views. `ContentViewModel` owns the active editor state, draft loading, search results, note selection, autosave scheduling, media insertion, and Obsidian-open commands for the current mode.

## Autosave Behavior

New Note mode:

1. Title and body are stored as a local draft.
2. No file is created while the body is empty.
3. Once the body has content, `VaultStore.createOrUpdateNote` creates the Markdown file.
4. Subsequent body changes write to the same created note.

Edit Vault File mode:

1. Search returns `VaultNote` values from the selected vault.
2. Selecting a note loads its current Markdown text.
3. Editor changes write back to that file immediately.

Append to Daily Note mode:

1. The editor resolves today's daily note from Obsidian's Daily Notes settings.
2. If the file is missing, the app creates it directly in the configured daily-note folder and applies the configured template when available.
3. Editor changes autosave directly to that Markdown file.
4. Opening the daily note in Obsidian is a separate command.

## Media Handling

Paste and drag-and-drop handling live in `MarkdownEditorView` and are normalized by `MediaAttachmentImporter`.

- Pasted images are converted to PNG.
- Pasted and dropped media files are copied as-is when supported.
- Remote media URLs are accepted only for supported extensions, bounded to 25 MB, and rejected when an explicit `Content-Type` is not an image/video match.
- Files are stored in Obsidian's configured attachment folder when it is a safe vault-relative path, otherwise in the vault root.
- The editor inserts a Markdown embed pointing at the vault-relative attachment path.
- Plain text paste is left to the native text editor.

Read-only preview rendering lives in `RichMarkdownView`; the main editor surface uses `RichMarkdownEditorView` and `MarkdownEditorTextRenderer`.

- The editable editor intentionally keeps the raw Markdown string as the text storage string.
- Markdown styling is applied as attributes only. Task checkbox hit testing marks the `[ ]` / `[x]` range with an attribute, but does not replace it with an attachment.
- Rendered image/video embeds belong to the read-only preview path. The editable surface keeps embed Markdown as normal text to avoid cursor and source-offset drift.
- Markdown text is rendered through `swift-markdown-ui`.
- Embed lines such as `![Title](path-or-url)` are rendered as images or videos when their extension is supported.
- Local relative paths are resolved through `VaultStore.url(forMarkdownLink:)` and `VaultStore.url(forWikiLink:)`, with vault-bound path validation.

## Testing

`ObsidianSideNoteTests/` covers:

- Empty New Note protection.
- Markdown file creation.
- Vault search filtering.
- Vault file writes.
- Obsidian Daily Note URI construction.
- Shortcut storage and hotkey mapping.
- New Note resume interval.
- Markdown media parsing.
- Media attachment type detection.
- Relative vault media URL resolution.
- Vault-relative path traversal rejection for Markdown links and Obsidian-configured folders.
- Remote media byte-limit and content-type checks.
- Rich Markdown editor rendering, command application, task-list toggling, smart list editing, and media preload behavior.

Run:

```bash
xcodebuild test \
  -project ObsidianSideNote.xcodeproj \
  -scheme ObsidianSideNote \
  -destination 'platform=macOS' \
  -only-testing:ObsidianSideNoteTests
```

## Design Principles

- Keep UI state in SwiftUI views.
- Keep file-system and UserDefaults access in stores.
- Keep Obsidian URI construction out of views.
- Prefer small, testable helpers over broad manager objects.
- Avoid creating empty Markdown files.
- Preserve Obsidian compatibility by writing normal Markdown files into the vault.
- Treat Obsidian-configured folders and Markdown links as vault-relative paths; reject path traversal instead of following paths outside the selected vault.
