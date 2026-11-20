#!/bin/sh
# Builds Broom.app from the Swift package: release binaries, an Info.plist, the hook helper, and a signature.
#
# Usage: scripts/make-app.sh [output-folder]        (default: build)
# Environment:
#   SIGN_IDENTITY   codesign identity. Default "-" (ad-hoc), which is enough to run on this Mac.
#                   A "Developer ID Application: …" identity also turns on the hardened runtime, as notarization requires.
#   UNIVERSAL=1     build for Apple Silicon and Intel instead of this Mac's architecture only.
#   BROOM_VERSION   version written to Info.plist. Default 0.1.0.
set -eu

cd "$(dirname "$0")/.."
OUT="${1:-build}"
APP="$OUT/Broom.app"
VERSION="${BROOM_VERSION:-0.1.0}"
IDENTITY="${SIGN_IDENTITY:--}"

ARCHS=""
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCHS="--arch arm64 --arch x86_64"
fi

# shellcheck disable=SC2086
swift build -c release $ARCHS --product Broom
# shellcheck disable=SC2086
swift build -c release $ARCHS --product broom-hook
# shellcheck disable=SC2086
BIN="$(swift build -c release $ARCHS --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp "$BIN/Broom" "$APP/Contents/MacOS/Broom"
cp "$BIN/broom-hook" "$APP/Contents/Helpers/broom-hook"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Broom</string>
    <key>CFBundleIdentifier</key><string>app.broom.Broom</string>
    <key>CFBundleName</key><string>Broom</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP/Contents/Helpers/broom-hook"
    codesign --force --sign - "$APP"
else
    # Inside out, with the hardened runtime and a secure timestamp.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Helpers/broom-hook"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Broom"))"
