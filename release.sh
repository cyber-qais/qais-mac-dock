#!/bin/zsh
# Builds a release of Q-Dock that opens without Gatekeeper warnings: signs it with HQE Systems' Developer ID
# (hardened runtime), notarizes it with Apple, staples the ticket, and zips it as Q-Dock.zip for GitHub Releases.
#
# One-time setup on the Mac that makes releases:
#   1. Install the "Developer ID Application: HQE Systems, Inc. (JPKJW4C8V6)" certificate in your login keychain.
#   2. Save notarization credentials in the keychain (you'll be prompted for an app-specific password from
#      account.apple.com; nothing is stored in this repo):
#        xcrun notarytool store-credentials qdock-notary --apple-id <your Apple ID> --team-id JPKJW4C8V6
set -euo pipefail
cd "$(dirname "$0")"

TEAM=JPKJW4C8V6
PROFILE=${NOTARY_PROFILE:-qdock-notary}
APP=Q-Dock.app

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' -v t="($TEAM)" '/Developer ID Application:/ && index($2, t) {print $2; exit}')
if [ -z "$IDENTITY" ]; then
  echo "No valid 'Developer ID Application: … ($TEAM)' certificate in your keychain. See the setup notes at the top of release.sh." >&2
  exit 1
fi

QDOCK_SIGN_IDENTITY="$IDENTITY" ./build.sh
codesign --verify --strict --deep --verbose=2 "$APP"

echo "Submitting to Apple for notarization (usually a few minutes)…"
SUBMIT=$(mktemp -d)/Q-Dock.zip
ditto -c -k --keepParent "$APP" "$SUBMIT"
OUT=$(xcrun notarytool submit "$SUBMIT" --keychain-profile "$PROFILE" --wait --output-format json)
rm -rf "$(dirname "$SUBMIT")"
STATUS=$(print -r -- "$OUT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')
ID=$(print -r -- "$OUT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
if [ "$STATUS" != "Accepted" ]; then
  echo "Notarization failed ($STATUS). Apple's log:" >&2
  [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" >&2
  exit 1
fi

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

rm -f Q-Dock.zip
ditto -c -k --keepParent "$APP" Q-Dock.zip
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
echo "Ready: $(pwd)/Q-Dock.zip (Q-Dock $VERSION, notarized). Attach it to the v$VERSION GitHub release."
