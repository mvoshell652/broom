#!/bin/sh
# Runs the tests. With Apple's Command Line Tools, `swift test` does not find Swift Testing on its own, so this points
# it at the framework and its macro plugin. With Xcode it runs `swift test` as is.
#
# Usage: scripts/test.sh [swift test arguments]
set -eu

cd "$(dirname "$0")/.."
developer="$(xcode-select -p 2>/dev/null || true)"
developer="${DEVELOPER_DIR:-$developer}"

case "$developer" in
*CommandLineTools*)
    framework="$(find "$developer" -name Testing.framework -maxdepth 8 -print -quit 2>/dev/null)"
    if [ -z "$framework" ]; then
        echo "Swift Testing was not found in $developer. Update the Command Line Tools to 26 or later." >&2
        exit 1
    fi
    frameworks="$(dirname "$framework")"
    set -- -Xswiftc -F -Xswiftc "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" "$@"
    # Swift Testing loads this at run time; add its folder to the test bundle's search path when it lives elsewhere.
    interop="$(find "$developer" -name 'lib_TestingInterop.dylib' -print -quit 2>/dev/null)"
    if [ -n "$interop" ]; then
        set -- -Xlinker -rpath -Xlinker "$(dirname "$interop")" "$@"
    fi
    plugin="$(find "$developer" -name 'libTestingMacros.dylib' -print -quit 2>/dev/null)"
    if [ -n "$plugin" ]; then
        set -- -Xswiftc -plugin-path -Xswiftc "$(dirname "$plugin")" "$@"
    fi
    echo "Swift Testing from $frameworks${plugin:+, macros from $(dirname "$plugin")}${interop:+, interop from $(dirname "$interop")}"
    ;;
esac

exec swift test "$@"
