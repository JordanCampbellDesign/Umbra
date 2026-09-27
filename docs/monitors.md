# Monitor compatibility

How Umbra works with specific monitors. Add yours with a pull request, or open a "Monitor compatibility" issue.

**Control** is how Umbra talks to the display:
- **Apple Native:** macOS controls brightness directly (built-in displays and Apple-made or Apple-certified displays).
- **DDC:** Umbra sends standard monitor commands over the video cable.
- **Gamma:** software dimming, for monitors that don't accept DDC.

Legend: ✅ works, ⚠️ partly or with a note, ❌ doesn't work, ❔ not checked yet.

| Monitor | Connection | Mac | Control | Brightness | Contrast | Volume | Input | Power off | DDC reads | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| MacBook Pro built-in (XDR) | built-in | Apple Silicon | Apple Native | ✅ | n/a | n/a | n/a | ✅ BlackOut | n/a | XDR Brightness above 100% works. |
| LG UltraFine 5K | Thunderbolt | Apple Silicon | Apple Native | ✅ | n/a | n/a | n/a | ✅ BlackOut | n/a | Shows up as two DDC links (tiled); Umbra uses Apple Native. |
| Samsung C27F390 | HDMI | Apple Silicon | DDC | ❔ | ❔ | ❔ | ❔ | ✅ BlackOut | ❌ | Reads return noise, so Umbra remembers the last value it sent. Its own on-screen menu can't be hidden over DDC. |

## Reporting a monitor

Include the output of these two commands:

```bash
umbra displays
UMBRA_DEBUG=1 umbra ddc <display> 0x10
```

Then say which controls change the monitor when you move them in Umbra's menu.
