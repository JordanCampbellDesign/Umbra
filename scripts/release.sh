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
# In CI the EdDSA key comes from a file; on your Mac it comes from the keychain.
KEY_ARGS=""; [ -n "$SPARKLE_KEY_FILE" ] && KEY_ARGS="--ed-key-file $SPARKLE_KEY_FILE"
"$SPARKLE_BIN/generate_appcast" $KEY_ARGS --download-url-prefix "https://github.com/JordanCampbellDesign/Umbra/releases/download/v$VERSION/" releases
cp releases/appcast.xml appcast.xml

git add Resources/Info.plist appcast.xml CHANGELOG.md
git commit -m "Release $VERSION"
git tag "v$VERSION"
git push origin main "v$VERSION"
# Release notes: only this version's section of the changelog.
NOTES=$(mktemp)
awk -v v="## $VERSION" '$0==v{on=1;next} /^## /{if(on)exit} on' CHANGELOG.md > "$NOTES"
gh release create "v$VERSION" "$DMG" --title "Umbra $VERSION" --notes-file "$NOTES"

# Point the Homebrew cask at the new release, if the tap is checked out next to this repo.
TAP=../homebrew-tap
if [ -f "$TAP/Casks/umbra.rb" ]; then
  SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
  sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP/Casks/umbra.rb"
  git -C "$TAP" commit -qam "umbra $VERSION" && git -C "$TAP" push -q
  echo "Updated the Homebrew cask to $VERSION."
fi
