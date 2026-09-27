#!/bin/sh
# Runs the XCUITest UI suite against a fresh build. The installed copy of Umbra is quit first
# (two copies would fight over hotkeys and gamma) and reopened afterward.
# The first run asks you to allow the test runner in System Settings > Privacy & Security > Accessibility.
set -e
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
command -v xcodegen >/dev/null && xcodegen generate --quiet
was_running=$(pgrep -x Umbra >/dev/null && echo yes || echo no)
pkill -x Umbra || true
status=0
rm -rf test-results/ui.xcresult
xcodebuild test -project Umbra.xcodeproj -scheme Umbra -derivedDataPath .xcbuild -resultBundlePath test-results/ui.xcresult 2>&1 \
  | grep -E "Test Case|error:|\*\* TEST|passed|failed" || status=$?
[ "$was_running" = yes ] && open ~/Applications/Umbra.app
exit $status
