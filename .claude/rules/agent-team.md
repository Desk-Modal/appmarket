# Agent Team Rules

## Canonical dispatch: native `.claude/agents/`

Personas are **native Claude Code subagent definitions** at
`.claude/agents/<name>.md`. Each file has YAML frontmatter (`name`,
`description`, `tools`, `model`) + an inlined system prompt body.

The Agent tool dispatches via `subagent_type: <name>` and Claude's
native router matches task wording against each agent's
`description` field. Spec Kit's `tasks.md` declares `persona:` and
`reviewers:` per task row; `/speckit.implement` passes those
through to `Agent(subagent_type=…)`.

**There is no custom routing engine.** The native router +
Spec Kit templates cover every dispatch case. Any historical
`scripts/dispatch-*.sh` helpers still present in-tree are
scheduled for removal once this refactor lands on `main`; new
work must not depend on them.

## Mandatory workflow

Every task follows the SDLC loop from CLAUDE.md:
ORIENT → PLAN → IMPLEMENT → REVIEW → VERIFY → DOCUMENT → COMMIT.
No steps are optional. No steps are deferred.

## Context discipline (applies to every persona)

All 23 agent definitions in `.claude/agents/*.md` inline a banner
pointing to `.claude/rules/context-discipline.md`. Key invariants:

- Read `.session-state/handoff.md` before acting (SessionStart hook surfaces it).
- Write a handoff when context hits 70% window OR 40 tool calls since last durable state OR 30 min wall time on one task.
- Cite evidence (file:line, log excerpt, exit code) for every claim.
- Never retry hypotheses the handoff's "Dead-ends" section has already disproved.
- Sub-agent dispatch: pack the full relevant context into the prompt, reference the active handoff path, and require the sub-agent to return its result in the handoff format (§3 of context-discipline).

## Persona selection matrix

| Domain | Persona (`.claude/agents/<name>.md`) |
|---|---|
| Rust / Tauri / platform core | `rust-systems-architect` |
| React / UI | `frontend-architect` |
| Visual / UX | `trading-ux-architect` |
| Financial logic | `trading-sme` *(CONDITIONAL reviewer — see §"Conditional reviewer matrix")* |
| Chart engine | `charting-expert` |
| Security / supply-chain / ACL | `security-engineer` |
| Testing / QA | `qa-architect` |
| FDC3 / channels / bridge | `fdc3-protocol-engineer` |
| Data / exchanges / feeds | `data-pipeline-engineer` |
| Build / dist / CI | `build-deploy-engineer` |
| Cross-repo integration | `integration-architect` |
| Multi-domain orchestration | `maestro-orchestrator` |
| Docs / specs / rules | `documentation-engineer` |
| Plugin SDK | `plugin-sdk-engineer` |
| Marketplace | `marketplace-architect` |

For the full 23-persona roster, `ls .claude/agents/`.

## Tool scoping (enforced by agent frontmatter)

- **Review-only personas** — `qa-architect`, `security-engineer`,
  `trading-sme`, `chart-qa-verifier`, `marketplace-qa`,
  `integration-architect`, `ux-design-lead` — have **no** `Write`,
  `Edit`, or `NotebookEdit` in their tools list. They audit and
  emit findings; they cannot mutate code.
- **Implementation personas** — the remaining 16 — have full
  mutator access plus domain-appropriate MCPs
  (rust-analyzer, brave-search, github, CBM).
- **Maestro** (`maestro-orchestrator.md`) is the only persona with
  `Agent` in its tools list — it dispatches sub-personas.

## Conditional reviewer matrix

DeskModal is a domain-agnostic plugin platform. Reviewer dispatch is
**capability-driven**, not domain-framed. For every task the main /loop
(or Spec Kit) determines mandatory reviewers using the following
capability filter applied to the task's plugin fixture + code touch set:

| Capability signal | Mandatory reviewer |
|---|---|
| **Universal** (every task) | `qa-architect` |
| Task writes Rust/Tauri/platform core | `rust-systems-architect` (impl) |
| Task writes React/UI | `frontend-architect` (impl) |
| Task writes script-runtime or editor | `plugin-sdk-engineer` (impl) |
| Task touches signing / ACL / auth / supply-chain / secrets | `security-engineer` |
| Task touches plugin-platform boundary (SDK, IPC, loader, channels) | `integration-architect` |
| Task touches FDC3 channels / intents / bridge | `fdc3-protocol-engineer` |
| Task changes user-visible surface (DeskModal app UI, storefront UI) | `ux-design-lead` (review) and/or `trading-ux-architect` (design) |
| Plugin fixture has `manifest.categories ⊇ {trading, market-data, finance, derivatives}` | `trading-sme` |
| Plugin fixture's `manifest.fdc3_intents_raised` includes any order/pnl/position intent (e.g. `deskmodal.PlaceOrder`, `deskmodal.GetPositions`) | `trading-sme` |
| Plugin fixture is `deskmodal.chart` or a chart-engine change | `charting-expert` |
| Task touches marketplace aggregator, catalog schema, or storefront | `marketplace-qa` |

Rules:

- **`trading-sme` is CONDITIONAL, never universal.** It is mandatory
  if and only if the task's plugin fixture meets the category or
  intent criteria above. Non-financial tasks (clock widget, Markdown
  editor, screenshot tool, dev utility) do NOT dispatch `trading-sme`.
- If a task's fixture is a **tri-surface chaos test** that includes
  any financial-capability plugin in the fixture set, `trading-sme`
  is mandatory for that task even if the other fixtures are
  non-financial.
- A missing capability signal is NOT a reason to skip `qa-architect`
  — it remains universal.
- Reviewer selection is declared statically in the task spec's
  `reviewers:` field (Spec Kit format). The main /loop refuses
  dispatch if the declared reviewers contradict the capability
  filter (e.g. financial-capability fixture without `trading-sme`,
  or non-financial fixture with `trading-sme` as mandatory).

## Adversarial review (non-negotiable)

- No code ships without review by a domain-hostile persona.
- **Trading SME must approve** any task whose plugin fixture meets
  the financial-capability trigger above (block authority on
  financial state / order flow / PnL / position).
- **Trading UX Architect must approve** any visual change to a
  trading-capable plugin surface; for non-trading surfaces
  `ux-design-lead` is the visual gate.
- **QA Architect reviews all changes.**
- **Security Engineer reviews** any auth / ACL / signature /
  supply-chain / secrets touch.

### Parallel reviewers are mandatory (INVARIANT)

Every reviewer declared in a task's `reviewers:` field is
dispatched **in a single parallel `Agent` batch** — all
`Agent(subagent_type=…)` calls live in one assistant message.
Sequential reviewer dispatch is a defect; it doubles wall-clock
time for no quality gain, drifts review context across the impl
timeline, and invites the "later reviewer rubber-stamps earlier
reviewer's verdict" failure mode.

### Granular reviewer decomposition (expansion, per `parallelism.md` §4)

Review-only personas MAY declare `review_angles: [<angle>, ...]`
in their frontmatter. When declared, the main /loop dispatches
one agent per angle per task in parallel, each with an
angle-specialised prompt. Findings are deduped by the main /loop
after return, grouped by `(file, line_range ± 3, severity,
finding_hash)` and merged with a `flagged_by: [angle1, angle2]`
list. Caps: ≤5 angles per persona per task; ≤15 reviewer agents
per wave total. Personas without declared angles dispatch once
per task (backward-compatible).

## Team composition patterns (2026-04-20)

Five recognised dispatch patterns. The main /loop picks based on
scope shape. Each sub-agent is a **small specialist**, not a
generalist — prompts ≤15 concrete objectives; over that,
decompose into more agents.

### 1. Pod — cross-persona team on ONE scope

When a task spans multiple domains (e.g., Rust backend + React
frontend + security review). Dispatch ONE impl agent per domain
in a single parallel batch, each pinned to its own worktree.
Write-sets audited via `scripts/audit-wave-write-sets.sh`.
Example: `drag-preview pod = [frontend-architect,
rust-systems-architect]` with write-set partition (TSX vs Rust).

### 2. Angle-swarm — N instances of SAME persona, different angles

When a single persona's scope has ≥2 sub-domains. Dispatch up to
5 agents of the same persona in parallel, each with an
angle-specialised prompt. Angles declared in the persona's
`review_angles` / `impl_angles` frontmatter. Finding dedup step
merges duplicates. Review-only personas parallelise trivially
(read-only); impl personas use angle-swarm only when write-sets
per angle are disjoint.

### 3. Pipeline — sequenced impl agents with role separation

When impl scope is large but write-sets overlap (parallel agents
would conflict). Dispatch SEQUENTIALLY with role handoff:
scaffold → implement → test → document. Each step's output is
the next step's input. Slower than pod but handles the
monolithic-scope case. Use sparingly; prefer decomposing to a
pod.

### 4. Pair — TWO impl agents with explicit write-set partition

When exactly two domains touch a task (e.g., Tauri-command +
React-consumer). One agent owns backend, the other frontend;
they agree on the IPC contract in the dispatch prompt. Faster
than pod for 2-agent cases; skips write-set-audit overhead.

### 5. Adversarial pod — reviewer guild per wave

Every task's review batch includes ALL declared angles across
ALL mandatory reviewer personas. Standing pod example:
`{qa-architect × 5 angles, security-engineer × 5 angles,
trading-sme × 5 angles (if financial logic), domain-reviewer}`.
Up to 15 reviewer agents per wave (cost ceiling). Fires in ONE
parallel message per the mandatory parallel-reviewer invariant
(§Parallel reviewers are mandatory).

### When to use which

| Task shape | Pattern |
|---|---|
| Single-domain, one impl agent | Direct dispatch (no pattern) |
| Multi-domain, disjoint writes | Pod |
| Single-persona, multi-sub-domain | Angle-swarm |
| Single-persona, monolithic writes | Pipeline |
| Two-domain, backend/frontend split | Pair |
| Review of any task | Adversarial pod (mandatory) |

### Small-agent principle

Every dispatched Agent prompt is ≤15 concrete objectives. Over
that threshold: decompose. A 30-objective prompt is a disguised
monolith — it loses focus and finishes as three shallow
10-objective passes instead of one 15-objective deep pass. Prefer
two agents with 8 objectives each to one agent with 16.

### `impl_angles:` frontmatter field

Implementation personas MAY declare `impl_angles: [<angle>,
<angle>, ...]` in frontmatter. Angles represent sub-domains of
the persona's charter. When the main /loop dispatches an impl
angle-swarm, it selects angles whose write-sets are pairwise
disjoint (audited per mechanism #3). Personas without declared
angles dispatch once per task (backward-compatible).

Consequences:
- The /loop Phase 3 (review) prompt emits one message containing
  N `Agent` tool calls for N reviewers — never N messages each
  with one call.
- If a wave has M tasks and each task has K reviewers, Phase 3
  emits one message with `M × K` parallel `Agent` calls.
- Reviewers run on review-only personas (tool scope forbids
  mutation) so parallel dispatch has no write-set race; no
  worktree isolation is required for review passes.
- Rework Phase 4 re-runs the **same parallel batch** after the
  impl rework commits land — no sequential reviewer re-check.

Escape hatches:
- **None for serial reviewer dispatch.** If a reviewer needs
  output from another reviewer, that is a spec defect — decompose
  the review scope so every reviewer has an independent hostile
  lens.
- `DESKMODAL_LAX=1` still bypasses the integration gate globally,
  but no flag permits sequential reviewer dispatch.

Enforcement:
- `/loop` Phase 3 runbook emits one multi-tool-call message; any
  single-reviewer message is a rule violation flagged in the
  handoff.
- The re-review replay in Phase 4 uses the same parallel batch.
- Task-spec reviewer lists with one entry still dispatch as a
  single-item parallel batch (format consistency).

## GUI verification (non-negotiable for GUI)

- Every GUI change requires before/after Playwright screenshots
  under `tests/gui/` (cross-platform; macOS-compatible). See
  `scripts/prod-check.sh gui` for the runner.
- CDP was removed 2026-04-21 — the
  `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` env is Windows-only and
  macOS WKWebView doesn't expose a Chrome DevTools port.
  Playwright's vendored Chromium is the cross-platform replacement.
- Delete temporary screenshots after review.

## Quality gates (must pass before commit)

- `scripts/local-ci.sh --fast` — fmt + clippy + typecheck + hook tests + prod-check --fast
- Zero BLOCKING / HIGH findings from adversarial review
- Playwright GUI specs pass for GUI changes (`scripts/prod-check.sh gui` when the change touches visuals/interaction)
- Constitution + compat-ladder clean (`.specify/memory/constitution.md`; `specs/compat-ladder.yml`)

## Amendment

Amendments to this rule follow the Constitution's amendment
process (`.specify/memory/constitution.md` Article VI + Governance).
