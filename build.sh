#!/bin/zsh
# Builds Q-Dock.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"

APP=Q-Dock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun --sdk macosx swiftc -O -target "$(uname -m)-apple-macos14.0" main.swift -module-name QDock -o "$APP/Contents/MacOS/Q-Dock"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Q-Dock</string>
  <key>CFBundleDisplayName</key><string>Q-Dock</string>
  <key>CFBundleIdentifier</key><string>com.local.qdock</string>
  <key>CFBundleExecutable</key><string>Q-Dock</string>
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
