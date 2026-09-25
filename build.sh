#!/bin/zsh
# Builds PinDock.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"

APP=PinDock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun --sdk macosx swiftc -O -target "$(uname -m)-apple-macos14.0" main.swift -module-name PinDock -o "$APP/Contents/MacOS/PinDock"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PinDock</string>
  <key>CFBundleDisplayName</key><string>PinDock</string>
  <key>CFBundleIdentifier</key><string>com.local.pindock</string>
  <key>CFBundleExecutable</key><string>PinDock</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
