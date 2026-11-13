#!/bin/zsh
# Builds a native Apple Silicon "WatchDeck.app" into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP="build/WatchDeck.app"
rm -rf build && mkdir -p build/obj "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos13.0 \
  -framework AppKit -framework SwiftUI -framework Charts -framework MapKit -framework CoreLocation -framework CoreBluetooth -framework IOBluetooth \
  Sources/*.swift -o build/obj/WatchDeck
cp build/obj/WatchDeck "$APP/Contents/MacOS/WatchDeck"

# App icon: drawn by Icon/make_icon.swift, packed into AppIcon.icns.
swiftc -O Icon/make_icon.swift -o build/obj/make_icon
build/obj/make_icon build/obj/icons "${ICON_STYLE:-glass}"
ICONSET=build/obj/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  cp "build/obj/icons/icon_$s.png" "$ICONSET/icon_${s}x${s}.png"
  cp "build/obj/icons/icon_$((s * 2)).png" "$ICONSET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>WatchDeck</string>
  <key>CFBundleIdentifier</key><string>com.lemonspitz.watchdeck</string>
  <key>CFBundleName</key><string>WatchDeck</string>
  <key>CFBundleDisplayName</key><string>WatchDeck</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSHumanReadableCopyright</key><string>Made by @lemonspitz · protocol knowledge from the Gadgetbridge project</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSLocationUsageDescription</key><string>WatchDeck sends this Mac's approximate location to your watch so its GPS locks faster. It is not sent anywhere else.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>WatchDeck sends this Mac's approximate location to your watch so its GPS locks faster. It is not sent anywhere else.</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>WatchDeck uses Bluetooth to connect to and control your Huawei watch or band.</string>
</dict>
</plist>
PLIST

# Watch-face generator: build/facemaker <output folder> [screen code or WxH] [design number]
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 FaceMaker/*.swift -o build/facemaker
cp build/facemaker "$APP/Contents/MacOS/facemaker"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
