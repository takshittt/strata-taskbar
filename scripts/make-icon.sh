#!/bin/bash
# Renders the master icon and builds Resources/AppIcon.icns from it.
# Usage: scripts/make-icon.sh
set -euo pipefail

cd "$(dirname "$0")/.."

WORK="build/icon"
ICONSET="$WORK/AppIcon.iconset"
rm -rf "$WORK"
mkdir -p "$ICONSET"

swift scripts/make-icon.swift "$WORK/master.png"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK/master.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$WORK/master.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Built Resources/AppIcon.icns"
