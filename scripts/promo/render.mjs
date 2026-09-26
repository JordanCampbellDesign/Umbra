// Renders docs/promo/promo.html.
//   node render.mjs sheet   -> 32 stills (one per beat) and a contact sheet
//   node render.mjs video   -> 1440x1440 60 fps loop: 4 subframes per frame (240 fps) blended with ffmpeg tmix
import { chromium } from "playwright";
import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const page_url = "file://" + path.join(root, "docs/promo/promo.html");
const out = path.join(root, "docs/promo");
const mode = process.argv[2] ?? "sheet";
const P = 16, FPS = 60, SUB = 4;

const browser = await chromium.launch({ args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1440 }, deviceScaleFactor: 1 });
page.on("console", m => { if (m.type() === "warning" || m.type() === "error") console.log("[page]", m.text()); });
await page.goto(page_url);
await page.evaluate(() => window.promoReady);
const stage = await page.$("#stage");
const shot = async t => { await page.evaluate(t => window.seek(t), t); return stage.screenshot({ type: "png" }); };

function ffmpeg(args, stdin) {
  const p = spawn("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", ...args], { stdio: [stdin ? "pipe" : "ignore", "inherit", "inherit"] });
  return p;
}
const done = p => new Promise((res, rej) => p.on("close", c => (c === 0 ? res() : rej(new Error("ffmpeg " + c)))));

if (mode === "sheet") {
  const dir = path.join(out, "sheet"); mkdirSync(dir, { recursive: true });
  const p = ffmpeg(["-f", "image2pipe", "-framerate", "1", "-i", "-", "-vf", "scale=360:360,tile=8x4:padding=6:color=white", "-frames:v", "1", path.join(dir, "contact-sheet.png")], true);
  for (let n = 1; n <= 32; n++) {
    const t = (n - 1) * 0.5 + 0.34;       // just after each beat's action lands
    const png = await shot(t);
    p.stdin.write(png);
    if ([1, 4, 8, 12, 16, 18, 22, 23, 27, 29, 30, 32].includes(n)) (await import("node:fs")).writeFileSync(path.join(dir, `beat-${String(n).padStart(2, "0")}.png`), png);
  }
  p.stdin.end(); await done(p);
  console.log("wrote", path.join(dir, "contact-sheet.png"));
} else {
  const total = P * FPS * SUB;             // 3840 subframes
  const mp4 = path.join(out, "umbra-loop.mp4");
  const p = ffmpeg(["-f", "image2pipe", "-framerate", String(FPS * SUB), "-i", "-",
    "-vf", "tmix=frames=4,select='eq(mod(n\\,4)\\,3)',setpts=N/60/TB",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", "-movflags", "+faststart", mp4], true);
  const t0 = Date.now();
  for (let i = 0; i < total; i++) {
    const png = await shot(i / (FPS * SUB));
    if (!p.stdin.write(png)) await new Promise(r => p.stdin.once("drain", r));
    if (i % 240 === 0) console.log(`${i}/${total}  ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  }
  p.stdin.end(); await done(p);
  console.log("wrote", mp4);
}
await browser.close();
