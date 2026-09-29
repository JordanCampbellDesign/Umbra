// End-to-end tests for the Umbra website. See TESTING.md.
// Runs against the live site by default. Point it at a preview deploy with BASE_URL=https://....vercel.app
import { defineConfig, devices } from "@playwright/test";

const BASE_URL = process.env.BASE_URL || "https://umbra-mac.vercel.app";
const LOCAL = /localhost|127\.0\.0\.1/.test(BASE_URL);

export default defineConfig({
  testDir: "tests",
  timeout: 30_000,
  expect: { timeout: 8_000 },
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: [["list"], ["html", { open: "never", outputFolder: "test-results/report" }]],
  outputDir: "test-results/artifacts",
  // npm run test:local starts a small file server first.
  webServer: LOCAL ? { command: "node tests/serve.mjs", url: BASE_URL, reuseExistingServer: true } : undefined,
  use: { baseURL: BASE_URL, trace: "retain-on-failure", screenshot: "only-on-failure" },
  // One project per screen size. Most visitors are on a Mac, so Safari's engine (WebKit) gets the desktop and phone sizes.
  projects: [
    { name: "desktop-chrome", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } } },
    { name: "desktop-safari", use: { ...devices["Desktop Safari"], viewport: { width: 1440, height: 900 } } },
    { name: "large-monitor", use: { ...devices["Desktop Chrome"], viewport: { width: 1920, height: 1080 } } },
    { name: "small-laptop", use: { ...devices["Desktop Chrome"], viewport: { width: 1024, height: 700 } } },
    { name: "tablet", use: { ...devices["iPad Mini"] } },
    { name: "phone", use: { ...devices["iPhone 13"] } },
    { name: "small-phone", use: { ...devices["iPhone SE"] } },
  ],
});
