#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ObsidianSideNote"
BUNDLE_ID="live.lukesmith.ObsidianSideNote"
PROJECT="ObsidianSideNote.xcodeproj"
SCHEME="ObsidianSideNote"
CONFIGURATION="Release"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/RunDerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
INSTALL_BUNDLE="/Applications/$APP_NAME.app"
INSTALL_BINARY="$INSTALL_BUNDLE/Contents/MacOS/$APP_NAME"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if [[ -f "$ROOT_DIR/EditorWeb/package.json" ]]; then
  if [[ ! -d "$ROOT_DIR/EditorWeb/node_modules" ]]; then
    npm --prefix "$ROOT_DIR/EditorWeb" install
  fi
  npm --prefix "$ROOT_DIR/EditorWeb" run build
fi

xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA"

rm -rf "$INSTALL_BUNDLE"
/usr/bin/ditto "$APP_BUNDLE" "$INSTALL_BUNDLE"

open_app() {
  /usr/bin/open -n "$INSTALL_BUNDLE"
}

case "$MODE" in
  build|--build)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$INSTALL_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    /usr/bin/codesign --verify --deep --strict "$INSTALL_BUNDLE"
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [build|run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
