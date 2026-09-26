#!/bin/sh
# Builds Umbra.app into ./build
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Umbra.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Umbra "$APP/Contents/MacOS/Umbra"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ ! -f build/AppIcon.icns ]; then
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sign with the local "Umbra Local Signing" certificate when it exists, so macOS keeps
# Accessibility access across rebuilds. Falls back to ad-hoc signing.
ID=$(security find-identity -p codesigning 2>/dev/null | awk '/"Umbra Local Signing"/ {print $2; exit}')
codesign --force --deep --sign "${ID:--}" "$APP"
echo "Built $APP"
