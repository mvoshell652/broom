#!/bin/sh
# Builds Broom from this checkout and installs it in /Applications, or ~/Applications when that is not writable.
# Run it again to update. Your settings, search index and history are kept.
set -eu

cd "$(dirname "$0")"

if [ "$(uname)" != "Darwin" ]; then
    echo "Broom runs on macOS only." >&2
    exit 1
fi
# Broom runs on macOS 14, but building it needs the version 26 tools, and the oldest of those need macOS 15.6.
version=$(sw_vers -productVersion)
major=$(echo "$version" | cut -d. -f1)
minor=$(echo "$version" | cut -d. -f2)
if [ "$major" -lt 15 ] || { [ "$major" -eq 15 ] && [ "${minor:-0}" -lt 6 ]; }; then
    echo "Building Broom needs macOS Sequoia 15.6 or later; this Mac has $version." >&2
    exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
    echo "Broom is built with Apple's Command Line Tools 26 or later. Install them with 'xcode-select --install', then run this again." >&2
    exit 1
fi

echo "Building Broom. The first build fetches one dependency (GRDB) and takes a few minutes."
if ! scripts/make-app.sh build; then
    echo "The build failed. Broom needs Apple's Command Line Tools 26 or later: check with 'swift --version' (Swift 6.2 or later)." >&2
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
