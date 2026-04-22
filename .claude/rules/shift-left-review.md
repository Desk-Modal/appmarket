# Shift-Left Review

**Cardinal rule:** review runs BEFORE implementation, not after. Every
task dispatches reviewers at spec-time (Phase 1.5) so blocking
concerns surface while pivoting is cheap, not after a worktree full
of commits is waiting for merge.

This rule expands the main /loop's phased lifecycle with two new
shift-left dispatch points. It is **additive** to the Phase 3
final-review and Phase 4 rework cycles defined in
`.claude/rules/parallelism.md` — those continue unchanged.

## Rationale

Rework cost declines ~10× when a structural concern is caught at
spec-time vs. post-impl. Observed failure modes on waves F-H:

- Phase 3 reviewer raises a `BLOCK` on an architectural choice the
  impl persona had no way to anticipate from the spec → impl rework
  is 30-50% of the original effort, not a fix-up.
- Reviewer's `BLOCK` reveals the spec's Acceptance clauses are
  themselves defective (e.g. missing reviewer's capability lens).
- Two reviewers return contradictory verdicts because neither
  reviewer saw the spec's trade-off rationale.

Shift-left dispatch collapses these failure modes: every reviewer
reads the spec + proposed approach BEFORE the impl persona writes
code, returns a structured verdict, and the impl incorporates
consensus before moving forward.

## Phase 1.5 — spec-review dispatch (OPT-IN, not mandatory by default)

**Cost reality:** each reviewer agent costs ~100K tokens and
~2 minutes wall-clock. A 5-task wave with 2-3 reviewers per task =
10-15 reviewer agents = ~1-1.5M tokens — before any impl. For most
tasks, the impl agent reading the spec with CBM + Phase 3 commit
review catches the same defects at 10× lower cost.

Phase 1.5 is therefore **opt-in**, triggered only by the explicit
conditions below. The default is: skip Phase 1.5, dispatch impl,
review the commit.

### When to use Phase 1.5 (opt-in triggers)

Fire Phase 1.5 ONLY when one of these is true:

- Task's `wave_eligibility: exclusive` (the task blocks the entire
  wave; getting it wrong costs a wave rework).
- Task's spec is declared `status: ambiguous` by the impl persona
  (impl persona requests pre-review explicitly in their Phase 1
  return).
- Task touches a **constitution invariant** (security signing,
  ACL, FDC3 channel shape, compat ladder) where post-impl rework
  is expensive.
- User explicitly requests Phase 1.5 for a specific task.

For routine impl tasks, skip Phase 1.5 entirely. Let Phase 3 review
the commit, where the evidence is concrete code, not spec prose.

### Who (when triggered)

At most **3 reviewers per task**, even when the Conditional
reviewer matrix would dispatch more. Note: `trading-sme` is NOT universal — it is dispatched only when the plugin fixture meets the
financial-capability trigger in the matrix. Pick the highest-value
lens for the remaining slots:
- `qa-architect` for acceptance-clause testability (universal
  when Phase 1.5 fires),
- `security-engineer` if the spec touches crypto/signing/ACL,
- One domain reviewer (e.g. `integration-architect` for
  cross-crate boundaries).

Hard cap: ≤3 reviewers per task; ≤6 reviewers per wave across all
triggered tasks. If the cap isn't enough, the task is scoped too
large — split it.

### How (dispatch shape)

All reviewers dispatched in **ONE parallel `Agent` batch** — one
assistant message containing N `Agent(subagent_type=…)` tool calls.
Sequential reviewer dispatch is a rule violation per
`.claude/rules/agent-team.md` §"Parallel reviewers are mandatory"
and applies identically to Phase 1.5 as it does to Phase 3.

Each reviewer agent's prompt includes:

- The task's `spec.md` verbatim.
- The impl persona's proposed approach (a short design summary in
  the dispatch prompt body).
- The commit SHA the spec was authored against.
- The phrase "This is Phase 1.5 (shift-left review). Respond with
  the structured JSON below; do NOT emit free-form prose."

Each reviewer returns EXACTLY this JSON:

```json
{
  "phase": "1.5",
  "verdict": "OK|CONCERN|BLOCK",
  "angle": "<short label of your review angle>",
  "task_id": "<e.g. T030>",
  "concerns": [
    {
      "severity": "HIGH|MED|LOW",
      "scope": "acceptance|architecture|security|capability-label|performance|fdc3|ux",
      "summary": "<one-line problem statement>",
      "spec_revision_required": "<concrete spec.md edit — file:line or section>"
    }
  ],
  "suggestions": ["<low-cost improvements that need not block>"],
  "spec_revisions_required": ["<concerns with severity HIGH demanding a spec revision before Phase 2>"]
}
```

### Disposition

- **All reviewers return `OK`** → proceed to Phase 2.
- **Any `CONCERN`** → annotate the spec with an inline `> note:
  <reviewer-angle>` block; concern closes in Phase 2 impl or
  carries through to Phase 3 review.
- **Any `BLOCK`** → impl persona revises the spec per every
  `spec_revisions_required` entry; Phase 1.5 re-dispatches the
  SAME parallel batch against the revised spec (1 re-try max
  before escalation).
- **Two consecutive `BLOCK` rounds on the same task** → ESCALATE
  per `.claude/rules/no-deferrals.md` §3. Main loop halts the wave
  and surfaces to the user.

### What Phase 1.5 is NOT

- Not a design alternative auction. Reviewers critique the PROPOSED
  approach; they do not author alternate implementations.
- Not a capability-label guessing game. If the spec omits the
  Conditional-reviewer-matrix capability signals, the matrix itself
  is defective — fix the matrix, not the spec.
- Not a replacement for Phase 3. The final adversarial review
  against the impl commit remains mandatory.

## Phase 2.5 — draft-review dispatch (OPT-IN)

### When

Phase 2.5 is opt-in, triggered only when ALL of these hold:

- Phase 1.5 fired for this task AND returned ≥1 HIGH concern, AND
- Impl persona's rework addresses the HIGH concern with a
  structural change (>10 files touched), AND
- Impl persona explicitly requests re-review pre-completion.

Phase 2.5 fires mid-implementation, after the impl persona has a
structural outline or a scaffolding commit, and BEFORE the impl
persona writes the majority of the logic.

### Who

Same reviewer set as Phase 1.5 (conditional matrix applies).
Architectural-angle reviewers only when the concern is
architectural — lighter-weight than the full Phase 3 batch.

### How

Same parallel-dispatch invariant as Phase 1.5 and Phase 3 — all
reviewers in ONE message. Impl persona submits:

- The current branch's SHA + worktree path.
- A short "what's been scaffolded" summary.
- A pointer to the structural outline (module graph, interface
  definitions, or key data-flow lines).

Reviewers return the Phase 1.5 JSON shape with `"phase": "2.5"`.

### Disposition

Same as Phase 1.5. `BLOCK` → impl revises the scaffold before
writing the body logic. `CONCERN` → annotate; re-check at Phase 3.

## Interaction with existing rules

- `.claude/rules/parallelism.md` — Phase 1.5 + Phase 2.5 preserve
  the mandatory-parallel-reviewer invariant. Phase 3 + 4 + 5 + 6
  unchanged.
- `.claude/rules/no-deferrals.md` — Phase 1.5 concerns are closed
  in Phase 2 impl; they may scope-transfer to a named receiver
  task only per the no-deferrals ledger protocol.
- `.claude/rules/agent-team.md` — Conditional reviewer matrix
  determines WHICH reviewers dispatch; this rule determines WHEN.
- `.claude/rules/reviewer-contract.md` — governs what every
  reviewer agent must do at dispatch time. Phase 1.5 reviewers
  follow the same discovery discipline (CBM-first) and dispatch
  hygiene (no `run_in_background: true`).
- `.claude/rules/context-discipline.md` — Phase 1.5 dispatch
  happens when the impl persona has just authored the spec;
  handoff after spec draft is optional (the spec itself carries
  the context).

## Where Phase 1.5 is skipped

The following narrow cases skip Phase 1.5. Every exception is
logged.

| Case | Rationale |
|---|---|
| Rule amendments (`.claude/rules/*.md`) | This rule IS a rule amendment; recursive Phase 1.5 is incoherent. Constitution Governance is the review. |
| Constitution amendments | Same as above — Article VI Governance clause. |
| `adr:not-applicable` commits | Mechanical fixes (dead-code removal, rename, lockfile regeneration) don't meet the architectural-touch threshold. |
| `DESKMODAL_LAX=1` in the session | Same bypass as other rules. Appends an audit line to `.prod-check/lax-bypass.log`. Use only when the user has authorised the bypass verbatim. |

## Enforcement

- **Task spec audit** — specs MAY include a `## Shift-left review`
  section when the task is Phase-1.5-triggered; otherwise the
  section is optional. Skipping it does not fail the audit.
- **Main /loop Phase 1.5 step** — the main /loop's runbook
  dispatches Phase 1.5 ONLY when the opt-in triggers above fire.
  Skipping Phase 1.5 for a routine task is expected behaviour,
  not a rule violation.
- **Hook regression test** —
  `.claude/hooks/tests/shift-left-review.test.sh` verifies the
  rule file exists, declares both phases, declares the structured
  JSON return shape, and cross-references the parallel-reviewer
  invariant (which still applies WHEN Phase 1.5 fires).

## Escape hatch

`DESKMODAL_LAX=1` bypasses Phase 1.5 dispatch globally. Every
bypass appends one line to `.prod-check/lax-bypass.log` with the
task ID and the reason — same audit shape as other rules.

## Amendment

Amendments to this rule follow the Constitution's Governance
process (`.specify/memory/constitution.md`). Required reviewers:
`integration-architect` (main-loop gate) + `qa-architect` (review
discipline) + `documentation-engineer` (rule clarity).
