// A tiny static server for testing the site before it's deployed: npm run test:local
// It serves the files as they are. Vercel-only parts (/download, /api, redirects, headers) are tested against a deploy.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(fileURLToPath(import.meta.url), "..", "..");
const types = { ".html": "text/html", ".png": "image/png", ".jpg": "image/jpeg", ".mp4": "video/mp4", ".txt": "text/plain", ".js": "text/javascript", ".json": "application/json" };
const port = Number(process.env.PORT || 4321);

createServer(async (req, res) => {
  let path = normalize(decodeURIComponent(new URL(req.url, "http://x").pathname)).replace(/^(\.\.[/\\])+/, "");
  if (path.endsWith("/")) path += "index.html";
  try {
    const body = await readFile(join(root, path));
    res.writeHead(200, { "Content-Type": types[extname(path)] || "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404, { "Content-Type": "text/html" });
    res.end(await readFile(join(root, "404.html")));
  }
}).listen(port, () => console.log(`Serving the site at http://localhost:${port}`));
