# Changelog

## 2.0 - 2026-06-14

Obsidian Side Note 2.0 is the editor and vault-workflow release.

### Changed

- Replaced the production Markdown editing surface with a bundled CodeMirror 6 editor inside `WKWebView`.
- Kept Markdown source as the editable document while rendering task checkboxes, bullet markers, and heading hierarchy inline.
- Improved list editing: `Tab` indents list items, `Command-Shift-Tab` outdents, and empty nested list items outdent with Backspace/Delete.
- Added active-note file monitoring so edits made in Obsidian are reloaded before the next Side Note autosave.
- Made Edit Vault File search return all matches and render suggestions as a scrollable overlay instead of shrinking the editor layout.
- Preserved New Note drafts across close/reopen within the configured resume interval unless the global New Note shortcut explicitly starts a fresh note.
- Kept the floating app out of the Dock and app switcher after opening note windows.
- Moved Settings to a local app shortcut so command-only shortcuts are not registered globally.
- Restored legacy app settings and vault selections after app replacements and sandbox-to-non-sandbox config moves.

### Developer

- Added `EditorWeb/` as the source package for the generated bundled editor script.
- Updated `script/build_and_run.sh` to build the web editor, build the Release app, install it into `/Applications`, verify signing, and open the installed app.
- Expanded unit and WebKit regression coverage for search, draft restore, active-file sync, editor rendering, and list key handling.

## 1.1.7 - 2026-06-01

Last published 1.x release.
