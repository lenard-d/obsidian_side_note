# Installation and Permanent Setup

This document explains how to install Obsidian Side Note from a release build, build it locally, install it into `/Applications`, and keep it active after restarting macOS.

## Current Status

Release builds are published on GitHub as zipped app bundles. They may not be notarized yet, so macOS can require an explicit first launch approval.

The reliable local build path is:

1. Build the bundled CodeMirror editor with npm.
2. Build a Release app bundle with Xcode.
3. Copy `ObsidianSideNote.app` into `/Applications`.
4. Add the app to macOS Login Items if you want it to start after login.
5. Select your Obsidian vault in the app Settings.

## Install a Release Build

1. Download `ObsidianSideNote-2.2.zip` from GitHub Releases.
2. Unzip it.
3. Move `ObsidianSideNote.app` into `/Applications`.
4. Open the app.

If macOS blocks the first launch, open Finder, go to `/Applications`, Control-click `ObsidianSideNote.app`, choose `Open`, and confirm the security dialog.

If needed, remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/ObsidianSideNote.app
open /Applications/ObsidianSideNote.app
```

## Build a Release App

From the repository root:

```bash
script/build_and_run.sh build
```

The built app will be here:

```text
/Applications/ObsidianSideNote.app
```

`script/build_and_run.sh` installs npm dependencies when needed, builds `EditorWeb/src/editor.js` into the bundled `ObsidianSideNote/MarkdownEditor/editor.js`, builds the Xcode Release app, and copies it into `/Applications`.

## Install Into Applications

Copy the app bundle:

```bash
script/build_and_run.sh build
```

Start it:

```bash
open /Applications/ObsidianSideNote.app
```

If macOS blocks the app because it was built locally, open it from Finder with Control-click -> Open, or approve it in System Settings -> Privacy & Security.

## Keep the App Running After Restart

Add the installed app as a Login Item:

1. Open System Settings.
2. Go to General -> Login Items.
3. Click `+`.
4. Select `/Applications/ObsidianSideNote.app`.

After the next login, macOS launches the menu bar app automatically. The app runs as an accessory app, so it appears in the menu bar instead of the Dock.

## First Launch Checklist

1. Open the app.
2. Click the menu bar icon.
3. Choose `Settings`.
4. Click `Choose...` and select your Obsidian vault folder.
5. Confirm or change the shortcuts.
6. Choose the New Note resume interval.

## Permissions

The app stores the selected vault path in app configuration. Selecting the vault once in Settings grants the app the path it needs for local Markdown reads and writes.

Daily Note append uses Obsidian's URI endpoint. Obsidian's Daily Notes core plugin must be enabled for template-aware daily note creation.

Global keyboard shortcuts are registered through macOS hotkey APIs for Append to Daily Note, Create New Note, and Edit Vault File. Their defaults are `Control` + `Option` + `Command` + `D`, `N`, and `V` to avoid normal app shortcuts.

Settings and Quit are local-only so they do not override shortcuts in the app you are currently using. The shortcut recorder rejects Command-only global shortcuts for the same reason.

If a global shortcut does not fire, check whether another app already owns the same key combination and choose a different shortcut in Settings.

## Updating the App

To update a local install:

```bash
script/build_and_run.sh run
```

## Future Release Packaging

The next packaging step should be a signed and notarized release build. A polished release flow would add:

- Developer ID signing.
- Notarization.
- A downloadable `.dmg` or `.zip`.
