#!/bin/bash
# Builds Strata with SwiftPM, assembles build/Strata.app and signs it with "Strata Dev".
# Usage: scripts/build-app.sh [--open]
# Debug arm64 only for now; the universal release build arrives in Phase 14 (spec §6).
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="Strata Dev"
APP="build/Strata.app"

swift build --arch arm64
BIN="$(swift build --arch arm64 --show-bin-path)/Strata"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Strata"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signing (-s -) would make macOS forget the Accessibility grant on every rebuild.
codesign --force --sign "$IDENTITY" "$APP"
echo "Built and signed $APP"

if [[ "${1:-}" == "--open" ]]; then
    open "$APP"
fi
