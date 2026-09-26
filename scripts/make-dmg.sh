#!/bin/sh
# Packs build/Umbra.app into build/Umbra-<version>.dmg with the drag-to-Applications window.
# Needs dmgbuild: python3 -m venv .venv-dmg && .venv-dmg/bin/pip install dmgbuild
set -e
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/Umbra.app/Contents/Info.plist)
DMGBUILD=$(command -v dmgbuild || echo .venv-dmg/bin/dmgbuild)
[ -x "$DMGBUILD" ] || { echo "dmgbuild not found. See the comment at the top of this script."; exit 1; }
# dmgbuild picks up background@2x.png next to background.png for Retina screens.
[ -f scripts/dmg/background@2x.png ] || swift scripts/dmg/make-background.swift scripts/dmg
OUT="build/Umbra-$VERSION.dmg"
rm -f "$OUT"
"$DMGBUILD" -s scripts/dmg/settings.py -D app=build/Umbra.app "Umbra" "$OUT"
echo "Built $OUT"
