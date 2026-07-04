import { defineConfig, devices } from "@playwright/test";

// Pinned, headless Chromium for deterministic CI snapshots.
export default defineConfig({
  use: {
    ...devices["Desktop Chrome"],
    headless: true,
    viewport: { width: 640, height: 480 },
    deviceScaleFactor: 2,
  },
  expect: { timeout: 10_000 },
  timeout: 60_000,
});
