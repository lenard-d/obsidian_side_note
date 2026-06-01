# Architecture

Obsidian Side Note is a small SwiftUI/AppKit macOS app. The architecture is intentionally simple: SwiftUI owns the UI, AppKit handles menu-bar and window behavior, and small store/service types isolate persistence, file-system work, hotkeys, and Obsidian URI construction.

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
        +--> RichMarkdownView
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

Store types are static because the app currently has a single active vault and a single editor window.

## Services

`Services/` contains integrations that are not UI views:

- `GlobalHotKeyManager`: registers configured note-workflow shortcuts as global Carbon hotkeys.
- `ObsidianURIBuilder`: builds Obsidian URIs for Daily Note append and opening files in Obsidian.

The app edits local Markdown files directly where possible. Obsidian URI is reserved for workflows that need Obsidian itself, such as appending to the daily note or opening a selected note.

Only Append to Daily Note, Create New Note, and Edit Vault File are global. Settings and Quit are intentionally local to avoid stealing standard shortcuts from the foreground app.

The global shortcut layer deliberately follows the pattern used by established launcher/menu-bar apps: globally trigger only explicit workflow commands, keep app-management commands local, store user choices in `UserDefaults`, and reject Command-only global shortcuts because they commonly collide with foreground-app menu commands.

## Views

`Views/` contains SwiftUI surfaces:

- `SettingsView`: vault picker, New Note interval, and shortcut rows.
- `KeyboardShortcutRow`: shortcut recorder UI.
- `MarkdownEditorView`: toolbar, text editor, preview toggle, and paste handling.
- `RichMarkdownView`: Markdown rendering plus line-level image/video embed rendering.
- `NoteEditorChrome`: shared header, search panel, missing-vault prompt, and append action bar.

`ContentView.swift` composes these views and owns the active editor state for the current mode.

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

1. The editor keeps a draft locally.
2. The append action first sends `obsidian://daily` with `silent` and no content. Obsidian creates the daily note through its Daily Notes plugin if it is missing, which preserves the configured folder, date format, and template.
3. The app then sends content to `obsidian://daily` with `append` and `silent`.
4. The daily note is not opened as part of the append action.

## Media Handling

Paste and drag-and-drop handling live in `MarkdownEditorView` and are normalized by `MediaAttachmentImporter`.

- Pasted images are converted to PNG.
- Pasted and dropped media files are copied as-is when supported.
- Files are stored in `Attachments/` inside the selected vault.
- The editor inserts a Markdown embed pointing at the vault-relative attachment path.
- Plain text paste is left to the native text editor.

Preview rendering lives in `RichMarkdownView`.

- Markdown text is rendered through `swift-markdown-ui`.
- Embed lines such as `![Title](path-or-url)` are rendered as images or videos when their extension is supported.
- Local relative paths are resolved through `VaultStore.url(forMarkdownLink:)`.

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
