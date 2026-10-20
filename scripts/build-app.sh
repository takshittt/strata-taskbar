#!/bin/bash
# Builds Strata with SwiftPM, assembles build/Strata.app and signs it with "Strata Dev".
# Usage: scripts/build-app.sh [--release] [--open]
#   default    arm64 debug build (includes the DEBUG-only test hooks)
#   --release  universal arm64 + x86_64 release build
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="Strata Dev"
APP="build/Strata.app"
RELEASE=0
OPEN=0
for arg in "$@"; do
    case "$arg" in
        --release) RELEASE=1 ;;
        --open) OPEN=1 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ $RELEASE == 1 ]]; then
    # SwiftPM's build backend emits a universal binary directly. (Per-triple builds share one
    # output path here, so the spec's build-twice-and-lipo approach would overwrite a slice.)
    swift build -c release --arch arm64 --arch x86_64
    cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Strata" "$APP/Contents/MacOS/Strata"
    lipo -info "$APP/Contents/MacOS/Strata"
else
    swift build --arch arm64
    cp "$(swift build --arch arm64 --show-bin-path)/Strata" "$APP/Contents/MacOS/Strata"
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signing (-s -) would make macOS forget the Accessibility grant on every rebuild.
codesign --force --sign "$IDENTITY" "$APP"
echo "Built and signed $APP"

if [[ $OPEN == 1 ]]; then
    open "$APP"
fi
