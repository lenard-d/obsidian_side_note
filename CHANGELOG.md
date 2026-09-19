# Changelog

## 2.6 - 2026-09-20

### Changed

- Added `Command+L` to focus and select vault search while editing a vault file.
- Made Return and Tab open the selected search result and move focus to the end of the editor.
- Store indentation as real tab characters and display each tab at four spaces wide.
- Fixed stale cursor artifacts after indenting and deleting on empty lines.
- Fixed rare cursor rollbacks when autosave confirms a local edit.
- Made `Command+Left` and `Command+Right` reveal and reach the Markdown source boundaries without skipping list prefixes.

### Developer

- Added focused editor tests for tab handling, cursor drawing, source-boundary navigation, and local autosave confirmation.
- Added search focus and file-selection tests for the vault editor.

## 2.5 - 2026-09-15

### Changed

- Added live blockquote presentation with a left rule while keeping the Markdown source editable.
- Kept `Shift+Enter` inside list items and blockquotes without creating a new list item or leaving the quote.
- Aligned list continuation text with the first line for bullets, numbered lists, and task lists.
- Fixed dragging inactive note windows from the empty header area.

### Developer

- Added WebKit layout tests for blockquotes and structural line breaks.
- Added a UI test for dragging an inactive window from its empty header area.

## 2.4 - 2026-09-13

### Changed

- Rank exact filenames before partial and approximate file matches. Accept apostrophe variants, accents, extra spaces, and an optional `.md` extension.
- Improve word and abbreviation matching, and accept one typo in a query word of at least four characters.
- Show folders first, with separate sections for exact matches, direct files, and files in subfolders. File rows show titles only.
- Enter matching folders instead of opening folder notes with the same name. Add `.md` to select the note explicitly.
- Use Cmd+Down and Cmd+Up to move between result sections. Escape dismisses suggestions before closing the window.
- Run indexing and matching in background tasks, reject stale results, and remove the silent 80-result cutoff.
- Keep the active note and its save target while browsing search results.

### Developer

- Add focused tests for ranking, Unicode names, folder-note navigation, query cancellation, and index refresh.
- Verify folder navigation, section shortcuts, filename searches, and file opening through the native UI.

## 2.3 - 2026-09-13

### Changed

- Fixed macOS text replacements in the editor. Shortcuts expand after a space, punctuation mark, or Enter.
- Reload text replacements when the editor receives focus.
- Added support for Periodic Notes daily note names.
- Stabilized list marker positions and cursor movement between source and preview text.

### Developer

- Made UI tests check visible input and saved Markdown after opening linked notes.
- Added UI coverage for text replacements through the app's normal editor interface.

## 2.2 - 2026-08-20

Obsidian Side Note 2.2 stabilizes live-preview editing, adds linked-note previews, and hardens vault and media handling.

### Changed

- Added hover previews for wiki and Markdown links in nonactivating, read-only floating windows, including nested previews and a configurable delay.
- Made live-preview links clickable while preserving editor focus and source positions.
- Added source-preserving live presentation for bold, italic, highlight, inline code, headings, task checkboxes, bullets, and inline images.
- Removed the horizontal layout shift when a bullet changes between preview and raw Markdown, and aligned bullet dots precisely between the text baseline and cap height.
- Hardened pasted, dropped, and remotely downloaded media with typed failures, content-type validation, download limits, and privacy-safe diagnostics.
- Centralized vault path validation, selection persistence, media lookup, image caching, and settings restoration behind smaller focused stores.
- Prevented unsafe vault-relative paths and symlink escapes from resolving outside the selected vault.
- Made launch-at-login persistence reflect only system changes accepted by macOS.

### Developer

- Split the CodeMirror theme and test adapter from the editor transaction logic and added deterministic WebKit layout coverage.
- Removed the obsolete STTextView, MarkdownUI, and native Markdown-renderer paths now replaced by CodeMirror.
- Added structured logging with bounded diagnostics and quiet XCTest defaults.
- Split the monolithic test suite by editor, window, vault, configuration, media, login-item, and logging responsibilities.

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
