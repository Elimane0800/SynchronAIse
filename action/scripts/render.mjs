// Render each changed component in a real browser and capture a PNG snapshot.
// The demo repo serves a render harness at RENDER_URL that mounts a component
// by name (e.g. RENDER_URL/?component=StatusCard) inside #root.
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { chromium } from "playwright";
import { WORK_DIR, ensureWorkDir, readJson, writeJson, log } from "./lib.mjs";

const RENDER_URL = process.env.RENDER_URL || "http://localhost:4173";
const TOKENS_PATH = process.env.TOKENS_PATH || "src/tokens.json";

function componentName(file) {
  return file.split(/[\\/]/).pop().replace(/\.tsx$/, "");
}

function readTokens() {
  const p = join(process.env.GITHUB_WORKSPACE || process.cwd(), TOKENS_PATH);
  return existsSync(p) ? JSON.parse(readFileSync(p, "utf8")) : {};
}

async function main() {
  ensureWorkDir();
  const { files } = readJson("changed.json", { files: [] });
  if (!files.length) {
    log("no changed components to render.");
    writeJson("render.json", { components: [] });
    return;
  }

  const tokens = readTokens();
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 640, height: 480 } });
  const components = [];

  for (const file of files) {
    const name = componentName(file);
    const url = `${RENDER_URL}/?component=${encodeURIComponent(name)}`;
    log("rendering", name, "->", url);
    await page.goto(url, { waitUntil: "networkidle" });
    const target = page.locator("[data-node='card']").first();
    const shotPath = join(WORK_DIR, "artifacts", `${name}.png`);
    await target.screenshot({ path: shotPath });
    const b64 = readFileSync(shotPath).toString("base64");
    const code = existsSync(file) ? readFileSync(file, "utf8") : "";
    components.push({ name, file, screenshot_b64: b64, code, tokens });
  }

  await browser.close();
  writeJson("render.json", { components });
  log(`rendered ${components.length} component(s).`);
}

main().catch((err) => {
  log("render failed:", err);
  // Soft-fail: write empty result so downstream steps still post a comment.
  writeJson("render.json", { components: [] });
});
