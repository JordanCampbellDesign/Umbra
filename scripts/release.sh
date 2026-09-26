#!/bin/sh
# Builds, packs a DMG, signs, and publishes a release, then updates appcast.xml for Sparkle.
# Usage: scripts/release.sh 1.0.1
# Needs: Xcode, XcodeGen, dmgbuild (see scripts/make-dmg.sh), the GitHub CLI (gh), and Sparkle's EdDSA key in your keychain
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

# The DMG opens a drag-to-Applications window. Sparkle installs updates from the same file.
./scripts/make-dmg.sh
rm -rf releases && mkdir releases
DMG="releases/Umbra-$VERSION.dmg"
cp "build/Umbra-$VERSION.dmg" "$DMG"
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "https://github.com/JordanCampbellDesign/Umbra/releases/download/v$VERSION/" releases
cp releases/appcast.xml appcast.xml

git add Resources/Info.plist appcast.xml
git commit -m "Release $VERSION"
git tag "v$VERSION"
git push origin main "v$VERSION"
gh release create "v$VERSION" "$DMG" --title "Umbra $VERSION" --notes-file CHANGELOG.md
