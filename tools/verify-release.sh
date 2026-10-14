#!/bin/zsh
# Checks that a Q-Dock.zip is fit to publish: signed with HQE Systems' Developer ID, notarized, stapled, and
# accepted by Gatekeeper the way a downloaded copy would be. A zip of a build.sh build fails here, because build.sh
# signs with the self-signed "Q-Dock Local Signing" certificate (or ad-hoc), which macOS blocks as "could not be
# verified" on every other Mac.
#
#   tools/verify-release.sh Q-Dock.zip   # a local zip (release.sh runs this on the zip it makes)
#   tools/verify-release.sh v1.3.1       # the Q-Dock.zip attached to that GitHub release
set -euo pipefail

TEAM=JPKJW4C8V6
ARG=${1:-Q-Dock.zip}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ -f "$ARG" ]; then
  cp "$ARG" "$WORK/Q-Dock.zip"
else
  gh release download "$ARG" --repo cyber-qais/qais-mac-dock --pattern Q-Dock.zip --dir "$WORK"
fi
# Mark it as downloaded so Gatekeeper judges it exactly as it would on a user's Mac.
xattr -w com.apple.quarantine "0083;$(printf %x $(date +%s));Safari;" "$WORK/Q-Dock.zip"
ditto -x -k "$WORK/Q-Dock.zip" "$WORK/x"
APP="$WORK/x/Q-Dock.app"

fail() { echo "NOT RELEASABLE: $1" >&2; echo "Build releases with ./release.sh, never ./build.sh." >&2; exit 1; }

[ -d "$APP" ] || fail "the zip doesn't contain Q-Dock.app at its top level."
INFO=$(codesign -dvv "$APP" 2>&1) || fail "Q-Dock.app isn't signed."
print -r -- "$INFO" | grep -q "^TeamIdentifier=$TEAM\$" \
  || fail "signed by '$(print -r -- "$INFO" | awk -F= '/^Authority=/ {print $2; exit}')', not the Developer ID of team $TEAM."
xcrun stapler validate "$APP" >/dev/null 2>&1 || fail "no notarization ticket is stapled."
spctl --assess --type execute "$APP" 2>/dev/null || fail "Gatekeeper rejects it ($(spctl --assess --type execute -vv "$APP" 2>&1 | tail -1))."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
echo "OK: Q-Dock $VERSION is Developer ID signed ($TEAM), notarized, stapled and accepted by Gatekeeper."
