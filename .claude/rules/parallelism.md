---
title: Parallelism + wave discipline
authority: derives from `core.md`; topic-file for §4 + §15
load_when: planning a wave, dispatching pods, deciding fix-forward vs reset, pipelined non-blocking delivery, audit-by-path discipline
---

# Parallelism + wave discipline

Lean topic-file. `core.md §4` and `core.md §15` cross-references resolve here unchanged. Pairs with [`quality.md`](quality.md) §18.7 (always-parallel + always-verify) and [`agents.md`](agents.md) (dispatch patterns). §4.1 empirical-rule detail + §15 elaboration live in `wiki/playbooks/architecture/orchestration.md` (NOT auto-loaded; `mcp__wiki-mcp__wiki_get_page playbooks/architecture/orchestration`).

## 4. Parallelism — single-agent default; pods reserved

**Default: ONE impl agent per wave.** Opus 4.8 with 1M ctx handles cross-stack work (Rust + Tauri command + TS bridge + React + CSS) better in one agent than three coordinated ones. Contract-edge violations become impossible because the agent owns both sides. Token cost drops ~50%.

**Pods (parallel impl agents) reserved for narrow cases only:**
- Pure CSS/token sweep (style-bot) — disjoint from any impl work.
- Perf benches (own bench files, no impl).
- Independent docs wave (no code writes).

Not a pod case: anything with Rust↔TS crossing, anything touching a Tauri command + its TS caller, anything where one persona's output is another's input.

**Reviewers are ALWAYS parallel** — dispatched in one `Agent` batch per [`quality.md`](quality.md) §7. They're read-only; no race risk; the parallelism is pure wall-clock win.

**Speculative next-wave dispatch (default ON, 2026-05-16):** while reviewers run on wave N, dispatch wave N+1's impl agent against the CURRENT HEAD (post-impl, pre-review). If wave N reviewer returns APPROVE/APPROVE_WITH_COMMENTS, rebase N+1's diff onto post-integration tip and keep. If REWORK with overlapping write-set, discard N+1 (log to `.session-state/speculation-log.md`) and re-dispatch after integration. If BLOCK/ESCALATED, discard unconditionally. Saves 10–20 min per wave; reviewer-cost-only when N+1 is discarded. Opt-out: `DESKMODAL_SPECULATIVE=0`.

**Pod ceiling (2026-05-16; revised 2026-05-18):** when write-sets are PROVEN pairwise-disjoint, dispatch up to `N = min(7, count_of_disjoint_tasks)` impl agents in parallel. **EMPIRICAL 2026-05-18 CAP: 3 concurrent large-context Opus 4.8 agents (per `feedback_api_load_concurrent_agents`).** 2-of-3 returns can be harness-rejected EVEN WHEN agent file-writes persist; observed in F156-R-A+R-B+R-C wave (3 deliverables landed despite 2/3 rejections). **Use 3-cap as the operational default; the architectural 7-cap is the LOGICAL bound, not the empirical one.** Per F157 Layer 12 cost-control: total concurrent agents across all local sessions capped at 9 (3 sessions × 3 agents/session); enforced via `.claude/hooks/subagent-start-bound-budget.sh` SubagentStart-hook.

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
- Pod waves (rare): write-sets MUST be pairwise disjoint. The MAIN LOOP `git apply`s each patch in declared task-number-ascending order; a failed apply or verify closes via a forward commit (§15), never a reset.
- Single-writer files (never written by sub-agents): `.session-state/**`, `.prod-check/**`, `specs/compat-ladder.yml`, `.specify/memory/constitution.md`, `.claude/rules/**`, `.claude/settings.json`.

Execution isolation is **native `isolation: "worktree"`** per `Agent`/`Workflow` dispatch (FS-level write-set isolation; no bespoke sandbox). Determinism preserved by: declared write-sets per task, task-number-ascending merge-train, mandatory parallel reviewer batch, single-writer state files.

## 4.1 Dynamic Workflow vs Agent — decision rule

The native **Workflow** tool moves orchestration OUT of the main conversation into a runtime-executed JS script: the script holds loop/branch logic + intermediate results; children run in FRESH background contexts; **only the final synthesised answer lands in main context** (saves the ~30–80K-token-per-agent intermediate exhaust the `Agent` tool deposits turn-by-turn). It is `core.md §4`'s "Dispatch shape: pipeline" made native.

**Which dispatch primitive:**

- **Single `Agent()`** — one-shot cross-stack wave; one agent owns the write-set end-to-end. Default (§4).
- **Pod (parallel `Agent` batch)** — proven pairwise-disjoint write-sets, zero contract edges, ≤3 concurrent (empirical cap §4).
- **Workflow** — dependency-ordered multi-step graph (research→draft→cross-check; fan-out-N→synthesise; impl-draft→adversarial-refute) that would otherwise be hand-sequenced `Agent` calls; preferred when main context is saturated. **Replaces the "Sequenced single-agent" pattern.** Use bundled `/deep-research` for multi-source fact-checked research fan-out.

**Hard invariants (full 11-rule empirical set in the wiki playbook):** ONE well-scoped phase per invocation (chain across turns, main loop integrates between); `args` is a JSON OBJECT (defensive-parse at top); don't trust returned `patch`/large-string fields (they TRUNCATE — recover real edits from the agent worktree); worktree isolation does NOT contain nested sub-repos (`platform/`, `plugins/*` are separate repos — parallel write-sets MUST be strictly disjoint DIRECTORIES); free-text for heavy fan-out agents, shallow schema for the final synthesis only; NO backticks inside prompt strings; ≤3 concurrent large-ctx Opus; NEVER verify mid-mutation (`§18.7.1`); **single-writer canonical files written by the MAIN LOOP, never by workflow agents** (workflows DRAFT, main loop WRITES + commits).

**Full empirical rules + forbidden postures:** `mcp__wiki-mcp__wiki_get_page playbooks/architecture/orchestration`.

## 4.2 Pipelined non-blocking delivery — verify-gates-push (2026-06-07; PROVEN, NEVER FORGOTTEN)

**Origin:** a session shipped on scope-only Tier-A green, pushed, then the workspace Tier-C verify went RED (fmt drift, stale wiki, clippy, ts). **Agent self-assessment is NOT a push gate.** The fix is a pipeline where impl never blocks and **push is gated on a workspace-green verify of the committed SHA — never agent self-assessment.** Native primitives ONLY (`Agent`/`Workflow` `isolation:"worktree"`, `Bash` `run_in_background`, native task list, native memory, `/review`). NO bespoke scripts.

**The 3 disciplines:**

1. **Disjoint-repo lanes.** The 8 DeskModal repos (root, `platform/`, `plugins/tradesurface/`, `plugins/optiscript/`, `plugin-tools/`, `marketplace/appmarket/`, `marketplace/plugin-index/`, `core-server-api/`) are separate git repos (`parallel-sessions.md`), so a per-repo lane is directory-disjoint **for free** — multiple impl agents in distinct repos satisfy §4's pairwise-disjoint requirement by construction; no cross-lane write-set audit needed. Within one repo, fall back to §4's file-level disjointness discipline.

2. **Verify-gates-push.** A lane's commits stay local until a **background verify of that exact committed SHA in a detached worktree** (`git worktree add --detach <tmp> <sha>` + `Bash` `run_in_background`) returns **rc=0 workspace-wide** (Tier-C: `local-ci.sh --full --sign` scope; `launch.sh --verify` when GUI/FDC3/dist). Impl continues on the LIVE tree; the verify never sees uncommitted mutation and never contaminates concurrent impl (the §4.1 verify-never-mid-mutation rule). The task-notification carries the real exit code — read THAT, never a log-tail/`pgrep`/`nohup`-masked rc. rc≠0 → fix-forward (§15) on top of the SHA, re-commit, re-verify; never push the red SHA, never reset. **Tier-A (agent scope) is ADVISORY** (`§18.7.1`); only the workspace-green worktree verify authorises the push.

3. **Share-cache, no duplication.** Detached-worktree verifies share the repo's warm Cargo/Nx/Vite incremental caches (the worktree is the SAME `.git`/`target`/`.nx` object store) — never `cargo clean`/`nx reset` to "isolate" a verify (that defeats `architecture.md §29` incremental discipline). One verify per lane; lanes share the cache, not re-build it. Durable per-lane state = the **native task list** (`TaskCreate`/`TaskUpdate` carrying lane repo + current SHA + verify rc; status `queued → in-flight → verifying → pushed`) — READ it each wake; never re-derive lane state from `git log`/handoff scanning. The audit trail still lives in `.session-state/handoffs/<feature>.md`.

**The anti-drift invariant:** the ONLY thing that promotes a commit to `origin` is a green workspace verify of that committed SHA in an isolated worktree. Scope-green can never again mask workspace-red because scope-green no longer authorises a push.

**Banned postures:** pushing on Tier-A / agent self-assessment (the drift root cause); verifying against the LIVE working tree mid-mutation; `nohup`-inside-background (masks rc); `pgrep`/log-tail to wait on a verify (self-matches own cmdline; `cmd | tail` rc-mask); re-deriving lane state from `git log` instead of the task plan; any new bespoke script (`verify-async.sh`, `delivery-plan.json`).

**Reusable skeleton:** the per-wave impl fan-out Workflow script lives at `.session-state/pipelined-impl-fanout.js` (correct native Workflow-tool API; agents DRAFT only, main loop commits + verify-gates-push).

**Pairs with:** §4 (single-agent default + pod cap 3 + single-writer) · §4.1 (Workflow fan-out + worktree isolation + verify-never-mid-mutation) · §15 (evolve-and-fix-forward — red verify closes forward) · `quality.md §18.7.1` (Tier A advisory / Tier C gate) · `quality.md §18.7` (always-parallel always-verify) · `architecture.md §29` (incremental cache discipline) · `parallel-sessions.md` (8 disjoint repos) · `discipline.md §26` (durable state — native task list + handoff) · `core.md §11` autonomous-primitive matrix.

## 15. Wave discipline — evolve-and-fix-forward (NEVER ROLL BACK)

**Cardinal rule: every wave moves forward.** Reviewer REWORK / BLOCK / HIGH findings close via a **subsequent commit on top of the current HEAD**, never via `git reset --hard`, `git revert`, or any destructive rewind. Rollback is banned as a wave-mechanic because it discards partial-value work the next wave would otherwise build on.

**The four invariants:**

1. **Impl Agents NEVER commit or push.** Agent instructions explicit: "edit files in-place. Do NOT `git commit`. Do NOT `git push`. Return your work as a unified diff via JSON field `patch`." If an agent returns `commit_sha` (committed behind the orchestrator): the orchestrator reconciles by adding a follow-up commit that completes the contract (never resets). The violation is logged to the handoff for persona-prompt tuning.

2. **Pre-wave snapshot is ADVISORY, not enforced.** The main loop captures `WAVE_BASE=$(git rev-parse HEAD)` so reviewers have a stable diff reference. If HEAD moved, that's a persona-tuning signal, **NOT** a rollback trigger. The orchestrator's response to HEAD-moved: inspect, accept if consistent with wave scope, fix-forward if not.

3. **Reviewer REWORK = one or more follow-up commits on the same branch.** Findings close in the order they reduce risk (BLOCKING → HIGH → MEDIUM → LOW). Each close is a separate small commit whose message cites the finding ID. Re-review runs against the final HEAD after all follow-ups land. Max 2 rework cycles; cycle 3 = ESCALATE to user, not reset.

4. **Pod integration is evolution-safe.** The main loop `git apply`s patches in declared order; if verification fails after apply, the fix is **another commit on top** (usually a reviewer-finding closure), not a reset. The atomic guarantee is about patch application, not about undoing committed work.

**Agent-rejection handling (replaces wave-abort):**
- Rejected / errored Agent → inspect the partial state. If files are untouched, re-dispatch with sharpened prompt. If files were edited and the partial patch is usable, accept + close reviewer findings via follow-up commits. No reset.
- Non-APPROVE self-assessment → still integrate the patch, then dispatch a scoped follow-up to close the `open_concerns`.

**Still prescribed:** Wave ceiling — max 3 rows per wave when truly independent, max 1 when contract edges exist. Shift-left scope review — a single `qa-architect` pass validates the wave's `## Parallelism` + Acceptance clauses before impl dispatch. Contract-edge serialization — when the wave has persona-to-persona contract edges, serialise; each step commits before the next dispatch.

**Verification cadence (batching discipline):** `local-ci.sh --fast` runs ONCE PER PHASE (at the integration gate, after all wave-rework follow-ups land — not per agent/row/commit); `launch.sh --verify` ONCE PER PHASE touching GUI/FDC3/dist, after reviewer findings close; `local-ci.sh --full` ONLY pre-push. Per-agent verification adds 2–5 min × N agents = 10–30 min wasted; the agent's own Tier-A + the integration `--fast` cover correctness. Full elaboration in the wiki playbook.

**What this rule FORBIDS (gate-referenced — IN FULL):**
- `git reset --hard <any-prior-sha>` as a wave-mechanic response to reviewer findings.
- `git revert` of an in-wave commit unless a reviewer finding specifically requests reversion as the fix-forward (rare; typically the fix is amend-on-top).
- `git stash` of orchestrator/in-flight state (root cause of the 2026-05-17 edit-loss incident); use `git show HEAD:<path>` for baselines.
- "Throw away the Agent's work and re-dispatch fresh" as a first response. Re-dispatch only when the partial state is fundamentally unsalvageable (rare).
- Pushing a SHA whose background workspace verify has not returned rc=0 (§4.2 verify-gates-push).

**What this rule REQUIRES:** every reviewer BLOCKING / HIGH finding has a named close-out commit (or scope-transfer / escalation ledger entry) BEFORE the benchmark row is marked green; the post-commit-handoff hook records each close-out commit with its finding ID so future sessions see the fix-forward trail.

**Pairs with:** §4 (parallelism + pod cap) · §4.2 (verify-gates-push — red verify closes forward) · `quality.md §18.7.1` (verification cadence) · `discipline.md §26` (durable state). Elaboration: `mcp__wiki-mcp__wiki_get_page playbooks/architecture/orchestration`.
