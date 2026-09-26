#!/bin/sh
# Builds Umbra.app into ./build
# With Xcode installed it builds the Xcode project, which adds the Siri and Shortcuts actions.
# Without Xcode it falls back to the Swift package (no Siri actions).
set -e
cd "$(dirname "$0")"
APP=build/Umbra.app
mkdir -p build

# Sign with the local "Umbra Local Signing" certificate when it exists, so macOS keeps
# Accessibility access across rebuilds. Falls back to ad-hoc signing.
ID=$(security find-identity -p codesigning 2>/dev/null | awk '/"Umbra Local Signing"/ {print $2; exit}')

XCODE=/Applications/Xcode.app/Contents/Developer
if [ -d "$XCODE" ]; then
  export DEVELOPER_DIR="$XCODE"
  command -v xcodegen >/dev/null && xcodegen generate --quiet
  xcodebuild -project Umbra.xcodeproj -scheme Umbra -configuration Release -derivedDataPath .xcbuild \
    CODE_SIGN_IDENTITY="${ID:--}" build > .xcbuild.log 2>&1 || { grep -E "error:" .xcbuild.log; echo "Build failed. See .xcbuild.log"; exit 1; }
  rm -rf "$APP"
  cp -R .xcbuild/Build/Products/Release/Umbra.app "$APP"
else
  swift build -c release
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp .build/release/Umbra "$APP/Contents/MacOS/Umbra"
  cp Resources/Info.plist "$APP/Contents/Info.plist"
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  codesign --force --deep --sign "${ID:--}" "$APP"
fi
echo "Built $APP"
