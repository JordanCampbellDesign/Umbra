# Security

Please report security problems privately through GitHub's "Report a vulnerability" button on the Security tab, not in a public issue.

## How Umbra limits access

- The CLI talks to the app with distributed notifications. Each command carries a random token that the app stores in `~/Library/Application Support/Umbra/cli-token`, readable only by your user account. Other apps can't send commands without it.
- `umbra://` links can come from web pages, so they only run safe commands (brightness, contrast, volume, presets, Night Mode, FaceLight, XDR, mode, open). They can't turn screens off, rearrange them, block the keyboard, sleep the Mac, or send raw DDC commands.
- Control Center controls run in a sandboxed extension and send one of five named actions: Night Mode, FaceLight, Brighter, Dimmer, and All Screens On. Distributed notifications can't prove who sent them, so any app could post these. That's why this channel only carries harmless, reversible actions (nothing that turns a screen off), and the app ignores bursts. A fully authenticated channel needs an App Group, which needs a paid Apple developer account.
- Sensor mode only contacts the address you enter. Location mode keeps your coordinates on your Mac.
- Diagnostics are off by default and anonymous when on. They never include serial numbers, screen contents, files, location, or keystrokes. See docs/automation.md.
