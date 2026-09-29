// Sends people straight to the newest Umbra DMG, so the site never needs an edit after a release.
// GET /download        -> 302 to the DMG on GitHub
// GET /download?info=1 -> {"version":"1.0.3","size":1066802,"url":"..."} for the page's version label
// If GitHub is slow or down, people land on the release page instead of an error.
const REPO = "JordanCampbellDesign/Umbra";
const FALLBACK = `https://github.com/${REPO}/releases/latest`;

async function latestDMG() {
  const headers = { Accept: "application/vnd.github+json", "User-Agent": "umbra-site" };
  // Optional: a token raises GitHub's limit from 60 to 5,000 requests an hour. The edge cache below usually makes it unnecessary.
  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  const r = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers, signal: AbortSignal.timeout(4000) });
  if (!r.ok) return null;
  const release = await r.json();
  const dmg = release.assets?.find((a) => a.name.endsWith(".dmg"));
  return dmg ? { version: release.tag_name.replace(/^v/, ""), size: dmg.size, url: dmg.browser_download_url } : null;
}

export default async function handler(req, res) {
  let dmg = null;
  try { dmg = await latestDMG(); } catch {}

  if (dmg) {
    // Cache at Vercel's edge for 10 minutes, and keep serving the last good answer for a day if GitHub fails.
    res.setHeader("Cache-Control", "public, s-maxage=600, stale-while-revalidate=86400, stale-if-error=86400");
  } else {
    res.setHeader("Cache-Control", "no-store");
  }

  if (req.query.info !== undefined) {
    res.status(dmg ? 200 : 503).json(dmg ?? { error: "GitHub didn't answer. Try again in a minute." });
    return;
  }
  res.redirect(302, dmg ? dmg.url : FALLBACK);
}
