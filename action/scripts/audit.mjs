// POST each rendered component to the audit service and store the returned
// payload for the comment step. Uses Node 20 built-in fetch.
import { readJson, writeJson, log } from "./lib.mjs";

const AUDIT_API_URL = (process.env.AUDIT_API_URL || "").replace(/\/$/, "");
const PR_NUMBER = Number(process.env.PR_NUMBER || 0);
const RUN_NUMBER = Number(process.env.RUN_NUMBER || 1);

async function auditOne(component) {
  const res = await fetch(`${AUDIT_API_URL}/audit`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      pr_number: PR_NUMBER,
      run: RUN_NUMBER,
      file_path: component.file,
      code: component.code,
      screenshot_b64: component.screenshot_b64,
      tokens: component.tokens || {},
    }),
  });
  if (!res.ok) {
    throw new Error(`audit ${component.name} -> HTTP ${res.status}: ${await res.text()}`);
  }
  return res.json();
}

async function main() {
  if (!AUDIT_API_URL) throw new Error("AUDIT_API_URL is required.");
  const { components } = readJson("render.json", { components: [] });
  const audits = [];
  for (const component of components) {
    try {
      const payload = await auditOne(component);
      log(`audited ${component.name}: drift ${payload.drift_score}, ${payload.findings.length} finding(s).`);
      audits.push(payload);
    } catch (err) {
      log("audit failed for", component.name, "-", err.message);
    }
  }
  writeJson("audit.json", { audits });
}

main().catch((err) => {
  log("audit step failed:", err.message);
  writeJson("audit.json", { audits: [] });
});
