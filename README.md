# Umbra

Umbra is a free menu bar app for macOS that controls monitor brightness, contrast, volume, input, and power. It covers the same features as Lunar.app, with no paid tier. It is written from scratch and does not use Lunar's code.

## Build and install

Umbra builds with the Swift command line tools. Xcode is not needed.

```bash
./build.sh
cp -R build/Umbra.app ~/Applications/
open ~/Applications/Umbra.app
```

## Main window

Umbra lives in the menu bar. If you can't see the icon (for example, it's hidden behind the notch), open the main window. It has the same controls as the menu.

- Open Umbra again from Applications, Spotlight, or the Dock.
- Run `umbra open`, or open the link `umbra://open`.
- If the menu bar icon is hidden when Umbra starts, the window opens by itself.

Umbra shows a Dock icon while a window is open. Settings > General has options to always show the Dock icon and to open the window at every start.

The first time Umbra starts, macOS asks for Accessibility access. Umbra needs it for the brightness and volume keys and for Cleaning Mode.

## First launch

A welcome window shows your screens with working brightness sliders, suggests an adaptive mode, and offers the brightness and volume keys. Open it again from Settings > CLI & About.

Modes that need a permission (Sensor, Location) explain what it's for before macOS asks. Screen arrangement changes switch back after 15 seconds unless you click Keep.

## Features

- Brightness, contrast, volume, and mute for external monitors over DDC (Apple Silicon).
- Apple Native control for the built-in display and Apple or LG UltraFine displays.
- Gamma (software) dimming for monitors without DDC, and a network relay option.
- Sub-zero dimming below 0%, and XDR Brightness above 100% on XDR displays.
- Adaptive modes: Manual, Sync, Location, Clock (schedule), and Sensor.
- BlackOut: turn a monitor off and on. Methods: disconnect, mirror and dim, or DDC power off. Auto BlackOut is optional.
- FaceLight, Night Mode, and Cleaning Mode.
- Input switching, resolution, rotation, and color gains per display.
- Screen arrangement: side by side, top to bottom, others above main, mirror, stop mirroring, set main, swap.
- Presets, app presets, global hotkeys, media keys, and an on-screen display.
- A CLI and `umbra://` links for scripts and the Shortcuts app.

## Default hotkeys

These match Lunar's defaults where Lunar has the same action.

| Action | Keys |
|---|---|
| Brightness 0%, 25%, 50%, 75%, 100% | ⌃⌘0 to ⌃⌘4 |
| FaceLight | ⌃⌘5 |
| BlackOut display under cursor | ⌃⌘6 |
| BlackOut without mirroring | ⌃⇧⌘6 |
| Power off (DDC standby) | ⌃⌥⌘6 |
| BlackOut all other displays | ⌃⌥⇧⌘6 |
| Turn all displays back on | ⌃⌘7 |
| Next adaptive mode | ⌃⌥⌘L |
| Open menu | ⌥⇧⌘L |
| Night Mode | ⌃⌥⌘N |

Change any of them in Settings > Hotkeys.

## CLI

Run `build/Umbra.app/Contents/MacOS/Umbra help` for the full list. Settings > CLI & About can install an `umbra` command on your PATH.

```bash
umbra displays
umbra set C27 brightness 40
umbra blackout C27 on
umbra night toggle
umbra arrange horizontal
```

When the app is open, the CLI sends each command to the app and prints its answer.

## Notes

- Some monitors answer DDC reads with noise (the Samsung C27F390 over HDMI does). Umbra does not need reads. It remembers the last value it wrote, like Lunar. Turn on "Read values from monitor at startup" in Settings > Displays for monitors that answer reads correctly.
- `umbra render <folder>` saves PNG images of the menu and each Settings tab. Use it to check the UI without opening the app.
- Not included: HDR toggle, Sidecar, and native Shortcuts actions. Use `umbra://` links or the CLI from Shortcuts instead.
