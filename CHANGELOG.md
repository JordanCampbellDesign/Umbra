# Changelog

## Unreleased

- Fix: monitors whose brightness, contrast, or volume range isn't 0 to 100 (for example 0 to 255) couldn't reach full brightness. Umbra now learns each control's range when the monitor connects, and Settings > Displays has a manual override.

- Optional, anonymous monitor diagnostics (off by default) to help fix monitors that don't work, and "Report a problem with a monitor", which opens a pre-filled GitHub issue.
- A DDC monitor simulator with per-model profiles, so monitor fixes are tested without the monitor.

- VoiceOver: icon-only buttons (Settings, Quit, each display's power button, mute) have spoken names, and sliders read as "Brightness, 51 percent" instead of repeating their icon and number.

## 1.0.1

- Away mode: after no input for a time you choose, screens fade down, then turn black, while the Mac stays awake. Any input wakes them. Options to leave one screen on, wait for video, and put DDC monitors in standby. `umbra away now|off|status`.
- Fix the BlackOut hint in Settings, which named the wrong hotkey for turning displays back on.
- Sync mode listens for brightness changes instead of checking twice a second, so Umbra wakes the Mac far less often while idle.
- Smaller download: the app is 3.1 MB (was 5.8 MB) and the DMG is under 1 MB (was 2.1 MB).
- `umbra state` prints the app's state as JSON, and `umbra set <display> offset <value>` sets the Sync offset.

## 1.0.0

First public release.

- Brightness, contrast, volume, mute, input, and power for external monitors over DDC on Apple Silicon.
- Apple Native control for the built-in display and Apple displays, software dimming for everything else, and a network relay option.
- Adaptive modes: Manual, Sync, Location, Clock, and Sensor. Umbra remembers the mode for each desk setup.
- BlackOut to turn screens off and on, FaceLight, Night Mode, Cleaning Mode, sub-zero dimming, and XDR Brightness.
- Screen arrangement with a 15-second undo.
- Siri and Shortcuts actions, Control Center and menu bar controls, a CLI, and `umbra://` links.
- Spring-based fades: each change of target adds one closed-form spring, so fades never jump.
- Scroll over the menu bar icon, or hold ⌃⌥ and scroll, to change brightness.
- Main window, welcome screen, and explanations before every permission prompt.
