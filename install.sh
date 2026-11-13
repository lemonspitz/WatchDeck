#!/bin/bash
# One-line installer for WatchDeck:
#   curl -fsSL https://raw.githubusercontent.com/lemonspitz/WatchDeck/main/install.sh | bash
set -euo pipefail

APP_NAME="WatchDeck.app"
URL="https://github.com/lemonspitz/WatchDeck/releases/latest/download/WatchDeck.zip"

if [ "$(uname -m)" != "arm64" ]; then
  echo "WatchDeck needs an Apple Silicon Mac (M1 or later)." >&2
  exit 1
fi

DEST="/Applications"
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading WatchDeck…"
curl -fsSL "$URL" -o "$TMP/WatchDeck.zip"
ditto -x -k "$TMP/WatchDeck.zip" "$TMP"

pkill -x WatchDeck 2>/dev/null || true
rm -rf "$DEST/$APP_NAME"
ditto "$TMP/$APP_NAME" "$DEST/$APP_NAME"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

echo "Installed to $DEST/$APP_NAME. Open it, then connect your watch on the Device page."
open "$DEST/$APP_NAME"
