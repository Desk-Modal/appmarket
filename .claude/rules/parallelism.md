---
title: Parallelism + wave discipline
authority: derives from `core.md`; topic-file for §4 + §15
load_when: planning a wave, dispatching pods, deciding fix-forward vs reset, audit-by-path discipline
---

# Parallelism + wave discipline

Section anchors preserved: `core.md §4` and `core.md §15` cross-references resolve to this file unchanged. Pairs with [`quality.md`](quality.md) §18.7 (always-parallel + always-verify) and [`agents.md`](agents.md) (dispatch patterns).

## 4. Parallelism — single-agent default; pods reserved

**Default: ONE impl agent per wave.** Opus 4.7 with 1M ctx handles cross-stack work (Rust + Tauri command + TS bridge + React + CSS) better in one agent than three coordinated ones. Contract-edge violations become impossible because the agent owns both sides. Token cost drops ~50%.

**Pods (parallel impl agents) reserved for narrow cases only:**
- Pure CSS/token sweep (style-bot) — disjoint from any impl work.
- Perf benches (own bench files, no impl).
- Independent docs wave (no code writes).

Not a pod case: anything with Rust↔TS crossing, anything touching a Tauri command + its TS caller, anything where one persona's output is another's input.

**Reviewers are ALWAYS parallel** — dispatched in one `Agent` batch per [`quality.md`](quality.md) §7. They're read-only; no race risk; the parallelism is pure wall-clock win.

**Speculative next-wave dispatch (default ON, 2026-05-16):** while reviewers run on wave N, dispatch wave N+1's impl agent against the CURRENT HEAD (post-impl, pre-review). If wave N reviewer returns APPROVE/APPROVE_WITH_COMMENTS, rebase N+1's diff onto post-integration tip and keep. If REWORK with overlapping write-set, discard N+1 (log to `.session-state/speculation-log.md`) and re-dispatch after integration. If BLOCK/ESCALATED, discard unconditionally. Saves 10–20 min per wave; reviewer-cost-only when N+1 is discarded. Opt-out: `DESKMODAL_SPECULATIVE=0`.

**Pod ceiling (2026-05-16; revised 2026-05-18):** when write-sets are PROVEN pairwise-disjoint (audited via `scripts/audit-wave-write-sets.sh`), dispatch up to `N = min(7, count_of_disjoint_tasks)` impl agents in parallel. **EMPIRICAL 2026-05-18 CAP: 3 concurrent large-context Opus 4.7 agents (per `feedback_api_load_concurrent_agents`).** 2-of-3 returns can be harness-rejected EVEN WHEN agent file-writes persist; observed in F156-R-A+R-B+R-C wave (3 deliverables landed despite 2/3 rejections). **Use 3-cap as the operational default; the architectural 7-cap is the LOGICAL bound, not the empirical one.** Per F157 Layer 12 cost-control: total concurrent agents across all local sessions capped at 9 (3 sessions × 3 agents/session); enforced via `.claude/hooks/subagent-start-bound-budget.sh` SubagentStart-hook.

**Dispatch hygiene — audit by path, never by quote (2026-05-16):** when an agent's prompt references an audit/spec/finding, pass the **file path** for it to read once at start. Inline-quoting full audit excerpts in every parallel dispatch burns ~30–80K tokens per agent. The agent reads the source once; you save token cost linearly with N agents.

**Warm-agent reuse via SendMessage (2026-05-16):** when wave N+1 is a follow-up that depends on wave N's loaded context (e.g. plugin-sdk-engineer already has the SDK contract in conversation), continue it via `SendMessage(to: <agent-id>)` instead of `Agent()`. Saves the ~30–50K cold-start re-read. Only valid when wave N+1 is genuinely a continuation, not a fresh task.

Every task spec declares:

```markdown
## Parallelism
- Reads: <paths or globs>
- Writes: <paths or globs>
- Contract produces: <named symbols this wave creates>
- Contract consumes: <named symbols this wave calls from existing code>
- Dispatch shape: single-agent | pod | pipeline
```

Invariants:
- Single-agent waves use ONE `Agent()` call. The agent edits in-place and returns a unified diff via JSON (never commits).
- Pod waves (rare): write-sets MUST be pairwise disjoint. `scripts/pod-apply.sh` applies all patches atomically or rolls all back.
- Single-writer files (never written by sub-agents): `.session-state/**`, `.prod-check/**`, `specs/compat-ladder.yml`, `.specify/memory/constitution.md`, `.claude/rules/**`, `.claude/settings.json`.

No worktree mandate. Claude picks per-dispatch execution isolation.

Determinism preserved by: declared write-sets per task, task-number-ascending merge-train, mandatory parallel reviewer batch, single-writer state files. None of the above amendments touch these invariants.

## 15. Wave discipline — evolve-and-fix-forward (NEVER ROLL BACK)

**Cardinal rule: every wave moves forward.** Reviewer REWORK / BLOCK / HIGH findings close via a **subsequent commit on top of the current HEAD**, never via `git reset --hard`, `git revert`, or any destructive rewind. Rollback is banned as a wave-mechanic because it discards partial-value work the next wave would otherwise build on.

**The four invariants (replace the old rollback-based ITER-02 mitigations):**

1. **Impl Agents NEVER commit or push.** Agent instructions explicit: "edit files in-place. Do NOT `git commit`. Do NOT `git push`. Return your work as a unified diff via JSON field `patch`." If an agent returns `commit_sha` (committed behind the orchestrator): the orchestrator reconciles by adding a follow-up commit that completes the contract (never resets). The violation is logged to the handoff for persona-prompt tuning.

2. **Pre-wave snapshot is ADVISORY, not enforced.** `scripts/wave-sandbox.sh init` still captures `WAVE_BASE=$(git rev-parse HEAD)` so reviewers have a stable reference for their diffs. `assert-clean` still runs — if HEAD moved, that becomes a persona-tuning signal, **NOT** a rollback trigger. The orchestrator's response to HEAD-moved is: inspect, accept if the change is consistent with wave scope, fix-forward if not.

3. **Reviewer REWORK = one or more follow-up commits on the same branch.** Findings close in the order they reduce risk (BLOCKING → HIGH → MEDIUM → LOW). Each close is a separate small commit whose message cites the finding ID. Re-review runs against the final HEAD after all follow-ups land. Max 2 rework cycles; cycle 3 = ESCALATE to user, not reset.

4. **Pod integration is evolution-safe.** `scripts/pod-apply.sh` applies patches in declared order; if verification fails after apply, the fix is **another commit on top** (usually a reviewer-finding closure), not a reset. The pod's atomic guarantee is about patch application, not about undoing committed work.

**Agent-rejection handling (replaces wave-abort):**
- Rejected / errored Agent → inspect the partial state. If files are untouched, re-dispatch with sharpened prompt. If files were edited and the partial patch is usable, accept + close reviewer findings via follow-up commits. No reset.
- Non-APPROVE self-assessment → still integrate the patch, then dispatch a scoped follow-up to close the `open_concerns`.

**What's still prescribed (unchanged):**

5. **Wave ceiling.** Max 3 rows per wave when truly independent. Max 1 row when contract edges exist between personas in the wave. Smaller waves = smaller rework surface.

6. **Shift-left scope review.** Before impl dispatch, a single `qa-architect` review pass validates the wave's `## Parallelism` section and Acceptance clauses. Catches contract holes at spec-time (cheap).

7. **Contract-edge serialization.** When the wave has persona-to-persona contract edges, serialise — never dispatch in parallel. Each step commits before the next Agent dispatches.

**Verification cadence (batching discipline, tightened 2026-05-16):**
- `scripts/local-ci.sh --fast` runs ONCE PER PHASE (at impl-wave integration gate; after all wave-rework follow-ups land — not per agent, not per row, not per intermediate commit).
- `scripts/launch.sh --verify` runs ONCE PER PHASE (only when the phase touches GUI/FDC3/dist), after all reviewer findings close.
- `scripts/local-ci.sh --full` runs ONLY pre-push (or pre-PR), never per-wave.
- Never per-row. Never per-persona. Never per-agent. Per-agent verification adds 2–5 min per dispatch × N agents per phase = 10–30 min wasted wall-clock; the agent's own type-check + the integration `--fast` cover correctness.

**What this rule forbids:**
- `git reset --hard <any-prior-sha>` as a wave-mechanic response to reviewer findings.
- `git revert` of an in-wave commit unless a reviewer finding specifically requests reversion as the fix-forward (rare; typically the fix is amend-on-top).
- `wave-sandbox.sh rollback` as the default response to REWORK. The script's `rollback` subcommand is deprecated; use `wave-sandbox.sh fix-forward` (no-op stub that logs the finding for handoff) instead.
- "Throw away the Agent's work and re-dispatch fresh" as a first response. Re-dispatch only when the partial state is fundamentally unsalvageable (rare).

**What this rule requires:**
- Every reviewer BLOCKING / HIGH finding has a named close-out commit (or scope-transfer / escalation ledger entry) BEFORE the benchmark row is marked green.
- The post-commit-handoff hook records each close-out commit with its finding ID so future sessions see the fix-forward trail.
