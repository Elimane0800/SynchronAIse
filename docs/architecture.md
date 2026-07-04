# SynchronAIse - Architecture

This document shows the building blocks of SynchronAIse and how they interact.
For a high-level overview and run instructions, see the [README](../README-2.md).

## The loop

> **push → snapshot → classification → feedback → fix in Cursor → green.**

## Building blocks

```mermaid
flowchart TB
    Dev["Developer"]

    subgraph demo [Demo Repo · synchronaise-demo]
        StatusCard["StatusCard.tsx<br/>(data-node ids)"]
        Tokens["tokens.css / tokens.json"]
        Render_Harness["render harness<br/>/?component=StatusCard"]
        Workflow[".github/workflows/audit.yml"]
        GroundTruth["ground-truth/pr-1..6.json"]
    end

    subgraph action [GitHub Action · action/]
        Changed["changed-files.mjs"]
        Render["render.mjs<br/>(Playwright snapshot)"]
        AuditCall["audit.mjs"]
        CommentPost["comment.mjs<br/>(create/update PR comment)"]
        Changed --> Render --> AuditCall --> CommentPost
    end

    subgraph backend [Backend · FastAPI]
        AuditEP["POST /audit"]
        ReportEP["GET /report/{id}"]
        FixEP["POST /fix"]
        subgraph engine [Taste Engine]
            TreeBuilder["tree_builder<br/>code_parser + figma_parser"]
            Classifier["classifier"]
            VLM["vlm<br/>Gemini -> OpenAI -> heuristic"]
            Patch["patch"]
            TreeBuilder --> Classifier --> VLM
        end
        Storage["storage<br/>(audit by audit_id)"]
        AuditEP --> TreeBuilder
        Classifier --> Storage
        AuditEP --> Storage
        ReportEP --> Storage
        FixEP --> Patch
    end

    Contract["Frozen JSON Contract<br/>packages/contract + mocks"]

    subgraph studio [Frontend · Graph Reconciliation Studio]
        Client["api/client.ts"]
        GraphView["GraphView<br/>(react-flow + dagre)"]
        Panel["ExplanationPanel"]
        PromptBox["PromptBox"]
        DriftScore["DriftScore"]
        Client --> GraphView
        Client --> Panel
        Panel --> PromptBox
    end

    Dev -->|"push PR"| StatusCard
    Workflow --> Changed
    StatusCard -.->|"rendered by"| Render
    Tokens -.->|"sent with code"| AuditCall
    AuditCall -->|"code + snapshot + tokens"| AuditEP
    Storage -->|"audit payload"| AuditCall
    CommentPost -->|"reasoning + cursor_patch + Studio link"| PR["PR Comment"]

    Contract -.->|"validates"| AuditEP
    Contract -.->|"mirrors types"| Client

    PR -->|"Studio link"| Client
    Client -->|"GET /report/{id}"| ReportEP
    PromptBox -->|"node + NL prompt"| FixEP
    FixEP -->|"CursorPatch"| PromptBox

    PR -->|"apply patch in Cursor"| Dev
    PromptBox -->|"apply patch in Cursor"| Dev
    GroundTruth -.->|"scored by metrics.py"| Classifier
```

## Key interactions

- **The loop:** `push → changed-files → render (Playwright) → /audit → store → PR comment → fix in Cursor → green`.
- **The contract is the spine:** [`packages/contract`](../packages/contract) validates the backend responses and mirrors the frontend TS types, so the Action, Studio, and metrics all read one shape.
- **The Taste Engine degrades gracefully:** `Gemini → OpenAI → deterministic heuristic`, always returning a valid payload so CI and demos are never blocked.
- **Two entry points for fixes:** the PR comment's `cursor_patch`, and the Studio's `PromptBox → /fix` - both produce a patch, neither auto-commits.
- **Ground truth** feeds `metrics.py` to produce the real pitch numbers, separate from the live serving path.

## Component map

| Path | Role | What it is |
| --- | --- | --- |
| [`packages/contract`](../packages/contract) | all | The frozen JSON contract that drives everything. |
| [`backend`](../backend) | R3 + R1 | FastAPI audit service + the Taste Engine. |
| [`action`](../action) | R4 | The reusable GitHub Action (render → audit → comment). |
| [`frontend`](../frontend) | R5 | The Graph Reconciliation Studio (React + react-flow). |
| [`synchronaise-demo`](../synchronaise-demo) | R2 | Hero `StatusCard`, tokens, and the 6 drift PRs. |
