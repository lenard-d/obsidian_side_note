# Obsidian Side Note

Obsidian Side Note is a lightweight macOS menu bar app for capturing and editing Markdown notes in an Obsidian vault without switching away from your current workspace.

The app opens a small floating editor, supports focused global keyboard shortcuts for note workflows, can append to the Obsidian daily note, creates local Markdown files with autosave, and can search and edit existing vault files directly.

> Attribution: this project is based on the original Obsidian Side Note app by Luke Smith. Original repository: [lukesmith96/obsidian_side_note](https://github.com/lukesmith96/obsidian_side_note).

## Table of Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [Requirements](#requirements)
- [Installation](#installation)
- [First Setup](#first-setup)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Development](#development)
- [Documentation](#documentation)
- [Roadmap](#roadmap)
- [Acknowledgments](#acknowledgments)

## Features

- Menu bar app: stays out of the Dock and is always available from the macOS menu bar.
- Floating editor window: movable, compact, and visible above normal windows.
- Global keyboard shortcuts: Append, New Note, and Edit Vault File work even while another app is active.
- Local app shortcuts: Settings and Quit stay local so they do not steal commands from apps such as Codex.
- Shortcut recorder: click a shortcut in Settings, press a key combination, and the app stores it.
- Vault folder picker: select the Obsidian vault from Finder instead of typing its name manually.
- Append to Daily Note: sends content to Obsidian's daily note endpoint silently.
- New Note editor: autosaves Markdown files into the selected vault once body content exists.
- Empty-file protection: a note title without body content is stored only as local draft state.
- Draft recovery: closing the editor does not discard unfinished text.
- Resume interval: choose whether reopening New Note within 1, 3, 5, 10, or 15 minutes should keep the current draft.
- Force new note shortcut: the New Note shortcut starts a fresh draft even if another draft is visible.
- Vault file search: live suggestions search Markdown files by title or relative path.
- Keyboard navigation: use arrow keys plus Tab or Return to pick search suggestions.
- Autosave editing: selected vault files save on each editor change.
- Markdown editing toolbar: bold, italic, strikethrough, links, lists, numbered lists, and tasks.
- Markdown preview: render Markdown before or while editing.
- Media embeds: render Markdown image/video embeds such as `![Title](url-or-relative-path)`.
- Paste media: pasted images and supported media files are copied into `Attachments/` and inserted as Markdown embeds.

## Screenshots

<p align="center">
  <img src="screenshots/full_view_edit.png" alt="Editor window" width="1012">
</p>
<p align="center">
  <img src="screenshots/menu_bar.png" alt="Menu bar" width="256">
  <img src="screenshots/full_view_markdown.png" alt="Markdown preview" height="256">
  <img src="screenshots/settings.png" alt="Settings" height="256">
</p>

## Logo Concepts

Four simple logo directions are available in [docs/assets/logo-concepts.png](docs/assets/logo-concepts.png). They are exploration assets only; the current app icon has not been replaced yet.

## Requirements

- macOS with Xcode support for the current project target.
- Xcode 26 or newer is recommended because the project currently targets `MACOSX_DEPLOYMENT_TARGET = 26.0`.
- Obsidian installed if you want Daily Note append and "Open in Obsidian" behavior.
- An existing local Obsidian vault folder.

The app uses SwiftUI, AppKit, Carbon global hotkeys, AVKit for video preview, and [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) for Markdown rendering.

## Installation

There is not yet a packaged release installer in this repository. For now, build the app locally and copy the generated app bundle into `/Applications`.

See [docs/INSTALLATION.md](docs/INSTALLATION.md) for detailed build, install, and Login Items instructions.

Quick local build:

```bash
xcodebuild \
  -project ObsidianSideNote.xcodeproj \
  -scheme ObsidianSideNote \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build
```

Then copy the app:

```bash
cp -R build/DerivedData/Build/Products/Release/ObsidianSideNote.app /Applications/
open /Applications/ObsidianSideNote.app
```

To keep the app available after restarting your Mac, add it to Login Items:

1. Open System Settings.
2. Go to General -> Login Items.
3. Add `/Applications/ObsidianSideNote.app`.
4. Keep Obsidian installed and allow any macOS permissions requested on first launch.

## First Setup

1. Launch `ObsidianSideNote.app`.
2. Click the note icon in the macOS menu bar.
3. Choose `Settings`.
4. Click `Choose...`.
5. Select your local Obsidian vault folder.
6. Adjust keyboard shortcuts if needed.
7. Choose the New Note resume interval.

The selected vault folder is stored with a security-scoped bookmark so the sandboxed app can keep read/write access across launches.

## Usage

### Menu Actions

- `Append to Daily Note`: open a scratch editor and send text to Obsidian's daily note endpoint.
- `Create New Note`: open the Quick Note editor for a new Markdown file.
- `Edit Vault File`: search existing Markdown files and edit the selected file.
- `Settings`: choose the vault folder, configure shortcuts, and set the resume interval.

### Default Shortcuts

- `Command-D`: Append to Daily Note.
- `Command-N`: Create New Note.
- `Command-E`: Edit Vault File.
- `Command-,`: Settings.
- `Command-Q`: Quit.

Shortcuts can be changed in Settings. Click the shortcut value on the right side of a row, then press the full key combination you want to use.

Only Append to Daily Note, Create New Note, and Edit Vault File are registered globally. Settings is local-only and is handled only while Obsidian Side Note is active. Quit remains local to the app as well.

### New Notes

New notes autosave directly into the selected vault.

The title field is stored locally as a draft until the body has content. If you type only a title and close the window, no empty Markdown file is created. Once the body contains text, the app creates a Markdown file using the title or a timestamp fallback.

If the New Note window is already open and you choose `Create New Note` from the menu within the configured resume interval, the current draft stays visible. Using the New Note shortcut forces a fresh draft.

### Editing Existing Vault Files

1. Choose `Edit Vault File`.
2. Type part of a title or vault-relative path.
3. Pick a suggestion by clicking it, using arrow keys, or pressing Tab/Return.
4. Edit the Markdown in the editor.

Changes autosave to the selected file. The open button next to the search field opens the selected note in Obsidian.

### Media

Markdown embeds are rendered in preview mode:

```markdown
![Diagram](Attachments/diagram.png)
![Remote image](https://example.com/image.png)
![Demo video](Attachments/demo.mp4)
```

Pasted images and supported media files are copied into an `Attachments/` folder inside the selected vault and inserted as Markdown embeds.

Supported preview formats:

- Images: `apng`, `avif`, `gif`, `jpeg`, `jpg`, `png`, `svg`, `webp`
- Videos: `m4v`, `mov`, `mp4`

## Project Structure

```text
ObsidianSideNote/
  Models/       Small domain types such as note modes, shortcuts, and vault notes.
  Services/     Integrations and service-style objects such as global hotkeys and Obsidian URIs.
  Stores/       UserDefaults-backed preferences and vault file-system access.
  Support/      AppKit/SwiftUI glue for windows, menu items, notifications, and shared views.
  Views/        SwiftUI views for settings, editor chrome, Markdown editing, and media preview.
  ContentView.swift
  ObsidianSideNoteApp.swift

ObsidianSideNoteTests/
  Unit tests for vault storage, shortcuts, URIs, preferences, and media parsing.
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a more detailed explanation of responsibilities and data flow.

## Development

Open the project:

```bash
open ObsidianSideNote.xcodeproj
```

Run tests:

```bash
xcodebuild test \
  -project ObsidianSideNote.xcodeproj \
  -scheme ObsidianSideNote \
  -destination 'platform=macOS' \
  -only-testing:ObsidianSideNoteTests
```

Run static analysis:

```bash
xcodebuild analyze \
  -project ObsidianSideNote.xcodeproj \
  -scheme ObsidianSideNote \
  -destination 'platform=macOS'
```

Check whitespace before committing:

```bash
git diff --check
```

## Documentation

- [Installation and permanent setup](docs/INSTALLATION.md)
- [Architecture and code layout](docs/ARCHITECTURE.md)

## Roadmap

- [ ] Signed and notarized release artifact.
- [ ] Built-in launch-at-login toggle.
- [ ] Window size preferences.
- [ ] Multiple vault support.
- [ ] Note templates.
- [ ] Custom attachment folder preference.
- [x] Custom global shortcuts.
- [x] Local vault folder selection.
- [x] Local vault search.
- [x] Autosave editing.
- [x] Media rendering and paste support.

## Contributing

Contributions are welcome. Please keep changes small, tested, and consistent with the existing SwiftUI/AppKit split.

1. Fork the repository.
2. Create a feature branch.
3. Run tests and static analysis.
4. Open a pull request with a clear description of the user-facing behavior.

## Acknowledgments

- Original app and repository by Luke Smith: [lukesmith96/obsidian_side_note](https://github.com/lukesmith96/obsidian_side_note)
- Markdown rendering via [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui)
- Obsidian integration via local Markdown files and [Obsidian URI](https://help.obsidian.md/uri)
