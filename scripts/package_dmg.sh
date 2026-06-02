#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/ObsidianSideNote.xcodeproj"
SCHEME="ObsidianSideNote"
CONFIGURATION="Release"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/build/dmg-root"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/ObsidianSideNote.app"
DMG_PATH="$DIST_DIR/ObsidianSideNote.dmg"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  build

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

codesign --force --deep --sign - "$STAGING_DIR/ObsidianSideNote.app"

hdiutil create \
  -volname "ObsidianSideNote" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
