#!/bin/zsh
# Builds Q-Dock.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"

APP=Q-Dock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun --sdk macosx swift tools/make-icon.swift assets/icon.png "$APP/Contents/Resources/AppIcon.icns"
# Universal binary (Apple Silicon + Intel)
TMP=$(mktemp -d)
for arch in arm64 x86_64; do
  xcrun --sdk macosx swiftc -O -target "$arch-apple-macos14.0" main.swift -module-name QDock -o "$TMP/Q-Dock-$arch"
done
lipo -create "$TMP/Q-Dock-arm64" "$TMP/Q-Dock-x86_64" -output "$APP/Contents/MacOS/Q-Dock"
rm -rf "$TMP"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Q-Dock</string>
  <key>CFBundleDisplayName</key><string>Q-Dock</string>
  <key>CFBundleIdentifier</key><string>com.local.qdock</string>
  <key>CFBundleExecutable</key><string>Q-Dock</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2.0</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Q-Dock asks Finder to move desktop icons out from behind the dock when Dock Mode is on, and to empty the Trash when you ask it to.</string>
</dict>
</plist>
PLIST

# Sign with the local "Q-Dock Local Signing" certificate if it exists (see tools/make-signing-cert.sh),
# so macOS keeps permissions like Accessibility across rebuilds. Otherwise fall back to ad-hoc signing.
IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk '/"Q-Dock Local Signing"/ {print $2; exit}')
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "Signed with Q-Dock Local Signing ($IDENTITY)"
else
  codesign --force --sign - "$APP"
  echo "Signed ad-hoc (run tools/make-signing-cert.sh to keep permissions across rebuilds)"
fi
echo "Built $(pwd)/$APP"
