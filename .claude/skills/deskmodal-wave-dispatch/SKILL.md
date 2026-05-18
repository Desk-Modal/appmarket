---
name: deskmodal-wave-dispatch
description: Plan and dispatch a wave of parallel impl agents with disjoint write-sets. Use when starting a new wave under /goal-driven autonomous delivery. Honours the 3-cap concurrent agents per feedback_api_load_concurrent_agents and the mesh claim/check protocol per F157 Layer 11.
when_to_use: Starting a new wave; have ≥2 candidate tasks with potentially disjoint write-sets; want parallel dispatch
disable-model-invocation: true
allowed-tools: Bash(scripts/session-mesh/*) Bash(scripts/audit-wave-write-sets.sh*) Bash(git status:*) Bash(git diff:*) Bash(git log:*) Agent
effort: xhigh
---

# DeskModal wave-dispatch skill

F157 Layer 2 helper — plans and dispatches a wave of parallel impl agents while respecting all DeskModal disciplines.

## Current mesh state

!`bash ${CLAUDE_SKILL_DIR}/../../../scripts/session-mesh/check-concurrency.sh`

## Recent findings from other sessions

!`bash ${CLAUDE_SKILL_DIR}/../../../scripts/session-mesh/list-findings.sh --since 24 --from-others`

## Git baseline

!`git log --oneline -3 2>/dev/null`
!`git status --short 2>/dev/null | head -10`

## Instructions

The user invoked this skill to dispatch a wave. Arguments: `$ARGUMENTS`.

Plan the wave following this checklist (per `parallelism.md §4`, `architecture.md §28-§32`, `quality.md §18.7`, `feedback_api_load_concurrent_agents`):

1. **Identify candidate tasks.** Read `.session-state/handoffs/<feature>.md` + the active spec's §6 wave plan. Pick 2-3 tasks with bounded scope.

2. **Declare write-sets per task.** Each task explicitly cites `Reads:` and `Writes:` per `parallelism.md §4`.

3. **Verify pairwise-disjoint write-sets.** If unsure, call `bash scripts/audit-wave-write-sets.sh` (when present). If write-sets overlap → single-agent OR serial-pair, NOT pod.

4. **Cap concurrency at 3.** Per `feedback_api_load_concurrent_agents`: empirical ceiling is 3 concurrent Opus 4.7 agents on large-context tasks. Mesh enforces via `subagent-start-bound-budget.sh` hook.

5. **Audit-by-path dispatch.** Pass file paths in the prompt, not inline excerpts (per `architecture.md §28.5`). Saves 30-80K tokens per agent × N parallel.

6. **Dispatch in ONE message.** Multiple `Agent` tool calls in a single assistant turn = parallel. Sequential dispatch is a defect.

7. **Reviewer pod parallel** per `quality.md §7` after impl returns. ONE message; all reviewers.

8. **Fix-forward per `parallelism.md §15`.** Reviewer REWORK → follow-up commits ON TOP of HEAD. Never `git reset`.

9. **Spec hygiene per `architecture.md §21`.** Every landed wave commit ATOMICALLY updates spec.md + benchmark.md.

10. **Share findings.** If the wave surfaced a cross-session-relevant pattern, call `bash scripts/session-mesh/share-finding.sh <topic> '<summary>'` after the wave commits.

## Cost-vs-quality switches

- Default `/effort xhigh` for cross-stack impl. Per-agent override via `--effort` flag if wave is mechanical (then `medium`).
- Use `/ultrareview` ONLY at logical-impact-batch boundary, not per wave.
- Cloud lanes for research / markdown work; local for impl.
- If 3 sessions already active per mesh, defer this wave OR coordinate via handoff.

## Output

Produce a wave plan with:
- Tasks (each with persona, write-set, contract)
- Dispatch shape (single-agent / pair / pod-of-N)
- Reviewer matrix (per `quality.md §7`)
- Verification command (per `architecture.md §29` incremental)
- Mesh claim line (the write-set declaration)
