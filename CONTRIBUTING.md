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
