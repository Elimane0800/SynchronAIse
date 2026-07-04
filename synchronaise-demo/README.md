# SynchronAIse Demo Repo

The repo the judges browse. It hosts the **hero component** (`StatusCard`), the
**design tokens**, and the **6 drift cases** as real open PRs. On every PR the
[SynchronAIse Action](../synchronaise/action) renders the changed component,
audits it, and posts an AI-generated comment.

## Hero component

`src/components/StatusCard.tsx` - icon + title + description + action button, with
`default` / `warning` / `danger` variants. Every element carries a stable
`data-node` id (`card`, `icon`, `content`, `title`, `description`, `btn-primary`)
that the audit uses to link findings to graph nodes.

## Design tokens

`src/tokens.css` (runtime) + `src/tokens.json` (machine-readable, sent to the
audit service). ~20 tokens across color / spacing / radius / typography /
elevation.

## The 6 drift cases

Each is a real open PR; `ground-truth/pr-N.json` holds the expected classification
(used to measure real accuracy for the pitch).

| PR | Change | Expected class |
| --- | --- | --- |
| 1 | Hardcoded `#ef4444` instead of `var(--color-danger)` | design_violation |
| 2 | `15px` padding instead of `16px` (`spacing-md`) | design_violation |
| 3 | Wrapper `div` for scroll/flex handling | technical_noise (ignored) |
| 4 | Component rebuilt from scratch mimicking StatusCard | design_violation (rogue) |
| 5 | New secondary button absent from Figma | intentional_evolution |
| 6 | Cases 1 + 3 combined | mixed |

## Render harness (CI)

`npm run build && npm run preview` serves `/?component=StatusCard`. The Action
screenshots the `[data-node='card']` element for the audit.

## Setup

```bash
npm install
npm run dev        # local preview at http://localhost:5174
```

Configure repo secrets/variables for the workflow:

- `secrets.AUDIT_API_URL` - the deployed audit service base URL.
- `vars.STUDIO_BASE_URL` - the deployed Studio base URL (for report links).
