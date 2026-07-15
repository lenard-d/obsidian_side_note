# Changelog

## 2.1 - 2026-07-15

Obsidian Side Note 2.1 improves vault search, pasted image handling, and New Note resume behavior.

### Changed

- Added concurrent floating editor windows: each New Note or Edit Vault File action now opens a separate, cascaded window.
- Fixed Markdown toolbar commands, macOS text replacements, hanging list indentation, centered bullets, and deterministic list continuation/exit behavior.
- Expanded the draggable title area through the complete top edge of note windows.
- Added fuzzy ranked vault search for abbreviations and partial title/path matches.
- Scoped slash-prefixed Edit Vault File searches to the typed directory subtree while keeping root searches global across subfolders.
- Limited Edit Vault File suggestions to the top ranked results so large vaults render the popup lazily.
- Displayed pasted image embeds inline inside the CodeMirror editor while preserving the underlying Markdown source.
- Made the New Note shortcut resume the recent draft or created note within the configured interval, matching the menu action.
- Refreshed the New Note resume interval on draft activity and close, so a recently closed note reopens instead of being replaced by a new draft.

### Developer

- Added focused regression coverage for fuzzy search, directory-scoped search, limited suggestions, media embed rendering, and New Note session refresh.
- Split vault search ranking into a dedicated `VaultNoteSearch` helper.

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
