# Parallelism Rules

**Cardinal rule:** parallelism is the default execution mode;
determinism is the floor no parallel decision is allowed to break.

Every planning decision — task spec, /loop iteration, Agent
dispatch, review pass — explicitly considers whether work can run
in parallel and what determinism guarantees hold under that
parallelism.

## The four determinism mechanisms

Parallelism that breaks determinism is a defect, not a win. These
four mechanisms make concurrent agent execution reproducible:

### 1. Declared file-set per task

Every task spec declares what it reads and writes. The scheduler
refuses to dispatch two tasks concurrently when their write sets
intersect (or when one's write set intersects another's read set
in a way that creates a read-after-write race).

Declared in the spec's `## Parallelism` section:

```markdown
## Parallelism
- Reads: <paths / globs — what the sub-agent will inspect>
- Writes: <paths / globs — what the sub-agent will modify>
- Concurrent with: <task IDs> | any | none
- Serialise after: <task IDs> | none
- Wave eligibility: concurrent | serial | exclusive
```

Specs without a complete Parallelism section are **rejected** by
the /loop at Phase 1 (same posture as missing Personas section).

Write-set disjointness is the correctness guarantee: two agents
can never be dispatched when their writes overlap, so no
file-level race is possible regardless of how the sub-agents
organise their work on disk.

### 2. Single-writer state files

The following files have exactly one writer — the main /loop. No
sub-agent writes them directly:

- `.session-state/handoff.md`
- `.session-state/loop-state.json`
- `.prod-check/status.json`
- `.prod-check/workspace.json`
- `specs/compat-ladder.yml` (ladder is authoritative; sub-agents
  return proposed diffs, main loop merges)
- Anything under `specs/tasks/queue/done/` (archive is integration)

Sub-agents return structured JSON; the main loop merges into
state. This eliminates the write-after-write race that made
distributed mutable memory systems (mem0-style) so hard to reason
about.

### 3. Deterministic integration order

When N parallel Agents finish a wave, the main loop integrates
their branches in **task-number order** (lowest NNN first), not
completion-time order. Same input set → same integration history,
byte-identically, regardless of which Agent finished first.

Rework cycles preserve this: if task 005 needs rework and task 008
is already integrated, only 005's branch re-dispatches; 008 stays
integrated. No global rollback on a local failure.

### 4. Structured outputs, constrained non-determinism

LLM outputs are inherently non-deterministic at the token level.
Specs absorb this by expressing acceptance as a **boolean contract**
against machine-checkable commands. Two runs of the same spec on
the same `main` SHA may produce different commit text or different
ordering within a file, but the acceptance gates determine
pass/fail identically.

Every sub-agent returns structured JSON (`{branch, commit_sha,
verification_all_passed, evidence_paths, ...}`) rather than
free-form prose. The main loop parses JSON, not interprets prose.

## Where parallelism is forbidden (by design)

Some work is serial because the semantics demand it:

| Operation | Why serial |
|---|---|
| Phase 4 rework cycle | Depends on reviewer findings from Phase 3 |
| Phase 6 archive + handoff | Integration point; single-writer invariant |
| Constitution amendments | `.specify/memory/constitution.md` is a global invariant; concurrent edits are incoherent |
| Compat ladder amendments | `specs/compat-ladder.yml` is authoritative; concurrent edits break the consumer-parity gate |
| Anything mutating `.claude/rules/*.md` | Rules are the execution contract; concurrent rule changes race with every in-flight task |
| Anything mutating `.claude/settings.json` | Hook config is enforcement; concurrent edits flap the hook surface |

Mark these tasks `wave_eligibility: serial` or `exclusive` in their
spec.

## How the /loop plans waves

Wave planning runs **inline in the /loop prompt**, not via a
separate dispatcher script:

1. `ls specs/tasks/queue/` — enumerate pending tasks.
2. Sort by execution order from `queue/README.md`.
3. Starting from the lowest-ordered pending task, greedily add
   subsequent tasks to the wave **iff**:
   - their write-sets don't intersect the wave's accumulated
     write set
   - their reads don't race the wave's writes
   - they have no unsatisfied `serialise_after:` dependency
   - the wave has no `exclusive` task (exclusive = alone)
   - the wave has no `serial` task (serial = alone within its
     wave)
4. Dispatch every wave member as an
   `Agent(subagent_type: <persona from tasks.md>)` in a single
   message (parallel execution). Persona is resolved from the
   task's `persona:` field (Spec Kit tasks-template.md extension).
   Claude selects the execution-isolation strategy that best fits
   the current best practices of the harness; the rule does not
   prescribe it.
5. Await all — each Agent returns structured JSON.
6. Integrate in task-number order:
   - Phase 3 adversarial review — **every reviewer across every
     wave-member task dispatched in ONE parallel `Agent` batch**
     (one assistant message, M × K tool calls for M tasks with
     K reviewers each). Sequential reviewer dispatch is a rule
     violation per `.claude/rules/agent-team.md` §"Parallel
     reviewers are mandatory".
   - Phase 3.5 smoke-check runs against each integrated branch.
   - Phase 4 rework per-task (in parallel across tasks,
     sequential within a task). Re-review after rework is the
     SAME parallel batch dispatched in Phase 3 — never
     sequentially.
   - Phase 5 gates per-task.
   - Phase 6 archive each member in task-number order.
7. `ScheduleWakeup` for the next wave (same cadence rules as
   single-task mode).

## Model-ID pinning

Every `Agent` dispatch passes `model` explicitly to pin the sub-
agent to the same model family as the main loop. "Inherit" is
fine (parent is the explicit pin), but never let a sub-agent pick
an arbitrary model — the planner's quality assumptions depend on
the model.

## Enforcement

- **Task spec audit gate** (`scripts/audit-parallelism-discipline.sh`)
  fails the build when any spec lacks a `## Parallelism` section or
  declares contradictory fields (e.g., `concurrent with: [005]`
  but `005` spec says `concurrent with: none`).
- **Main-loop refuses** to dispatch from a spec without a complete
  Parallelism section (Phase 1 precondition).

## Known escape hatches (documented, not encouraged)

- **`DESKMODAL_LAX=1`** — bypass enforcement for one-off hotfixes.
  Same bypass flag as other rules. Audit log captures every use.
- **Manual wave override** — a user can edit
  `specs/tasks/queue/README.md` execution order to force serial
  execution if a wave-scheduling bug surfaces.

## Pipeline parallelism — maximum scaling mechanisms

The base rules above guarantee correctness under parallelism.
These mechanisms close the remaining bottlenecks — idle
dispatcher time between phases, serial integration branch, fixed
impl-count cap, reviewer fan-out, single-loop cap.

Adopted 2026-04-20 to address the five bottlenecks identified by
the main /loop during Wave F Group B execution. Each mechanism is
independently opt-in with a documented default.

### 1. Speculative next-wave impl (default ON)

When the current wave enters Phase 3 (review) and the review
batch is dispatched, the main /loop MAY dispatch the next wave's
impl agents speculatively in parallel with the review.

- Speculative branch: `spec/task/TNNN-<slug>`, pinned to the
  CURRENT integration tip (post-review tip is not yet known).
- Rollback contract:
  - Current wave verdict = APPROVE / APPROVE_WITH_COMMENTS →
    rebase speculative branches onto post-integration tip; keep.
  - Current wave verdict = REWORK and rework's write-set
    intersects speculative write-set → discard speculative,
    re-dispatch after integration.
  - Current wave verdict = BLOCK / ESCALATED → discard
    speculative unconditionally.
- Speculative impl agents use the SAME persona + write-set
  discipline as non-speculative dispatches. They cannot merge
  their own branches.
- Every discard appends one line to
  `.session-state/speculation-log.md` with timestamp + task +
  reason + tokens-wasted estimate.

Opt-out: `DESKMODAL_SPECULATIVE=0`. Default: ON.

### 2. Per-task integration branches + merge-train (default ON)

Replaces the single-`/tmp/dm-integration` cherry-pick serial:

- Each completed + APPROVED task lands on `integ/TNNN` — the
  task branch rebased onto the current integration tip.
- Wave-boundary merge-train: `git merge --no-ff integ/TNNN ...`
  in task-number ascending order. Each merge step gated by
  `scripts/local-ci.sh --fast`. A failed gate halts the train
  at that step; the offending task is surfaced by exact ID
  (failure attribution is unambiguous, unlike bulk cherry-pick).
- Review happens on the task branch BEFORE the merge-train —
  no pre-integration wait.
- Legacy `/tmp/dm-integration` survives as the merge-train
  target HEAD; the train advances its tip atomically per merge.

Opt-out: `DESKMODAL_INTEG_MODE=cherry-pick`. Default:
`merge-train`.

### 3. Write-set-gated impl-count cap (replaces fixed max=3)

The fixed "max 3 impl per wave" was a proxy for write-set
safety. The declared file-set mechanism (§1 determinism
mechanism) enforces write-set safety per-task; the real residual
constraint is cost, not correctness.

- Compute the wave's cumulative write-set (union across tasks).
- If tasks' write-sets are pairwise disjoint: dispatch up to
  `N = min(7, count_of_pairwise_disjoint_tasks)` impl agents in
  parallel.
- Hard cost-safety ceiling: `N ≤ 7` impl agents per wave to
  bound sub-agent token spend (≈ $50–100/wave on Opus).
- When two or more tasks share ANY write-set member, fall back
  to the old 3-cap, or serial if sharing is broad.
- Audit: `scripts/audit-wave-write-sets.sh` validates
  disjointness before dispatch when `N > 3`. Audit failure
  blocks dispatch.

### 4. Granular reviewer decomposition (default ON when angles declared)

Expand the "one reviewer persona per task" shape to "one reviewer
persona per REVIEW ANGLE per task":

- Each review-only persona MAY declare
  `review_angles: [<angle>, <angle>, ...]` in its frontmatter.
- Example: `security-engineer` declares
  `[supply-chain, acl, signature, crypto, secrets]` — main /loop
  dispatches up to 5 `security-engineer` agents per task in
  parallel, one per angle, each with a specialised prompt.
- All angles across all wave-member tasks dispatch in ONE
  parallel message (preserves the mandatory parallel-reviewer
  invariant in `.claude/rules/agent-team.md` §73-107).
- Finding dedup step runs after all reviewers return: main /loop
  groups findings by `(file, line_range ± 3, severity,
  finding_hash)` and merges duplicates into a single finding with
  a `flagged_by: [angle1, angle2, ...]` list.
- Caps: ≤5 angles per persona per task; ≤15 reviewer agents per
  wave total.
- When a persona declares no `review_angles`, dispatch a single
  agent (current behaviour — backward compatible).

### 5. Multi-loop via per-feature handoffs (opt-in)

Single-writer handoff scopes to PER-FEATURE, not workspace-wide:

- Handoff path: `.session-state/handoffs/<feature-id>.md` (e.g.
  `handoffs/001.md`, `handoffs/016.md`).
- Lock file: `.session-state/handoffs/<feature-id>.lock` — taken
  at /loop start, released at /loop completion/stop.
- `.session-state/handoff.md` becomes a symlink to the active
  feature's handoff for backward compatibility (or an index of
  active loops when multiple are live).
- `.session-state/handoffs/MEMORY.md` lists active loops with
  feature-id + lock-holder session-id + start time.
- Rule-file mutations (`.claude/rules/*.md`,
  `.claude/settings.json`, `.specify/memory/constitution.md`,
  `specs/compat-ladder.yml`) remain workspace-global single-
  writer — they BLOCK multi-loop concurrency by design.

Opt-in: `/loop --feature <id>` explicit invocation. Default:
single-loop (preserves current behaviour exactly).

### Interaction with existing rules

- Mandatory parallel reviewer dispatch (agent-team.md §73-107) is
  UNCHANGED — mechanism #4 expands it, doesn't replace it.
- NO DEFERRALS (`no-deferrals.md`) applies to speculative and
  per-task integ branches identically. A speculative branch that
  never integrates is not a deferral — it is a cancelled work
  unit; document in `.session-state/speculation-log.md`.
- Integration order remains task-number ascending; merge-train
  enforces it atomically.
- Model-ID pinning unchanged.

### Enforcement

- `scripts/audit-wave-write-sets.sh` validates disjointness
  before `>3` impl dispatch (mechanism #3).
- `scripts/merge-train.sh` runs `local-ci.sh --fast` between
  each merge step (mechanism #2).
- `.session-state/speculation-log.md` audit trail for discards
  (mechanism #1).
- `scripts/feature-lock.sh {acquire,release} <feature-id>`
  (mechanism #5).
- Main /loop adds Phase 3.5: reviewer-finding dedup step
  (mechanism #4).

These scripts are followup implementation tasks; the rule
codifies the contract.

### Cost model

| Mechanism | Wall-clock gain | Token cost | Rollback risk |
|---|---|---|---|
| #1 Speculative | +10–20 min/wave | +30% (discards) | Medium |
| #2 Merge-train | +5–15 min/wave | 0% | Low (atomic merges) |
| #3 Impl cap lift | 0–5 min/wave | +40–130% | Low (write-sets audit) |
| #4 Granular reviewers | +2–10 min/wave | +100–200% | Low (read-only) |
| #5 Multi-loop | linear with loop count | linear | High (rule races) |

Mechanisms #2, #3, #4 are high-confidence. Mechanism #1 is
experimental with measured rollback risk. Mechanism #5 is a
structural shift requiring careful rollout.

## How to amend

Amendments follow the Constitution's Governance section
(`.specify/memory/constitution.md`). Required reviewers:
`integration-architect` (primary) + `qa-architect` +
`security-engineer`.
