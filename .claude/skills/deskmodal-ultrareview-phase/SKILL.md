---
name: deskmodal-ultrareview-phase
description: Fire /ultrareview cloud fleet at a logical-impact-batch boundary. Per quality.md §18.7.1 Tier C cadence + F157 Layer 12 cost-control. Replaces local-reviewer-pod load.
when_to_use: A logical-impact batch (3-6 waves spanning a coherent capability) just integrated; pre-push or pre-PR
disable-model-invocation: true
effort: medium
---

# DeskModal phase-boundary ultrareview

F157 Layer 6 — leverages Claude Code's `/ultrareview` (W17 docs primitive, 20 Apr 2026). Runs a cloud fleet of adversarial review agents in parallel; findings stream back automatically.

## When to invoke

Per `quality.md §18.7.1` Tier C cadence:
- A coherent capability surface has landed across N waves (e.g., F140-A W1+W2+W3+W4 = "collab end-to-end")
- F156 Phase 1 ABOVE is complete
- About to push to main or open PR

## When NOT to invoke

- Per-wave (use local reviewer pod per `quality.md §7`)
- Pre-impl (the reviewer matrix lives at integration boundary)
- For small markdown-only commits (waste)

## How

Invoke `/ultrareview` (built-in Claude Code skill). The fleet:
- Spawns multiple cloud-based bug-hunting agents
- Each agent applies a distinct lens (security / performance / FDC3 conformance / a11y / trading-domain correctness)
- Findings auto-stream back to the CLI / Desktop
- Quota is cloud-allocated; doesn't compete with local sessions

## Output handling

Each finding either:
- **CLOSED-IN-WAVE** — fixed via follow-up commit in this session
- **SCOPE-TRANSFERRED-TO-{wave}** — named receiver wave per `quality.md §18.1`
- **ESCALATED-TO-USER** — pause for user decision

Update the parent spec's `§Open concerns` table per `architecture.md §21` spec-hygiene.

## Cost note

`/ultrareview` IS a paid cloud-fleet — billed separately. Reserve for boundary moments; never per-wave.
