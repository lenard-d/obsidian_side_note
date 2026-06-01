# Installation and Permanent Setup

This document explains how to build Obsidian Side Note locally, install it into `/Applications`, and keep it active after restarting macOS.

## Current Status

The repository does not yet contain a signed release artifact or installer. The reliable path today is:

1. Build a Release app bundle with Xcode.
2. Copy `ObsidianSideNote.app` into `/Applications`.
3. Add the app to macOS Login Items.
4. Select your Obsidian vault in the app Settings.

## Build a Release App

From the repository root:

```bash
xcodebuild \
  -project ObsidianSideNote.xcodeproj \
  -scheme ObsidianSideNote \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build
```

The built app will be here:

```text
build/DerivedData/Build/Products/Release/ObsidianSideNote.app
```

## Install Into Applications

Copy the app bundle:

```bash
cp -R build/DerivedData/Build/Products/Release/ObsidianSideNote.app /Applications/
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

The app is sandboxed and uses a security-scoped bookmark for the selected vault folder. Selecting the vault once in Settings grants persistent read/write access to that folder.

Global keyboard shortcuts are registered through macOS hotkey APIs for Append to Daily Note, Create New Note, and Edit Vault File. Settings and Quit are local-only so they do not override shortcuts in the app you are currently using.

If a global shortcut does not fire, check whether another app already owns the same key combination and choose a different shortcut in Settings.

## Updating the App

To update a local install:

```bash
xcodebuild \
  -project ObsidianSideNote.xcodeproj \
  -scheme ObsidianSideNote \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build

rm -rf /Applications/ObsidianSideNote.app
cp -R build/DerivedData/Build/Products/Release/ObsidianSideNote.app /Applications/
open /Applications/ObsidianSideNote.app
```

## Future Release Packaging

The next packaging step should be a signed and notarized release build. A polished release flow would add:

- Developer ID signing.
- Notarization.
- A downloadable `.dmg` or `.zip`.
- A built-in Launch at Login toggle.
