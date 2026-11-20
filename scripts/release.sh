#!/bin/sh
# Builds, signs, notarizes and staples Broom.app for distribution outside the App Store.
#
# Needs, once:
#   1. A "Developer ID Application" certificate in your keychain (Apple Developer account > Certificates).
#   2. Notary credentials saved under a profile name:
#        xcrun notarytool store-credentials broom-notary --apple-id <you> --team-id <team> --password <app-specific password>
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=broom-notary scripts/release.sh [output-folder]
#
# This uploads the app to Apple's notary service. Nothing else in the project talks to the network.
set -eu

cd "$(dirname "$0")/.."
OUT="${1:-build/release}"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

case "$SIGN_IDENTITY" in
    "Developer ID Application:"*) ;;
    *) echo "SIGN_IDENTITY must be a Developer ID Application identity; got: $SIGN_IDENTITY" >&2; exit 64 ;;
esac

UNIVERSAL=1 SIGN_IDENTITY="$SIGN_IDENTITY" scripts/make-app.sh "$OUT"
APP="$OUT/Broom.app"
ZIP="$OUT/Broom.zip"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

# Re-zip so the download carries the stapled ticket.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"
echo "Notarized: $ZIP"
