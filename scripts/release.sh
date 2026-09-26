#!/bin/sh
# Builds, zips, signs, and publishes a release, then updates appcast.xml for Sparkle.
# Usage: scripts/release.sh 1.0.1
# Needs: Xcode, XcodeGen, the GitHub CLI (gh), and Sparkle's EdDSA key in your keychain
# (created once with Sparkle's generate_keys tool).
set -e
cd "$(dirname "$0")/.."
VERSION="$1"
[ -n "$VERSION" ] || { echo "Usage: scripts/release.sh <version>"; exit 1; }

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist
./build.sh

SPARKLE_BIN=$(find .xcbuild/SourcePackages/artifacts -type d -path "*Sparkle/bin" | head -1)
[ -d "$SPARKLE_BIN" ] || { echo "Sparkle tools not found. Build once with Xcode first."; exit 1; }

rm -rf releases && mkdir releases
ZIP="releases/Umbra-$VERSION.zip"
ditto -c -k --keepParent build/Umbra.app "$ZIP"
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "https://github.com/JordanCampbellDesign/Umbra/releases/download/v$VERSION/" releases
cp releases/appcast.xml appcast.xml

git add Resources/Info.plist appcast.xml
git commit -m "Release $VERSION"
git tag "v$VERSION"
git push origin main "v$VERSION"
gh release create "v$VERSION" "$ZIP" --title "Umbra $VERSION" --notes-file CHANGELOG.md
