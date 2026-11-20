#!/bin/sh
# Builds Broom from this checkout and installs it in /Applications, or ~/Applications when that is not writable.
# Run it again to update. Your settings, search index and history are kept.
set -eu

cd "$(dirname "$0")"

if [ "$(uname)" != "Darwin" ]; then
    echo "Broom runs on macOS only." >&2
    exit 1
fi
major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 14 ]; then
    echo "Broom needs macOS 14 or later; this Mac has $(sw_vers -productVersion)." >&2
    exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
    echo "Broom is built with Xcode 26 or later. Install Xcode, open it once, then run this again." >&2
    exit 1
fi

echo "Building Broom. The first build fetches one dependency (GRDB) and takes a few minutes."
if ! scripts/make-app.sh build; then
    echo "The build failed. Broom needs Xcode 26 or later: check with 'xcodebuild -version'." >&2
    exit 1
fi

dest=/Applications
if [ ! -w "$dest" ]; then
    dest="$HOME/Applications"
    mkdir -p "$dest"
fi

# Quit a running copy so it can be replaced.
osascript -e 'quit app "Broom"' >/dev/null 2>&1 || true
rm -rf "$dest/Broom.app"
cp -R build/Broom.app "$dest/"
open "$dest/Broom.app"

echo "Broom is installed in $dest and running: look for the broom in the menu bar."
echo "To see waiting sessions right away, open its settings and choose Connect Claude Code."
