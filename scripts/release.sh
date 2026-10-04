#!/usr/bin/env bash
# Build Headroom.app (universal), sign it with your Developer ID, notarize and
# staple it, then wrap it in a signed + notarized DMG: dist/Headroom.dmg.
#
#   ./scripts/release.sh                      # needs a "Developer ID Application" cert
#   NOTARY_PROFILE=my-profile ./scripts/...   # notarytool keychain profile (default below)
#   NOTARIZE=0 ./scripts/release.sh           # sign only (faster; other Macs will warn)
#
# One-time notary setup (run in Terminal; it prompts for an app-specific password):
#   xcrun notarytool store-credentials <profile> --apple-id <you@example.com> --team-id <TEAMID>
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Headroom.app"
DMG="dist/Headroom.dmg"
PROFILE="${NOTARY_PROFILE:-glidepage-notary}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"

echo "› building (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Headroom"

echo "› assembling $APP"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Headroom"
cp Info.plist "$APP/Contents/Info.plist"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

notarize() { # file, what it is
	echo "› notarizing $2 (a few minutes)"
	local out id
	if ! out="$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1)"; then echo "$out"; exit 1; fi
	echo "$out" | grep -E "status:" | tail -1 | sed 's/^/  /'
	if ! echo "$out" | grep -q "status: Accepted"; then
		id="$(echo "$out" | sed -n 's/^ *id: //p' | head -1)"
		echo "✗ Apple did not accept $2:"
		xcrun notarytool log "$id" --keychain-profile "$PROFILE" || true
		exit 1
	fi
}

if [[ -z "$IDENTITY" ]]; then
	echo "› no Developer ID certificate found: ad-hoc signing (runs on this Mac only)"
	codesign --force --sign - "$APP"
else
	echo "› signing with $IDENTITY"
	codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
	codesign --verify --strict --verbose=2 "$APP"
	if [[ "${NOTARIZE:-1}" != "0" ]]; then
		ZIP="$(mktemp -d)/Headroom.zip"
		ditto -c -k --keepParent "$APP" "$ZIP"
		notarize "$ZIP" "the app"
		xcrun stapler staple -q "$APP" && echo "  ticket stapled to the app"
	fi
fi

echo "› dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Headroom" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
if [[ -n "$IDENTITY" ]]; then
	codesign --force --timestamp --sign "$IDENTITY" "$DMG"
	if [[ "${NOTARIZE:-1}" != "0" ]]; then
		notarize "$DMG" "the DMG"
		xcrun stapler staple -q "$DMG" && echo "  ticket stapled to the DMG"
	fi
fi
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
