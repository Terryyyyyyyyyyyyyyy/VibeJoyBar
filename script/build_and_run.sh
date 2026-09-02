#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="VibeJoyBar"
BUNDLE_ID="com.terry.vibejoybar"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
RESOURCE_BUNDLE_NAME="VibeJoyBar_VibeJoyBar.bundle"
ICON_SOURCE="$ROOT_DIR/Sources/VibeJoyBar/Resources/AppIcon/AppIcon.icns"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"

# Ask only our own previously staged menu-bar app to quit.  Avoid a broad
# process-name kill, which could terminate an unrelated VibeJoyBar binary.
osascript -e 'tell application id "com.terry.vibejoybar" to quit' >/dev/null 2>&1 || true

swift build --package-path "$ROOT_DIR"
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --show-bin-path)/$APP_NAME"
BUILD_BIN_DIR="$(dirname "$BUILD_BINARY")"

# File Provider metadata can be reattached to bundles stored on Synology
# Drive while they are being signed. Assemble and strictly verify the app in
# a private local staging directory first, then copy that verified bundle to
# dist. The temporary path is deliberately narrow and always cleaned up.
STAGING_DIR="$(mktemp -d "/private/tmp/vibejoybar-package.XXXXXX")"
STAGED_APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
STAGED_APP_CONTENTS="$STAGED_APP_BUNDLE/Contents"
STAGED_APP_MACOS="$STAGED_APP_CONTENTS/MacOS"
STAGED_APP_RESOURCES="$STAGED_APP_CONTENTS/Resources"
STAGED_APP_BINARY="$STAGED_APP_MACOS/$APP_NAME"
STAGED_INFO_PLIST="$STAGED_APP_CONTENTS/Info.plist"

cleanup_staging() {
  rm -rf "$STAGING_DIR"
}
trap cleanup_staging EXIT INT TERM

if [[ "$APP_BUNDLE" != "$ROOT_DIR/dist/$APP_NAME.app" || "$STAGING_DIR" != /private/tmp/vibejoybar-package.* ]]; then
  echo "unexpected packaging path" >&2
  exit 2
fi

mkdir -p "$STAGED_APP_MACOS" "$STAGED_APP_RESOURCES"
cp "$BUILD_BINARY" "$STAGED_APP_BINARY"
chmod +x "$STAGED_APP_BINARY"
if [[ -d "$BUILD_BIN_DIR/$RESOURCE_BUNDLE_NAME" ]]; then
  cp -R "$BUILD_BIN_DIR/$RESOURCE_BUNDLE_NAME" "$STAGED_APP_RESOURCES/$RESOURCE_BUNDLE_NAME"
else
  echo "missing SwiftPM resource bundle: $BUILD_BIN_DIR/$RESOURCE_BUNDLE_NAME" >&2
  exit 1
fi
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$STAGED_APP_RESOURCES/AppIcon.icns"
else
  echo "missing app icon: $ICON_SOURCE" >&2
  exit 1
fi

plutil -create xml1 "$STAGED_INFO_PLIST"
plutil -insert CFBundleExecutable -string "$APP_NAME" "$STAGED_INFO_PLIST"
plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$STAGED_INFO_PLIST"
plutil -insert CFBundleName -string "$APP_NAME" "$STAGED_INFO_PLIST"
plutil -insert CFBundleDisplayName -string "VibeJoy Bar" "$STAGED_INFO_PLIST"
plutil -insert CFBundlePackageType -string "APPL" "$STAGED_INFO_PLIST"
plutil -insert CFBundleIconFile -string "AppIcon.icns" "$STAGED_INFO_PLIST"
plutil -insert CFBundleShortVersionString -string "0.5.3" "$STAGED_INFO_PLIST"
plutil -insert CFBundleVersion -string "1" "$STAGED_INFO_PLIST"
plutil -insert LSMinimumSystemVersion -string "$MIN_SYSTEM_VERSION" "$STAGED_INFO_PLIST"
plutil -insert LSUIElement -bool true "$STAGED_INFO_PLIST"
plutil -insert NSPrincipalClass -string "NSApplication" "$STAGED_INFO_PLIST"

# Strictly sign and verify only inside /private/tmp. This is the required
# trust boundary; a later dist verification may be affected by File Provider
# metadata, but this staged bundle must always pass before it is copied.
signed=false
for _attempt in 1 2 3 4 5; do
  xattr -cr "$STAGED_APP_BUNDLE"
  xattr -d com.apple.FinderInfo "$STAGED_APP_BUNDLE" >/dev/null 2>&1 || true
  if codesign --force --deep --sign - --requirements '=designated => identifier "com.terry.vibejoybar"' "$STAGED_APP_BUNDLE" >/dev/null 2>&1 \
      && codesign --verify --deep --strict "$STAGED_APP_BUNDLE" >/dev/null 2>&1; then
    signed=true
    break
  fi
  sleep 0.2
done
if [[ "$signed" != true ]]; then
  echo "failed to sign and verify staged app $STAGED_APP_BUNDLE" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
ditto "$STAGED_APP_BUNDLE" "$APP_BUNDLE"

# Copying back to Synology Drive can reattach top-level metadata. Clear and
# verify the final bundle with bounded retries, but retain the strict staged
# verification above as the authoritative signing check if metadata returns.
final_verified=false
for _attempt in 1 2 3 4 5; do
  xattr -cr "$APP_BUNDLE"
  xattr -d com.apple.FinderInfo "$APP_BUNDLE" >/dev/null 2>&1 || true
  if codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
    final_verified=true
    break
  fi
  sleep 0.2
done
if [[ "$final_verified" != true ]]; then
  echo "warning: final bundle metadata prevents strict verification; staged bundle was verified" >&2
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  build|--build)
    echo "Successfully packaged: $APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
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
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
