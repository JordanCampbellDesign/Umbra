# Contributing to Umbra

Thanks for helping. Bug reports, monitor compatibility notes, and pull requests are all welcome.

## Set up

1. Install Xcode and XcodeGen: `brew install xcodegen`.
2. Clone the repo and run `./build.sh`. It builds `build/Umbra.app`.
3. Copy the app to `~/Applications` and open it.

Without Xcode, `./build.sh` builds with the Swift command line tools. That build has no Siri actions and no Control Center controls.

`Umbra.xcodeproj` is generated from `project.yml`. Edit `project.yml`, not the project, then run `xcodegen`.

## Signing on your Mac

macOS ties Accessibility access to an app's signature. An ad-hoc signed build loses that access every time you rebuild. To keep it, create a local code-signing certificate named "Umbra Local Signing" in Keychain Access (Certificate Assistant > Create a Certificate, type Code Signing). `build.sh` uses it when it exists.

## Before you open a pull request

- Run `swift test`. It needs Xcode, not only the command line tools.
- Keep changes small and focused on one thing.
- Match the style of the file you change. Comments explain why, not what.
- For UI changes, add a before and after image. `umbra render <folder>` saves PNGs of the menu and Settings.
- For monitor fixes, name the monitor model and how it connects (HDMI, DisplayPort, USB-C, dock).

## Report a monitor that doesn't work

Open an issue with the "Monitor compatibility" template. Include the output of `umbra displays` and `UMBRA_DEBUG=1 umbra ddc <display> 0x10`.

## Promo loop

The promo video is built from `docs/promo/promo.html`, where every frame is a pure function of time. To re-render it:

```bash
cd scripts/promo && npm install && node render.mjs sheet   # one still per beat, for review
node render.mjs video                                      # 1440x1440 60 fps MP4
```

The MP4 is not kept in git (each render would add about 6 MB to the history). Upload a new render to the `promo` pre-release with `scripts/promo/publish.sh`. The README links to it there.

## End-to-end tests

Two suites run against the real app. Both change your displays for a moment and put them back.

- **CLI suite:** `scripts/e2e/cli_e2e.py`. It restarts the installed app (`~/Applications/Umbra.app`, or pass `--app`) and checks each change through `umbra state`: brightness and contrast round trips, below 0%, mode switch, Night Mode, Away mode and its keep-awake assertion, link safety, and that commands without the app's token are rejected. It ends by checking every display is back where it started. Add `--disruptive` to also turn an external monitor off and on with BlackOut. Results go to `test-results/e2e-cli.json`.
- **Virtual screens:** `scripts/e2e/virtual_displays.sh` tests detection, software dimming, BlackOut, and arrangement undo on virtual screens it creates, so no monitor is needed. See docs/automation.md.
- **UI suite:** `scripts/e2e/ui_e2e.sh`. It runs XCUITest against a fresh build: it opens the main window and drives the mode picker, a brightness slider, and the Away mode setting through accessibility. It quits your installed copy first and reopens it after. The first run asks for your password to allow UI automation.
