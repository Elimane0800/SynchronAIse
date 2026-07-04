// Format the audit into a PR comment and create-or-update it (no spam on
// re-push). If no audit is available it posts the walking-skeleton comment,
// which is enough to prove the token + trigger + permissions in hour one.
import { readJson, log } from "./lib.mjs";

const MARKER = "<!-- synchronaise-audit -->";
const TOKEN = process.env.GITHUB_TOKEN;
const REPO = process.env.GITHUB_REPOSITORY;
const PR_NUMBER = Number(process.env.PR_NUMBER || 0);
const STUDIO = (process.env.STUDIO_BASE_URL || "").replace(/\/$/, "");

const api = (path, init = {}) =>
  fetch(`https://api.github.com${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${TOKEN}`,
      accept: "application/vnd.github+json",
      "content-type": "application/json",
      ...(init.headers || {}),
    },
  });

const CLASS_EMOJI = {
  design_violation: "🔴",
  technical_noise: "⚪",
  intentional_evolution: "🟡",
  aligned: "🟢",
};

function renderFinding(f) {
  const studioLink = STUDIO ? ` · [open in Studio](${STUDIO}/#/report/AUDIT_ID)` : "";
  return [
    `#### ${CLASS_EMOJI[f.classification] || "🔴"} ${f.type} — \`${f.location}\``,
    "",
    `**Expected:** \`${f.expected}\`  |  **Actual:** \`${f.actual}\`  |  **Severity:** ${f.severity}`,
    "",
    `> ${f.reasoning}`,
    "",
    "**Cursor patch**",
    "",
    "```diff",
    f.cursor_patch.diff,
    "```",
    "",
    `_Prompt:_ ${f.cursor_patch.prompt}${studioLink}`,
    "",
  ].join("\n");
}

function renderAudit(a) {
  const lines = [];
  const link = STUDIO ? `[View in Graph Reconciliation Studio](${STUDIO}/#/report/${a.audit_id})` : "";
  lines.push(`### PR #${a.pr_number} · drift score \`${a.drift_score}\` ${link}`);
  lines.push("");

  if (a.findings.length) {
    lines.push(`**${a.findings.length} design violation(s)**`, "");
    for (const f of a.findings) lines.push(renderFinding(f).replaceAll("AUDIT_ID", a.audit_id));
  } else {
    lines.push("✅ No design violations. Graphs aligned.", "");
  }

  if (a.ignored_as_noise.length) {
    lines.push("<details><summary>⚪ Ignored as technical noise (the taste moment)</summary>", "");
    for (const n of a.ignored_as_noise) lines.push(`- \`${n.element}\` — ${n.reasoning}`);
    lines.push("", "</details>", "");
  }

  if (a.evolution_proposals.length) {
    lines.push("<details><summary>🟡 Intentional evolution — reconcile, don't roll back</summary>", "");
    for (const e of a.evolution_proposals) lines.push(`- \`${e.element}\` — ${e.reasoning}\n  - _Proposal:_ ${e.proposal}`);
    lines.push("", "</details>", "");
  }
  return lines.join("\n");
}

function buildBody() {
  const { audits } = readJson("audit.json", { audits: [] });
  const header = `${MARKER}\n## 🎨 SynchronAIse — Automated Design Audit\n`;
  if (!audits.length) {
    return `${header}\n_Walking skeleton: the Action is wired and permissions are proven. Awaiting the audit service._`;
  }
  return header + "\n" + audits.map(renderAudit).join("\n---\n");
}

async function findExisting() {
  const res = await api(`/repos/${REPO}/issues/${PR_NUMBER}/comments?per_page=100`);
  if (!res.ok) return null;
  const comments = await res.json();
  return comments.find((c) => (c.body || "").includes(MARKER)) || null;
}

async function main() {
  if (!TOKEN || !REPO || !PR_NUMBER) {
    log("missing GITHUB_TOKEN/REPOSITORY/PR_NUMBER; printing comment instead:\n");
    console.log(buildBody());
    return;
  }
  const body = buildBody();
  const existing = await findExisting();
  const res = existing
    ? await api(`/repos/${REPO}/issues/comments/${existing.id}`, {
        method: "PATCH",
        body: JSON.stringify({ body }),
      })
    : await api(`/repos/${REPO}/issues/${PR_NUMBER}/comments`, {
        method: "POST",
        body: JSON.stringify({ body }),
      });
  log(existing ? "updated existing comment" : "created new comment", "->", res.status);
}

main().catch((err) => {
  log("comment step failed:", err.message);
  process.exitCode = 0; // never fail the PR on comment issues
});
