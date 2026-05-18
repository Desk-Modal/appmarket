---
name: deskmodal-cloud-lane
description: Dispatch a cloud research lane via RemoteTrigger / Routines with a self-contained brief per architecture.md §31.1. Offloads markdown / docs / research work without burning local API quota.
when_to_use: Research / markdown-polish / spec-suggest / competitor-audit / docs-currency work that can run on a fresh cloud clone with bounded write-set
disable-model-invocation: true
allowed-tools: Bash(scripts/session-mesh/*)
effort: high
---

# DeskModal cloud-lane dispatch

F157 Layer 7 / Layer 12 — research offload to avoid local API saturation (per `feedback_api_load_concurrent_agents` 2026-05-18 incident).

## Mesh state

!`bash ${CLAUDE_SKILL_DIR}/../../../scripts/session-mesh/check-concurrency.sh`

## When to use cloud lanes (per architecture.md §31.1)

Cloud lanes ARE for:
- Markdown / doc / spec polish
- CSS / design-token audits
- Perf baseline captures
- Research / competitor analysis / SOTA scans
- Pre-captured-artefact-based audits (e.g., visual-critique against pre-captured playwright snapshots)

Cloud lanes are NOT for:
- Source-file edits (`.rs` / `.ts` / `.tsx` / `.py` / `.toml`)
- Canonical-file edits (`.claude/rules/**`, `CLAUDE.md`, `.mcp.json`, `.specify/memory/**`)
- Cross-stack impl requiring GUI verification
- Tauri IPC changes (needs local verification)

## Brief contract (every cloud lane MUST satisfy)

Per `architecture.md §31.1`:
- **Fresh-clone start** — no CBM cache continuity
- **Bounded write-set** — declared explicitly; audited at orchestrator-pull-time
- **Self-contained brief** — every fact inlined (file paths, requirements, citations); no CBM queries
- **No source edits** — `.rs` / `.tsx` / `.ts` / `.py` / `.toml` forbidden
- **Push to main** — direct push via `git pull --rebase` (3 retries); no PR shape

## Instructions

Construct a brief that:
1. Names the deliverable file path explicitly (under `specs/<NNN>/research/<topic>-<date>.md`)
2. Lists every source path the lane should read (no CBM-only references)
3. Cites the SOTA criteria + scope by section
4. Includes the verification command (`bash scripts/wiki-lint.sh` or `wc -l <deliverable>`)
5. Includes the commit + push protocol with rebase-retry

Use the `schedule` skill (bundled) OR direct `RemoteTrigger create` to dispatch.

## Output

A self-contained brief ready to paste into the cloud lane's prompt.
