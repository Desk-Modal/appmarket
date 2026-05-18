---
name: deskmodal-verify-tier-b
description: Phase-boundary Tier B verification — scripts/local-ci.sh --fast. Per quality.md §18.7.1. Use ONCE after a logical-impact batch of waves integrates (not per-wave).
when_to_use: Logical-impact batch integrated (e.g., F156-P1 A+C+D landed); need workspace-wide affected-gate verification
disable-model-invocation: true
allowed-tools: Bash(scripts/local-ci.sh*) Bash(git log:*)
effort: medium
---

# DeskModal Tier B verification

F157 Layer 2 — phase-boundary verification per `quality.md §18.7.1`. Costs ~2-5 min wall-clock.

## What's been landing

!`git log --oneline -10`

## Instructions

Run `scripts/local-ci.sh --fast`. This runs:
- All BLOCKING audit gates workspace-wide
- All affected Cargo crates' fmt + clippy + test
- All affected Nx projects' lint + typecheck + test
- Hook regression tests
- `scripts/prod-check.sh --fast`

If rc=0 → phase boundary verified, ready for next wave-batch.
If rc≠0 → diagnose; fix in a fix-forward commit (NEVER `git reset` per `parallelism.md §15`).

## When NOT to invoke

- Per-wave (use `/deskmodal-verify-tier-a` instead)
- Pre-push (use `/deskmodal-verify-tier-c` for `--full --sign`)
- Docs-only commits (Tier A on changed scope only)

## Output

```
Tier B (quality.md §18.7.1):
  scripts/local-ci.sh --fast: rc=0 (durations per-gate)
  → Phase boundary GREEN. Proceed to next wave-batch.
```
