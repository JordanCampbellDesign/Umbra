#!/bin/bash
# Runs Umbra's display code against virtual screens (no monitors needed): detection, software dimming,
# BlackOut, and arrangement undo. It briefly adds test screens to this Mac, and only changes those.
# - The installed copy of Umbra is quit first so it doesn't act on the test screens, then reopened.
# - caffeinate keeps the displays awake: while they sleep, macOS postpones removing virtual screens.
# - Each test runs in its own process: after a disconnect, macOS can hold a virtual screen until the process exits.
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
was_running=$(pgrep -x Umbra >/dev/null && echo yes || echo no)
pkill -x Umbra || true
swift build --build-tests >/dev/null 2>&1
status=0
for t in testDetectsANewMonitorWithItsBrand testSoftwareDimmingChangesTheScreen testBlackOutDisconnectsAndRestores testDDCMonitorOnAVirtualScreen testSwapThenUndoRestoresTheArrangement; do
  if UMBRA_VIRTUAL_DISPLAYS=1 caffeinate -d -u swift test --skip-build --filter "VirtualDisplayTests/$t" > /tmp/umbra-vd-$t.log 2>&1; then
    echo "PASS  $t"
  else
    echo "FAIL  $t"; grep -E "error:" /tmp/umbra-vd-$t.log | sed 's/^/      /'; status=1
  fi
done
[ "$was_running" = yes ] && open ~/Applications/Umbra.app
exit $status
