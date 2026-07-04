// Shared helpers for the SynchronAIse action scripts.
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

export const WORK_DIR = join(process.env.GITHUB_WORKSPACE || process.cwd(), ".synchronaise");

export function ensureWorkDir() {
  mkdirSync(WORK_DIR, { recursive: true });
  mkdirSync(join(WORK_DIR, "artifacts"), { recursive: true });
  return WORK_DIR;
}

export function writeJson(name, data) {
  ensureWorkDir();
  writeFileSync(join(WORK_DIR, name), JSON.stringify(data, null, 2), "utf8");
}

export function readJson(name, fallback = null) {
  const p = join(WORK_DIR, name);
  if (!existsSync(p)) return fallback;
  return JSON.parse(readFileSync(p, "utf8"));
}

export function log(...args) {
  console.log("[synchronaise]", ...args);
}
