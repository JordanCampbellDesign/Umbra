# Security

Please report security problems privately through GitHub's "Report a vulnerability" button on the Security tab, not in a public issue.

## How Umbra limits access

- The CLI talks to the app with distributed notifications. Each command carries a random token that the app stores in `~/Library/Application Support/Umbra/cli-token`, readable only by your user account. Other apps can't send commands without it.
- `umbra://` links can come from web pages, so they only run safe commands (brightness, contrast, volume, presets, Night Mode, FaceLight, XDR, mode, open). They can't turn screens off, rearrange them, block the keyboard, sleep the Mac, or send raw DDC commands.
- Control Center controls run in a sandboxed extension. They send one of six named actions, and the app ignores anything else.
- Sensor mode only contacts the address you enter. Location mode keeps your coordinates on your Mac.
