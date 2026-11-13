#!/bin/zsh
# Builds WatchDeck and packages it for a GitHub release:
#   build/release/WatchDeck.dmg  – open it and drag the app onto Applications
#   build/release/WatchDeck.zip  – used by install.sh
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
OUT=build/release
STAGE=build/obj/dmg
rm -rf "$OUT" "$STAGE" && mkdir -p "$OUT" "$STAGE"

ditto -c -k --sequesterRsrc --keepParent "build/WatchDeck.app" "$OUT/WatchDeck.zip"

ditto "build/WatchDeck.app" "$STAGE/WatchDeck.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "WatchDeck" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT/WatchDeck.dmg"

(cd "$OUT" && shasum -a 256 WatchDeck.dmg WatchDeck.zip > SHA256SUMS.txt)
ls -lh "$OUT"
