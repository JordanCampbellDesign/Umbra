// Sends people straight to the newest Umbra DMG, so the site never needs an edit after a release.
// GET /download        -> 302 to the DMG on GitHub
// GET /download?info=1 -> {"version":"1.0.3","size":1066802,"url":"..."} for the page's version label
const REPO = "JordanCampbellDesign/Umbra";
const FALLBACK = `https://github.com/${REPO}/releases/latest`;

export default async function handler(req, res) {
  let release = null;
  try {
    const r = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: "application/vnd.github+json", "User-Agent": "umbra-site" },
    });
    if (r.ok) release = await r.json();
  } catch {}

  const dmg = release?.assets?.find((a) => a.name.endsWith(".dmg"));
  // Cache at Vercel's edge for 10 minutes, so GitHub's rate limit is never an issue.
  res.setHeader("Cache-Control", "public, s-maxage=600, stale-while-revalidate=86400");

  if (req.query.info !== undefined) {
    res.status(dmg ? 200 : 503).json(
      dmg ? { version: release.tag_name.replace(/^v/, ""), size: dmg.size, url: dmg.browser_download_url } : { error: "unavailable" },
    );
    return;
  }
  res.redirect(302, dmg ? dmg.browser_download_url : FALLBACK);
}
