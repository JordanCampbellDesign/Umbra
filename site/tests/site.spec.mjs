// End-to-end tests for umbra-mac.vercel.app. See TESTING.md for how to run them.
import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const REPO = "https://github.com/JordanCampbellDesign/Umbra";
// Checks of the server itself (redirects, headers, API) don't depend on screen size, so they run once,
// and only against a real deploy (npm run test:local serves plain files).
const local = (info) => /localhost|127\.0\.0\.1/.test(info.project.use.baseURL);
const once = (info) => info.project.name !== "desktop-chrome" || local(info);
const oneSize = (info) => info.project.name !== "desktop-chrome";
const isPhone = (info) => ["phone", "small-phone"].includes(info.project.name);

// Scroll through the page so every section reveals, then wait until no animation is running.
async function settle(page) {
  await page.evaluate(async () => {
    // "instant" beats the page's smooth scrolling, which would otherwise stop each jump partway.
    for (let y = 0; y < document.body.scrollHeight; y += innerHeight * 0.6) { scrollTo({ top: y, behavior: "instant" }); await new Promise((r) => setTimeout(r, 60)); }
  });
  // Every section has been seen, so every reveal has started. Then wait for all of them to land.
  await page.waitForFunction(() => [...document.querySelectorAll(".reveal")].every((g) => g.classList.contains("in")));
  await page.evaluate(() => scrollTo({ top: 0, behavior: "instant" }));
  await page.waitForFunction(() => document.getAnimations().every((a) => a.playState !== "running" || a.effect?.getTiming().iterations === Infinity));
}

// Collect console errors and failed requests on every page load.
test.beforeEach(async ({ page }, info) => {
  info.errors = [];
  // The local file server has no /download function, so answer the version request the way Vercel would.
  if (local(info)) {
    await page.route((url) => url.pathname === "/download" && url.searchParams.has("info"), (r) => r.fulfill({ json: { version: "9.9.9", size: 1234567, url: "https://example.com/Umbra-9.9.9.dmg" } }));
    await page.route("**/api/chat", (r) => r.fulfill({ json: { ai: false } }));
  }
  page.on("pageerror", (e) => info.errors.push(`page error: ${e.message}`));
  page.on("console", (m) => m.type() === "error" && info.errors.push(`console: ${m.text()}`));
  page.on("response", (r) => r.status() >= 400 && !r.url().includes("/api/chat") && info.errors.push(`${r.status()} ${r.url()}`));
});

test.describe("Layout at every screen size", () => {
  test("the page loads without errors", async ({ page }, info) => {
    const res = await page.goto("/");
    expect(res.status()).toBe(200);
    await expect(page).toHaveTitle(/Umbra/);
    await expect(page.locator("h1")).toHaveCount(1);
    await page.waitForLoadState("networkidle");
    expect(info.errors).toEqual([]);
  });

  test("nothing is wider than the screen", async ({ page }) => {
    await page.goto("/");
    const overflow = await page.evaluate(() => {
      const w = document.documentElement.clientWidth;
      const wide = [...document.querySelectorAll("main *, header *, footer *")]
        .filter((el) => {
          if (el.closest(".brew")) return false; // the command box scrolls sideways on purpose
          const r = el.getBoundingClientRect();
          return r.width > 0 && (r.right > w + 1 || r.left < -1) && getComputedStyle(el).position !== "fixed";
        })
        .map((el) => `${el.tagName.toLowerCase()}.${el.className}`.slice(0, 60));
      return { page: document.documentElement.scrollWidth - w, wide: [...new Set(wide)].slice(0, 5) };
    });
    expect(overflow.page, "page scrolls sideways").toBeLessThanOrEqual(0);
    expect(overflow.wide, "elements stick out past the edge").toEqual([]);
  });

  test("every image loads", async ({ page }) => {
    await page.goto("/");
    // Only images people can see; the chat's icon loads when the chat opens.
    for (const img of await page.locator("img:visible").all()) {
      await img.scrollIntoViewIfNeeded();
      await expect.poll(() => img.evaluate((i) => i.complete && i.naturalWidth > 0)).toBe(true);
    }
  });

  test("the app screenshots sit side by side on wide screens and stack on narrow ones", async ({ page }) => {
    await page.goto("/");
    const figs = page.locator(".shots figure");
    await figs.first().scrollIntoViewIfNeeded();
    await settle(page); // they fade up 60 ms apart, so measure once they've landed
    const [a, b] = [await figs.nth(0).boundingBox(), await figs.nth(1).boundingBox()];
    // Neither image may show at its full pixel size (760 and 1040 px wide).
    expect(a.width).toBeLessThanOrEqual(400);
    expect(b.width).toBeLessThanOrEqual(400);
    expect(Math.abs(a.width - b.width)).toBeLessThan(2);
    if (page.viewportSize().width > 760) {
      expect(Math.abs(a.y + a.height - (b.y + b.height)), "captions line up").toBeLessThan(2);
      expect(b.x).toBeGreaterThan(a.x + a.width);
    } else {
      expect(b.y).toBeGreaterThan(a.y + a.height);
    }
  });

  test("text stays readable", async ({ page }) => {
    await page.goto("/");
    const tiny = await page.evaluate(() =>
      [...document.querySelectorAll("p, li, summary, a, button, h1, h2, h3")]
        .filter((el) => el.offsetParent && el.textContent.trim() && parseFloat(getComputedStyle(el).fontSize) < 12)
        .map((el) => el.textContent.trim().slice(0, 40)));
    expect(tiny).toEqual([]);
    // Headings must not be cut off or overlap the next line.
    const h1 = await page.locator("h1").boundingBox();
    expect(h1.width).toBeLessThanOrEqual(page.viewportSize().width);
  });

  test("buttons are big enough to tap", async ({ page }, info) => {
    test.skip(!isPhone(info) && info.project.name !== "tablet", "touch screens only");
    await page.goto("/");
    const small = await page.evaluate(() =>
      [...document.querySelectorAll("header a, .hero a.btn, .chat-fab, #share, .cta a")]
        .filter((el) => el.offsetParent || getComputedStyle(el).position === "fixed")
        .map((el) => ({ t: el.textContent.trim() || el.getAttribute("aria-label"), h: el.getBoundingClientRect().height }))
        .filter((b) => b.h < 36));
    expect(small).toEqual([]);
  });

  test("the header fits: text links hide on phones, Download and GitHub stay", async ({ page }, info) => {
    await page.goto("/");
    await expect(page.locator("header .btn")).toBeVisible();
    await expect(page.locator("header .gh")).toBeVisible();
    const features = page.locator('header a[href="#features"]');
    if (page.viewportSize().width <= 640) await expect(features).toBeHidden();
    else await expect(features).toBeVisible();
  });

  test("full-page screenshot", async ({ page }, info) => {
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    await settle(page);
    await info.attach(`${info.project.name}.png`, { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
  });
});

test.describe("Download", () => {
  test("the buttons go to /download and show the latest version", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator(".hero a.btn")).toHaveAttribute("href", "/download");
    await expect(page.locator("[data-version]").first()).toHaveText(local(test.info()) ? "9.9.9" : /^\d+\.\d+\.\d+$/);
    await expect(page.locator("[data-size]").first()).toHaveText(/MB$/);
  });

  test("/download sends people to a real DMG", async ({ request }, info) => {
    test.skip(once(info));
    const res = await request.get("/download", { maxRedirects: 0 });
    expect(res.status()).toBe(302);
    const dmg = res.headers().location;
    expect(dmg).toMatch(new RegExp(`^${REPO}/releases/download/v\\d+\\.\\d+\\.\\d+/Umbra-.*\\.dmg$`));
    const file = await request.head(dmg);
    expect(file.status()).toBe(200);
    expect(Number(file.headers()["content-length"])).toBeGreaterThan(500_000);
  });

  test("/download?info=1 describes the release", async ({ request }, info) => {
    test.skip(once(info));
    const info1 = await (await request.get("/download?info=1")).json();
    expect(info1.version).toMatch(/^\d+\.\d+\.\d+$/);
    expect(info1.url).toContain(`/v${info1.version}/`);
  });

  test("clicking Download shows what to do next", async ({ page }) => {
    await page.goto("/");
    await page.route("**/download", (r) => r.fulfill({ status: 204 })); // don't really download in tests
    await page.locator(".hero a.btn").click();
    await expect(page.locator("#toast")).toBeVisible();
    await expect(page.locator("#toast a")).toHaveAttribute("href", "#install");
  });

  test("phones get a note, and desktops don't", async ({ page }, info) => {
    await page.goto("/");
    if (isPhone(info) || info.project.name === "tablet") {
      await expect(page.locator(".not-mac")).toBeVisible();
      await expect(page.locator("#share")).toBeVisible();
    } else {
      await expect(page.locator(".not-mac")).toBeHidden();
    }
  });

  test("the Homebrew command copies", async ({ page, context, browserName }) => {
    test.skip(browserName !== "chromium", "clipboard permissions are Chromium-only in Playwright");
    await context.grantPermissions(["clipboard-read", "clipboard-write"]);
    await page.goto("/");
    await page.locator('[data-copy="brew"]').click();
    await expect(page.locator('[data-copy="brew"]')).toHaveText("Copied");
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe("brew install --cask jordancampbelldesign/tap/umbra");
  });
});

test.describe("Brightness demo", () => {
  test("the slider dims the screens, and Night Mode dims and warms them", async ({ page }) => {
    await page.goto("/");
    const slider = page.locator("#bright");
    await slider.scrollIntoViewIfNeeded();
    await slider.fill("0");
    await expect(page.locator("#val")).toHaveText("0%");
    await expect(page.locator("#hint")).toContainText("as dark as the backlight goes");
    await expect.poll(() => page.locator(".dim").first().evaluate((d) => +getComputedStyle(d).opacity)).toBeGreaterThan(0.7);

    await slider.fill("80");
    await page.locator("label.toggle").click();
    await expect(page.locator("#val")).toHaveText("20%");
    await expect.poll(() => page.locator(".warm").first().evaluate((d) => +getComputedStyle(d).opacity)).toBeGreaterThan(0.2);
    await page.locator("label.toggle").click();
    await expect(page.locator("#val")).toHaveText("80%");
  });
});

test.describe("Help chat", () => {
  const cases = [
    ["macOS says Apple can't verify Umbra", "Apple checks apps"],
    ["my monitor won't get darker", "don't pass brightness commands"],
    ["the brightness keys do nothing", "Accessibility permission"],
    ["where did the menu bar icon go", "notch"],
    ["my screen went black", "turn every screen back on"],
    ["does it cost money", "no paid version"],
    ["will it run on my intel mac", "Apple Silicon"],
    ["it says the app is damaged", "didn't finish"],
    ["there is no open anyway button", "about an hour"],
    ["how do updates work", "checks once a day"],
  ];

  test("opens, fits the screen, and closes with Escape", async ({ page }) => {
    await page.goto("/");
    await page.locator("#chat-fab").click();
    const chat = page.locator("#chat");
    await expect(chat).toBeVisible();
    await expect(page.locator(".msg.bot").first()).toContainText("Ask me anything");
    await expect(page.locator(".chip")).toHaveCount(4);
    await expect(page.locator("#chat-input")).toBeFocused();
    const box = await chat.boundingBox(), vp = page.viewportSize();
    expect(box.x).toBeGreaterThanOrEqual(0);
    expect(box.y).toBeGreaterThanOrEqual(0);
    expect(box.x + box.width).toBeLessThanOrEqual(vp.width);
    expect(box.y + box.height).toBeLessThanOrEqual(vp.height);
    await page.keyboard.press("Escape");
    await expect(chat).toBeHidden();
    await expect(page.locator("#chat-fab")).toBeFocused();
  });

  test("answers common questions with the right help topic", async ({ page }) => {
    await page.goto("/");
    await page.locator("#chat-fab").click();
    for (const [question, expected] of cases) {
      await page.locator("#chat-input").fill(question);
      await page.locator("#chat-input").press("Enter");
      await expect(page.locator(".msg.bot").last(), question).toContainText(expected);
    }
  });

  test("says so when it doesn't know, and offers topics", async ({ page }) => {
    await page.goto("/");
    await page.locator("#chat-fab").click();
    await page.locator("#chat-input").fill("what's the weather tomorrow");
    await page.locator("#chat-input").press("Enter");
    await expect(page.locator(".msg.bot").last()).toContainText("not sure");
    await expect(page.locator(".chip")).toHaveCount(4);
  });

  test("a suggestion answers, and Open this in Help jumps to the topic", async ({ page }) => {
    await page.goto("/");
    await page.locator("#chat-fab").click();
    await page.locator(".chip", { hasText: "menu bar" }).click();
    await page.locator(".msg .more").last().click();
    await expect(page.locator("#chat")).toBeHidden();
    const topic = page.locator("#help details", { hasText: "I can't find Umbra in the menu bar" });
    await expect(topic).toHaveAttribute("open", "");
    await expect(topic).toBeInViewport();
  });

  test("the Help section's link opens the chat", async ({ page }) => {
    await page.goto("/");
    await page.locator("#help-chat").click();
    await expect(page.locator("#chat")).toBeVisible();
  });
});

test.describe("Help, questions, and credits", () => {
  test("every help and question topic opens", async ({ page }) => {
    await page.goto("/");
    const items = page.locator("details");
    expect(await items.count()).toBeGreaterThanOrEqual(15);
    for (const d of await items.all()) {
      await d.locator("summary").click();
      await expect(d).toHaveAttribute("open", "");
      await expect(d.locator("p").first()).toBeVisible();
    }
  });

  test("the page says Umbra is open source and links to GitHub", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("#oss")).toHaveText("Free and open source");
    await expect(page.locator("#open-source a", { hasText: "View on GitHub" })).toHaveAttribute("href", REPO);
    await expect(page.locator("header .gh")).toHaveAttribute("href", REPO);
    await expect(page.locator(".lede a")).toHaveText("open source");
  });

  test("the footer has the made-with-love note", async ({ page }) => {
    await page.goto("/");
    const love = page.locator("footer .love");
    await expect(love).toContainText("Made with");
    await expect(love.locator("a")).toHaveText("Jordan Campbell");
    await expect(love.locator("a")).toHaveAttribute("href", "https://www.jordancampbell.design");
  });
});

test.describe("Motion and accessibility", () => {
  test("the hero comes in one piece at a time", async ({ page }) => {
    await page.goto("/");
    const delays = await page.locator(".hero .enter").evaluateAll((els) => els.map((e) => parseFloat(getComputedStyle(e).animationDelay) * 1000));
    expect(delays.length).toBe(6);
    // 60 ms apart, in reading order: icon, headline, text, button, version, Homebrew.
    delays.forEach((d, i) => expect(Math.round(d)).toBe(i * 60));
  });

  test("sections fade up once when they scroll into view, items staggered", async ({ page }) => {
    await page.goto("/");
    const features = page.locator(".features");
    const firstCard = features.locator(".feature").first();
    expect(await firstCard.evaluate((e) => +getComputedStyle(e).opacity)).toBe(0);
    await features.scrollIntoViewIfNeeded();
    await expect(features).toHaveClass(/\bin\b/);
    await expect.poll(() => firstCard.evaluate((e) => +getComputedStyle(e).opacity)).toBe(1);
    const delays = await features.locator(".feature").evaluateAll((els) => els.slice(0, 4).map((e) => parseFloat(getComputedStyle(e).animationDelay)));
    expect(delays).toEqual([0, 0.06, 0.12, 0.18]);
    // It doesn't replay when you scroll away and back.
    await page.evaluate(() => scrollTo({ top: 0, behavior: "instant" }));
    await expect(features).toHaveClass(/\bin\b/);
  });

  test("with reduce motion on, things fade but don't move", async ({ browser }, info) => {
    test.skip(oneSize(info));
    const context = await browser.newContext({ reducedMotion: "reduce" });
    const page = await context.newPage();
    await page.goto(info.project.use.baseURL + "/");
    expect(await page.locator("h1").evaluate((e) => getComputedStyle(e).animationName)).toBe("fade-only");
    await context.close();
  });

  test("everything is readable with JavaScript off", async ({ browser }, info) => {
    test.skip(oneSize(info));
    const context = await browser.newContext({ javaScriptEnabled: false });
    const page = await context.newPage();
    await page.goto(info.project.use.baseURL + "/");
    const hidden = await page.evaluate(() => [...document.querySelectorAll("main h1, main h2, main p, .feature")]
      .filter((e) => +getComputedStyle(e).opacity < 1).map((e) => e.textContent.trim().slice(0, 30)));
    expect(hidden).toEqual([]);
    await context.close();
  });

  test("the motion follows Emil Kowalski's never-ship list", async ({ request }, info) => {
    test.skip(oneSize(info));
    const css = (await (await request.get("/")).text()).match(/<style>([\s\S]*?)<\/style>/)[1];
    expect(css, "transition: all").not.toMatch(/transition:\s*all/);
    expect(css, "scale(0) entrance").not.toMatch(/scale\(0\)/);
    expect(css, "ease-in on UI").not.toMatch(/ease-in(?!-out)/);
    // Hover movement only with a real mouse, so taps on touch screens don't trigger it.
    expect(css).toMatch(/@media \(hover: hover\) and \(pointer: fine\)/);
  });

  test("no serious accessibility problems", async ({ page }, info) => {
    test.skip(!["desktop-chrome", "phone"].includes(info.project.name));
    await page.goto("/");
    await settle(page);
    const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze();
    const serious = results.violations.filter((v) => ["serious", "critical"].includes(v.impact))
      .map((v) => `${v.id}: ${v.nodes.slice(0, 3).map((n) => n.target.join(" ")).join(", ")}`);
    expect(serious).toEqual([]);
  });

  test("the chat has no serious accessibility problems", async ({ page }, info) => {
    test.skip(once(info));
    await page.goto("/");
    await page.locator("#chat-fab").click();
    const results = await new AxeBuilder({ page }).include("#chat").analyze();
    expect(results.violations.filter((v) => ["serious", "critical"].includes(v.impact)).map((v) => v.id)).toEqual([]);
  });

  test("people who prefer less motion get a paused video with controls", async ({ browser }, info) => {
    test.skip(once(info));
    const context = await browser.newContext({ reducedMotion: "reduce" });
    const page = await context.newPage();
    await page.goto(info.project.use.baseURL + "/");
    const video = page.locator("video");
    await expect(video).toHaveJSProperty("controls", true);
    await expect(video).toHaveJSProperty("paused", true);
    await context.close();
  });

  test("keyboard users can skip to the content", async ({ page, browserName }, info) => {
    test.skip(isPhone(info) || info.project.name === "tablet", "no keyboard");
    await page.goto("/");
    // Safari only moves to links with Option-Tab unless "Press Tab to highlight each item" is on.
    await page.keyboard.press(browserName === "webkit" ? "Alt+Tab" : "Tab");
    await expect(page.locator(".skip")).toBeFocused();
    await expect(page.locator(".skip")).toBeInViewport();
  });
});

test.describe("Server", () => {
  test.beforeEach(async ({}, info) => test.skip(once(info)));

  test("a missing page shows the branded 404", async ({ page }) => {
    const res = await page.goto("/this-page-does-not-exist");
    expect(res.status()).toBe(404);
    await expect(page.locator("h1")).toHaveText("This page is in the dark");
    await expect(page.locator('a[href="/download"]')).toBeVisible();
  });

  test("short links redirect", async ({ request }) => {
    const cases = { "/help": "/#help", "/install": "/#install", "/dmg": "/download", "/github": REPO };
    for (const [from, to] of Object.entries(cases)) {
      const res = await request.get(from, { maxRedirects: 0 });
      expect([307, 308], from).toContain(res.status());
      expect(res.headers().location, from).toContain(to);
    }
  });

  test("the old address redirects to the new one", async ({ request }) => {
    const res = await request.get("https://umbra-chi-six.vercel.app/download", { maxRedirects: 0 });
    expect(res.status()).toBe(308);
    expect(res.headers().location).toBe("https://umbra-mac.vercel.app/download");
  });

  test("security headers are set", async ({ request }) => {
    const h = (await request.get("/")).headers();
    expect(h["x-content-type-options"]).toBe("nosniff");
    expect(h["x-frame-options"]).toBe("DENY");
    expect(h["referrer-policy"]).toBe("strict-origin-when-cross-origin");
  });

  test("the chat API reports its status and rejects bad requests", async ({ request }) => {
    const status = await (await request.get("/api/chat")).json();
    expect(typeof status.ai).toBe("boolean");
    const empty = await request.post("/api/chat", { data: { messages: [] } });
    expect(status.ai ? 400 : 501).toBe(empty.status());
    expect((await request.put("/api/chat")).status()).toBe(405);
  });

  test("robots.txt keeps the API out of search", async ({ request }) => {
    expect(await (await request.get("/robots.txt")).text()).toContain("Disallow: /api/");
  });
});
