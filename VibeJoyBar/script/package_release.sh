#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
mkdir -p "$DIST_DIR"
APP_SOURCE="/Applications/VibeJoyBar.app"
if [[ ! -d "$APP_SOURCE" ]]; then
  APP_SOURCE="$REPO_ROOT/VibeJoyBar/dist/VibeJoyBar.app"
fi
echo "Packaging $APP_SOURCE -> $DIST_DIR/VibeJoyBar-macOS.zip..."
(cd "$(dirname "$APP_SOURCE")" && /usr/bin/ditto -c -k --keepParent "$(basename "$APP_SOURCE")" "$DIST_DIR/VibeJoyBar-macOS.zip")
echo "Release package created: $DIST_DIR/VibeJoyBar-macOS.zip ($(du -h "$DIST_DIR/VibeJoyBar-macOS.zip" | cut -f1))"
