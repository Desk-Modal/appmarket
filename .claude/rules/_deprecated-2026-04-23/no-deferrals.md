# No Deferrals

**Cardinal rule:** every reviewer finding is CLOSED before the
task's branch integrates. "DEFERRED to <later wave>", "DEFERRED to
<later task>", "DEFERRED to follow-up", "track in ADR for someday"
are **not** valid close-outs.

This rule exists because deferral is where quality silently
evaporates. A finding that is real at the moment it is raised is
still real three waves later — except now it is invisible, has
accumulated sibling findings, and the original evidence has
decayed. The /loop has historically absorbed these as technical
debt; it no longer does.

## The three dispositions a reviewer finding may receive

Every finding exits review in exactly one of three states. Nothing
else is valid.

### 1. CLOSED — the fix is in this task's rework

The owning task's rework branch contains a commit that resolves
the finding. The rework JSON cites the commit SHA + file:line + a
verification command whose evidence path is persisted. Reviewers
on the re-review pass confirm close-out against the same
evidence.

This is the default. Most findings close this way.

### 2. SCOPE-TRANSFERRED — ownership explicitly moves to another task

Permitted when, and only when, the finding's fix is genuinely
within another task's charter AND that task already exists (or is
being created in this same amendment). Transfer requires **all**
of:

- The receiving task is named (`T017`, `T016`, `T027`, …). No
  "queue to Wave J generically".
- The receiving task's `spec.md` Acceptance section is amended in
  the same commit that closes the finding on the sender side, and
  the amendment cites the original finding's source (e.g.
  "scope-transferred from T021 reviewer finding HIGH #3 —
  dashed-line cadence, see `.session-state/wave-f-group-b-findings.md`").
- The sender task's rework references the receiver's Acceptance
  clause number (e.g. "DragPreviewOverlay visual regression
  closure: see T016 Acceptance clause 7").
- The transfer is logged to `.session-state/no-deferrals-ledger.md`
  as a single line: `<ISO timestamp>  <sender-task>  <finding-id>  →  <receiver-task>  <receiver-acceptance-#>  <reason>`.

A scope-transfer is **not** a deferral — it is a finding that
closes on the receiver's integration boundary, not the sender's.
The main /loop rejects integration of the sender task until the
ledger entry is present AND the receiver task's Acceptance
clause has been amended in-commit.

### 3. ESCALATED — the fix is a scope change, paused for user

Permitted when the finding genuinely exceeds the feature's
approved scope (spec.md) AND its resolution would change contracts
the user has already signed off on (architectural direction, a new
crate, a dependency on an unreleased upstream feature, a
material-UX change).

Escalation triggers:

- A comment block in the rework JSON under
  `"escalations": [{finding, reason, proposed_disposition}]`.
- A one-line entry in `.session-state/no-deferrals-ledger.md`
  tagged `ESCALATED`.
- The main /loop **halts the current wave's integration** and
  surfaces the escalation to the user verbatim. Next-wave
  dispatch is suspended until the user answers.

Escalation is the expensive path. Use it sparingly — it blocks the
wave.

## What the rule forbids, concretely

- A reviewer's rework-return JSON containing a `"deferred"` key
  where the value names a wave or task that is not simultaneously
  receiving a spec amendment. **Integration refused.**
- A commit message line reading "deferred to Wave K" /
  "follow-up task to be created" / "tracked in a future ADR" /
  "queue for v2". **commit-msg hook rejects.**
- A task spec Acceptance clause that declares itself the catch-all
  for "any remaining visual-regression items" without naming the
  source tasks and the source finding IDs. **Spec audit rejects.**
- A main-loop integration pass that proceeds past a reviewer
  `REWORK` or `BLOCK` verdict without either (a) the rework
  commit's SHA in the ledger as CLOSED, or (b) an ESCALATED entry
  blocking the wave. **Integration refused.**

## What the rule permits, concretely

- A finding whose close-out costs 30 minutes of work in the
  sender's rework — just do it, no ledger entry needed.
- A finding whose close-out belongs in a later task that already
  exists — scope-transfer with the ledger entry.
- A finding whose close-out requires a new task — author the new
  task's spec in the same commit, add the ledger entry, and set
  the receiver's `serialise_after:` to the sender's task ID.
- A finding that is genuinely out of the feature's scope — ESCALATE,
  wait for the user.

## Interaction with the rework cycle

The main /loop's Phase 4 rework cycle per
`.claude/rules/parallelism.md` is unchanged in **mechanism**; the
contract is tightened:

1. Phase 3 returns reviewer findings in the structured JSON
   format.
2. Phase 4 rework re-dispatches the implementation persona with
   the reviewer findings in the prompt.
3. The rework agent's return JSON declares, for every finding, one
   of `CLOSED | SCOPE_TRANSFERRED | ESCALATED` — no other value.
4. Any `SCOPE_TRANSFERRED` finding carries the receiver's task ID;
   the main /loop verifies the receiver's spec has been amended
   in the same atomic commit.
5. Any `ESCALATED` finding halts the wave; the main /loop surfaces
   the escalation to the user.
6. Re-review (Phase 3 replay) accepts the rework only when every
   finding has a valid disposition.
7. Integration proceeds in task-number order as before.

## Ledger format

`.session-state/no-deferrals-ledger.md` is append-only, one line
per disposition event, format:

```
<ISO-8601 timestamp>  <sender-task>  <finding-id>  <disposition>  <receiver-or-user>  <reason>
```

Examples:

```
2026-04-19T14:03:11Z  T021  HIGH-3   SCOPE_TRANSFERRED  T016-Acceptance-7  dashed-line cadence is CDP-visual regression scope
2026-04-19T14:03:12Z  T021  MED-5    CLOSED             rework/12046f9     per-drag nonce now wired via T020
2026-04-19T15:22:04Z  T022  HIGH-7   ESCALATED          user               full PointerEvents migration exceeds T022 charter
```

The ledger is the audit trail. Reviewers consult it during
re-review. The user reads it to understand what quality posture
each wave has actually delivered.

## Enforcement

- **commit-msg hook extension** — `.claude/hooks/commit-message-honesty.sh`
  already rejects banned phrases; add the deferral phrases to its
  pattern list: `defer(red)? to`, `follow[- ]?up task`, `track(ed)? in (a |an )?(future )?(ADR|wave|task)`, unless the same commit body contains a `scope-transferred` or `escalated` ledger-line reference.
- **Rework-return JSON validator** (main /loop inlined) — rejects
  any finding without one of the three dispositions.
- **Integration gate** — refuses to cherry-pick a sender task's
  branch onto `/tmp/dm-integration` if the ledger shows an
  undischarged `ESCALATED` for that task or any of its
  scope-transfer receivers lack their matching Acceptance
  amendment.
- **Spec audit** (`scripts/audit-parallelism-discipline.sh` or a
  sibling) — rejects an Acceptance clause that contains the
  strings "to be addressed later", "handled separately", or
  "catch-all" without a cross-reference to a named sender task +
  finding ID.

## Escape hatch

`DESKMODAL_LAX=1` bypasses the commit-msg and integration gates,
same as the existing escape hatches. Every bypass appends one line
to `.prod-check/lax-bypass.log` with the exact finding that was
skipped. Use only when the user has authorised the bypass in this
session, verbatim.

## How to amend this rule

Amendments follow the Constitution's amendment process in
`.specify/memory/constitution.md`. Required reviewers:
`qa-architect` (primary) + `integration-architect` (main-loop
gate) + `security-engineer` (audit trail integrity).
