# Vault search

The popup searches Markdown filenames and relative paths. It does not read note bodies.

## Matching

Files use fixed match levels, in this order:

1. Exact relative path or exact title.
2. Title starts with the query.
3. Title contains the query.
4. All query words occur in the title, in any order.
5. Abbreviations in the title. Adjacent characters and word starts get higher scores.
6. Matches that need the folder path.
7. One typo in one query word of at least four characters.

Typo matching accepts one insertion, deletion, substitution, or adjacent transposition. It does not turn short unrelated words into matches. Exact matches cannot lose to accumulated fuzzy scores.

Matching ignores case, accents, straight versus curved apostrophes, repeated whitespace, and an optional `.md` suffix. Hyphens and underscores act as word separators. The result retains the real filename and URL.

## Folder navigation and results

- Folders stay above files and show a folder icon and name only.
- Enter, Tab, or a click on a folder fills the search field with its relative path and `/`.
- A trailing slash always means folder browsing. Missing folders return no results.
- Browsing lists direct child folders. It separates direct files and files in deeper folders.
- An exact file match gets an `exact matches` section before other files, including when it is in a deeper folder.
- An exact folder name selects the folder, even when a folder note has the same name. Adding `.md` selects the file instead. Other name searches select the best file. Folder browsing starts at the first row.
- There is no silent 80-result cutoff. Section counts show the number of matches.
- File rows show titles only. Duplicate titles can still look identical. Full path labels remain excluded by the product brief.

## Keyboard and search state

- Up and Down move one row. Cmd+Down and Cmd+Up move between sections without wrapping.
- Enter and Tab activate the selected result. If a search is still running, activation waits for that query's results.
- Escape dismisses suggestions first. It does not close the note window on that first press.
- Search keys only apply while the search field has focus.
- A new query selects its best result. Old background searches cannot replace newer results.
- Browsing does not clear the active note or change its save target.

Indexing and matching run off the UI thread. Queries use a short 25 ms debounce. The prepared index caches normalized names and paths. The index refreshes when search receives focus, after app file writes, or when its 30-second cache expires on a later lookup.

## Open source comparison and implementation decisions

This is an improvement of an existing SwiftUI/AppKit popup. The sources below informed the behavior; their code was not copied.

| Source or component | Useful behavior | Integration choice |
| --- | --- | --- |
| [VS Code fuzzy scorer](https://github.com/microsoft/vscode/blob/main/src/vs/base/common/fuzzyScorer.ts) | Separate name and path scoring; prefer full paths, prefixes, word boundaries, and compact matches | Apply those principles in Swift. A TypeScript runtime would add unnecessary integration work. |
| [Helix pickers](https://docs.helix-editor.com/master/pickers.html) | Separate searching from navigating a directory | Keep the native popup and use a trailing slash for explicit folder browsing. |
| [fzf](https://github.com/junegunn/fzf) | Responsive fuzzy selection for large candidate lists | No subprocess dependency. The app needs native sections, note selection, and focus handling. |
| Existing SwiftUI controls | Native scrolling, text input, buttons, accessibility | Reuse these controls and the original popup background. |

## UI improvement list

| Area | Decision | Benefit | Effort | State |
| --- | --- | --- | --- | --- |
| `VaultNoteSearch` | Modernize internal matching with fixed levels and prepared candidates | Reliable exact names, tolerant spelling, useful abbreviations | Medium | Implemented |
| `VaultSearchIndexStore` and `ContentViewModel` | Run scans and matching in background tasks | Keep typing responsive and reject stale query results | Medium | Implemented |
| `VaultSearchSuggestionsPopup` | Reuse native controls with typed sections | Separate folders, direct files, and deeper files | Small | Implemented |
| Search keyboard routing | Reuse AppKit events with focus checks and section boundaries | Predictable Enter, Escape, and Cmd+arrow behavior | Small | Implemented |

## Visual decisions

The common default would add badges, path subtitles, and a new command-palette skin. This popup instead uses a compact native list, small lowercase section labels, counts, folder icons, and thin separators. No new background, decorative cards, or scrolling animations were added. Long result lists and duplicate titles remain the main visual risks.
