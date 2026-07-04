// Detect which component files changed in this PR, so we audit only the diff
// (no spam on unrelated pushes). Falls back to a directory walk if git diff is
// unavailable. Avoids fs.globSync so it runs on Node 20+.
import { execSync } from "node:child_process";
import { readdirSync } from "node:fs";
import { join } from "node:path";
import { writeJson, log } from "./lib.mjs";

const COMPONENT_GLOB = process.env.COMPONENT_GLOB || "src/components/**/*.tsx";
const BASE = process.env.BASE_SHA;
const HEAD = process.env.HEAD_SHA;

// Derive the root directory to walk from the glob (portion before the wildcard).
const GLOB_ROOT = COMPONENT_GLOB.split("*")[0].replace(/\/$/, "") || "src";

function fromGit() {
  if (!BASE || !HEAD) return null;
  try {
    const out = execSync(`git diff --name-only ${BASE} ${HEAD}`, { encoding: "utf8" });
    return out
      .split("\n")
      .map((l) => l.trim())
      .filter((f) => f.endsWith(".tsx") && f.toLowerCase().includes("component"));
  } catch (err) {
    log("git diff failed, walking directory instead:", err.message);
    return null;
  }
}

function walk(dir, acc = []) {
  let entries = [];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return acc;
  }
  for (const entry of entries) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, acc);
    else if (entry.name.endsWith(".tsx")) acc.push(full);
  }
  return acc;
}

const changed = fromGit() ?? walk(GLOB_ROOT);
log("changed components:", changed);
writeJson("changed.json", { files: changed });
