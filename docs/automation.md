# Diagnostics and the auto-fix loop

How a monitor problem on someone else's Mac turns into a tested fix.

```
Umbra (diagnostics on) ──> PostHog ──> GitHub issue ──> Claude opens a PR ──> you merge ──> you run Release
   ddc_summary, crash       webhook      "Monitor: X"     with a simulator test              DMG, Sparkle, Homebrew
```

Nothing ships without a person: Claude only opens pull requests, and a release starts only when you run the Release workflow. One bad automatic release could break monitors for everyone at once.

## 1. Diagnostics in the app

Off by default. People turn it on in Settings > General > Diagnostics. When on, Umbra sends anonymous events to PostHog:

| Event | When | What |
|---|---|---|
| `app_launched` | 5 seconds after launch | Umbra and macOS versions, Mac model, display count |
| `display_detected` | after launch, per display | model name, EDID vendor and product codes, control method, DDC link found |
| `ddc_summary` | every 10 minutes and on quit, only when something failed | per display and control: writes and reads that worked or failed, last IOKit error, noisy replies |
| `failure` | when BlackOut or similar fails | what failed |
| `crash` | the launch after a crash (from macOS MetricKit) | exception type, signal, Umbra's call stack |

Never sent: serial numbers, names people give their displays, screen contents, files, location, or keystrokes. Events are anonymous (`$process_person_profile: false`) and keyed by a random per-install ID.

A build only sends anything if it has a PostHog project key. Set it when building:

```bash
UMBRA_POSTHOG_KEY=phc_your_project_key ./build.sh
```

"Report a problem with a monitor" (More menu and Settings) works without PostHog: it opens a GitHub issue with the Mac and display details filled in, for the person to check before sending.

## 2. PostHog to GitHub issues

1. Create a PostHog project and copy its project API key into the `UMBRA_POSTHOG_KEY` repository secret.
2. In PostHog, add a destination (webhook) for the `ddc_summary` and `crash` events that calls:
   `POST https://api.github.com/repos/JordanCampbellDesign/Umbra/dispatches`
   with a fine-grained GitHub token that can write this repository's contents, and the body
   `{"event_type": "monitor-failure", "client_payload": {{ event.properties }}}`.
3. The `Diagnostics to issue` workflow files one issue per monitor model, labeled `monitor`, `from-diagnostics`, and `auto-fix`. Later reports add comments.

## 3. Claude writes the fix

The `Claude fix` workflow runs when an issue gets the `auto-fix` label, or when someone comments `@claude`. It needs the `ANTHROPIC_API_KEY` repository secret.

Claude reproduces the problem with the monitor simulator before changing anything:

- `Tests/UmbraTests/SimulatedMonitor.swift` is a fake monitor that speaks DDC/CI (MCCS). It checks Umbra's checksums, applies settings, answers reads, and can misbehave: noisy reads, dropped writes, IOKit errors, unsupported controls.
- `Tests/UmbraTests/Monitors/*.json` holds one profile per monitor model. Every profile runs through the same contract tests (`swift test`): writes must land, and reads may fail but must never return a wrong value.

There's also a **monitor zoo** (`Tests/UmbraTests/MonitorZooTests.swift`): 2,000 generated monitors that mix the quirks seen in the wild (value ranges of 50, 64, or 255 instead of 100, noisy or missing reads, dropped writes, I/O errors, no speakers, no DDC contrast). It's seeded, so any failure reproduces exactly. It found that Umbra assumed every monitor uses 0 to 100: a monitor using 0 to 255 topped out at about 39% brightness. Umbra now learns each control's range when a monitor connects, and Settings > Displays has a manual override for monitors that never answer.

No public database of per-model DDC behavior exists. [linuxhw/EDID](https://github.com/linuxhw/EDID) has identity data for about 175,000 monitors (names, vendors, product codes) but nothing about how they respond over DDC. That's why the zoo generates behavior, and why reports from real monitors (diagnostics or issues) become profiles.

So each reported monitor becomes a profile, the fix has to make its test pass, and every earlier profile keeps it from breaking other monitors. The pull request runs the normal `Build` workflow.

## 4. Release

After merging, run the `Release` workflow from the Actions tab with the new version number. It needs these repository secrets:

| Secret | What it is |
|---|---|
| `SIGNING_P12_BASE64` | the "Umbra Local Signing" certificate and key, exported from Keychain Access as .p12, then `base64 -i cert.p12` |
| `SIGNING_P12_PASSWORD` | the password you set when exporting |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle's private update key: run Sparkle's `generate_keys -x key.txt` and paste the file's contents |
| `TAP_TOKEN` | a fine-grained token that can push to `JordanCampbellDesign/homebrew-tap` |
| `UMBRA_POSTHOG_KEY` | optional, the PostHog project key for diagnostics |

The workflow signs with the same certificate as your local builds, so macOS keeps each user's permissions across the update.

## Virtual screens

`scripts/e2e/virtual_displays.sh` runs Umbra's display code against virtual screens: real displays as far as macOS knows, made in software through the private `CGVirtualDisplay` API (the one DeskPad and BetterDisplay use). The bridge lives in `Sources/VirtualDisplay`, which only the tests link. It checks:

- a new monitor is detected, with its brand (for Siri) and the right control method;
- software dimming really changes the screen's gamma, including Away mode's black;
- BlackOut turns the screen off (disconnect, or Umbra's mirror-and-black fallback) and back on;
- swapping two screens moves them, and "Go back" restores the arrangement.

It only touches the screens it creates. It keeps the displays awake while it runs, because macOS postpones removing virtual screens while displays sleep, and it runs each test in its own process, because after a disconnect macOS can hold a virtual screen until the process exits. These tests found that Umbra gave unrelated screens another monitor's DDC link; links now need a real match unless the pairing is certain.

It also runs the whole DDC path on a real macOS screen: a virtual screen with a simulated monitor plugged in as its DDC link. Umbra learns the monitor's 0-255 range, and the slider, a fast drag, Night Mode, and DDC power all reach it.

## Timing

Real monitors need time. The simulator can model monitors that answer slowly (reading too early returns zeros) and firmware that ignores commands sent too close together. A virtual clock stands in for real waits, so these tests run instantly and exactly. They showed that a fast slider drag could leave slow firmware on an older value than the slider shows; Umbra now re-sends the final value 150 ms after a burst. The zoo includes these timing traits too.
