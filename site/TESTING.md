# Testing the website

The site at [umbra-mac.vercel.app](https://umbra-mac.vercel.app) has end-to-end tests. They open the real page in real browsers, click through it the way a visitor would, and check the results. They use [Playwright](https://playwright.dev).

## Run the tests

Run these commands in the `site` folder.

1. Install the tools. You only do this once.
   ```bash
   npm install
   npx playwright install chromium webkit
   ```
2. Test your changes before you push. This serves the files on your Mac:
   ```bash
   npm run test:local
   ```
3. Test the live site after a deploy:
   ```bash
   npm test
   ```
4. Open the report, with a full-page screenshot for every screen size:
   ```bash
   npm run test:report
   ```

To test a different deploy, set its address:

```bash
BASE_URL=https://umbra-abc123.vercel.app npm test
```

To test only phones, run `npm run test:phone`. To test one area, use `-g`, for example `npx playwright test -g "Help chat"`.

## Screen sizes and browsers

Every test runs at each of these sizes, unless it only applies to some of them.

| Name | Size | Browser |
|---|---|---|
| desktop-chrome | 1440 × 900 | Chrome |
| desktop-safari | 1440 × 900 | Safari (WebKit) |
| large-monitor | 1920 × 1080 | Chrome |
| small-laptop | 1024 × 700 | Chrome |
| tablet | iPad Mini, 768 × 1024 | Safari (WebKit) |
| phone | iPhone 13, 390 × 844 | Safari (WebKit) |
| small-phone | iPhone SE, 320 × 568 | Safari (WebKit) |

Safari gets the most sizes, because most people who visit a Mac app's site use a Mac or an iPhone.

## What the tests check

**Layout at every size**
- The page loads with no errors in the console and no failed requests.
- Nothing is wider than the screen, and the page never scrolls sideways.
- Every visible image loads, and no text is smaller than 12 px.
- On phones and tablets, every button and header link is at least 36 px tall, so it's easy to tap.
- On screens 640 px wide or less, the header shows only the logo, GitHub, and Download.
- Each run saves a full-page screenshot for each size in the report.

**Download**
- The buttons go to `/download`, and the page shows the latest version and file size.
- `/download` redirects to a real DMG on GitHub that's larger than 500 KB.
- After a click, a note appears with a link to the install steps.
- Phones and tablets see "Umbra is a Mac app" and a button to send the link to a Mac. Desktops don't.
- The Homebrew command copies to the clipboard (Chrome only).

**Brightness demo**
- At 0%, the screens dim and the hint explains the extra slider.
- Night Mode drops brightness to 20% and warms the colors. Turning it off brings back 80%.

**Help chat**
- The chat opens, fits inside the screen, puts the cursor in the text box, and closes with Escape.
- Ten common questions, written the way people ask them, each get the right help topic. For example, "Apple can't verify Umbra" gets the Open Anyway steps.
- An off-topic question gets "not sure" and suggested topics.
- "Open this in Help" closes the chat and scrolls to the topic.

**Help, questions, and credits**
- Every help and question topic opens.
- The page says Umbra is open source, and the GitHub links point to the repository.
- The footer says "Made with ♥ by Jordan Campbell" and links to jordancampbell.design.

**Accessibility and motion**
- An automatic scan ([axe](https://github.com/dequelabs/axe-core)) finds no serious WCAG 2.1 AA problems on desktop, on a phone, or in the open chat.
- With "Reduce motion" on, the video starts paused and shows its controls.
- The first Tab key press focuses "Skip to content". In Safari this is Option-Tab.

**Server (live deploys only, run once)**
- A missing page returns 404 with the branded page.
- `/help`, `/install`, `/dmg`, and `/github` redirect to the right place.
- The old address, umbra-chi-six.vercel.app, redirects to umbra-mac.vercel.app.
- Security headers are set: `nosniff`, `DENY` for frames, and a referrer policy.
- The chat API reports whether AI is on and rejects bad requests.
- `robots.txt` keeps `/api/` out of search results.

`npm run test:local` skips the server checks, because a folder of files has no `/download` function, redirects, or headers. It answers the version request with a stand-in (9.9.9) and checks that the page shows it.

## Automatic runs

The **Website tests** GitHub Action (`.github/workflows/site-e2e.yml`) runs the full suite against the live site:

- after every production deploy from Vercel,
- once a day, which catches problems like a broken download link or GitHub being down, and
- when you start it by hand on the Actions tab.

When a run fails, the Action saves the report with screenshots and traces. Open the run, then download **playwright-report** under Artifacts.

## Bugs these tests found

These were fixed before the tests were added to the repository:

- The closed chat panel was invisible but still on the page, so screen readers could read it. The panel's own style overrode the `hidden` attribute.
- On phones, the chat button had no name for screen readers, because its text label is hidden at that size.
- The Homebrew command box scrolled sideways on phones, but keyboard users couldn't reach it.
- The header links were 23 px tall on tablets and the logo link was 32 px on phones, which is too small to tap reliably.
- The chat's text box label shared a class with the "Skip to content" link.

## Add a test

Tests live in `tests/site.spec.mjs`, grouped by area. Write test names as plain sentences that say what a visitor should see, like `"the slider dims the screens"`. When a check doesn't depend on screen size, such as a redirect, skip it on every size but one with `test.skip(once(info))`.
