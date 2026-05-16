# Agent dispatch

## Canonical

Personas live in `.claude/agents/<name>.md` with YAML frontmatter (`name`, `description`, `tools`, `model`, optional `color`, `permissionMode`, `memory`). Body is ≤ 15 lines: domain scope + invariants + exit criteria. Central rules come from `.claude/rules/core.md`.

Dispatch: `Agent(subagent_type=<name>, model=<pinned>)`. Claude's native router matches task wording against each agent's `description`.

## Model tiering

**Policy (2026-05-16, amends 2026-05-14): demote model tiers aggressively per task shape.** The all-Opus 2026-05-14 policy was over-conservative — Sonnet handles pattern-replication refactors at 1/5 the cost; Haiku handles mechanical sweeps at 1/25. Reserve Opus for what genuinely requires it.

| Tier | Model | Use for | Rationale |
|---|---|---|---|
| **Opus 4.7** | `claude-opus-4-7` | Orchestration; adversarial review (qa-architect, security-engineer, trading-sme, ux-design-lead, chart-qa-verifier); Rust ABI / FDC3 semantics / security / ACL impl; cross-stack contracts (rust-systems-architect, integration-architect, fdc3-protocol-engineer, plugin-sdk-engineer on SDK shape) | Subtle invariants, multi-file reasoning, 1M-ctx essential |
| **Sonnet 4.6** | `claude-sonnet-4-6` | Structural decomp on ≤1000 LOC files; React/UI impl (frontend-architect, trading-ux-architect); data pipeline / charting impl; pattern-replication refactors; docs (documentation-engineer); marketplace UX | Pattern replication, single-file focus, 5× cheaper |
| **Haiku 4.5** | `claude-haiku-4-5-20251001` | Token sweeps; lint auto-fixes; rename refactors; CSS-token replacement (style-bot); doc-only typo fixes | Mechanical, <8 objectives, 25× cheaper |

**Promotion criteria.** Any impl persona showing REWORK > 1 per 5 dispatches gets promoted one tier (Haiku→Sonnet, Sonnet→Opus). Demotion when REWORK = 0 across 10 dispatches. Tier overrides allowed per-dispatch via the `model` parameter; default inherits from the persona's frontmatter pin.

**Anti-pattern.** Don't run Opus on a 200-LOC component-extraction or a CSS-token swap. The 5× cost differential compounds across N parallel waves.

## Dispatch patterns

Claude Code's native sub-agent system is the dispatch mechanism (`Agent` tool). This section is workflow POLICY for when to use it.

**Default is single-agent per wave.** Opus 4.7 1M-ctx owns cross-stack work end-to-end; contract-edge violations impossible; token cost ~50% vs multi-agent.

| Pattern | When | How |
|---|---|---|
| **Single-agent** (default) | Any wave — one agent owns Rust + TS + CSS end-to-end | One `Agent` call; agent edits in-place; returns unified diff via JSON |
| **Sequenced single-agent** | Rare — if a commit must land before the next step can proceed (e.g. serde shape change that forces downstream TS regen) | Sequential `Agent` calls with a commit between |
| **Pod (≤7)** | Proven pairwise-disjoint write-sets (audited via `scripts/audit-wave-write-sets.sh`) AND zero contract edges between members | Parallel `Agent` batch up to 7 concurrent; `scripts/pod-apply.sh` atomic-merges all patches. Default cap 3 unaudited; 7 when audit passes (core.md §4) |
| **Speculative N+1** (default ON) | While wave N's reviewers run, dispatch wave N+1 impl against current HEAD | Parallel `Agent` call alongside the review batch; rebase or discard per wave N verdict (core.md §4). Opt-out: `DESKMODAL_SPECULATIVE=0` |
| **Warm-agent SendMessage** | Wave N+1 is a continuation of wave N with same persona + loaded context (e.g. plugin-sdk-engineer already holds SDK contract) | `SendMessage(to: <agent-id>)` instead of fresh `Agent()` — saves ~30–50K cold-start re-read tokens. Only valid for true continuations |
| **Angle-swarm** (review only) | One reviewer persona, multiple lenses | Parallel dispatch of same persona with angle-specialised prompts |
| **Adversarial review** (mandatory every wave) | All declared reviewers for the wave | ONE parallel `Agent` batch per core.md §7 |

Reviewers always parallel (read-only, no race risk). Impl single-agent by default; promote to pod when write-sets audit clean; layer speculative N+1 on top when pipelining pays.

Each prompt ≤ 15 concrete objectives. Past that: decompose the wave, not the agent.

**Audit-by-path, not by inline quote (core.md §4).** When dispatching N parallel agents that share an audit/spec/finding reference, pass the **file path** and instruct the agent to read it once. Inline-quoting the audit body in each prompt burns ~30–80K tokens per dispatch — at N=5 parallel, that's 150–400K wasted tokens.

**Throughput estimate (2026-05-16 amendments combined):** serial 1-agent waves at ~15–20 min → 3–5 parallel agents per wave at ~10–15 min total. ~2–3× throughput on impl-heavy work, ~4–8× on mechanical sweeps (Haiku style-bot pods).

## Return contract (every impl sub-agent)

**Impl Agents NEVER `git commit` or `git push`.** They edit files in-place and return the unified diff via JSON.

```json
{
  "patch": "<output of: git diff HEAD -- <declared write-set>>",
  "write_set_declared": ["<path>", ...],
  "write_set_actual": ["<path>", ...],
  "verification_command": "scripts/local-ci.sh --fast",
  "verification_exit_code": 0,
  "contract_produces": ["<symbol>", ...],
  "contract_consumes": ["<symbol>", ...],
  "self_assessment": "APPROVE | CONCERNS | REWORK | BLOCK",
  "open_concerns": ["..."]
}
```

**`patch` field** is required; MUST contain a valid unified diff. If an agent returns `commit_sha` (old shape), orchestrator reconciles by folding the agent's commit into a wave-cohort commit on top of current HEAD and logs the persona-prompt violation to the handoff. **Never reset.**

**Orchestrator handles (does NOT reject) returns where:**
- `patch` is empty or malformed → dispatch a follow-up Agent with the exact malformation cited; never reset.
- `write_set_actual ⊄ write_set_declared` → review the out-of-set files; accept if consistent with wave scope, otherwise carve them into a separate scoped follow-up commit.
- `verification_exit_code != 0` → diagnose inline; the fix is a forward commit (reviewer finding or impl patch), not a reset.
- `self_assessment == APPROVE` with non-empty `open_concerns` → integrate the patch; dispatch a scoped follow-up to close `open_concerns` before benchmark row marks green.
- HEAD moved during agent's run → inspect the commit. If consistent with wave scope, accept + continue. If not, add a reconciling commit. Never `git reset --hard`.

**Integration flow (evolve-and-fix-forward per core.md §15):**
1. `scripts/wave-sandbox.sh init` (advisory snapshot — stable diff reference, NOT a rollback anchor).
2. Dispatch Agent(s) → collect patches.
3. `scripts/wave-sandbox.sh assert-clean` → if dirty, inspect + reconcile via follow-up commits (never reset).
4. `scripts/pod-apply.sh` (pod) or `git apply` (single-agent) → integrate.
5. `scripts/local-ci.sh --fast` → on failure, dispatch a scoped follow-up or close inline; commit the fix. Never reset.
6. Parallel adversarial review → findings close via follow-up commits in severity order.
7. `scripts/launch.sh --verify` (GUI/FDC3/dist-touching waves only) after all reviewer findings close.
8. Benchmark row marks green in a final outer-workspace commit; push both repos.

**Rollback is banned** as a wave-mechanic. If a wave's direction is wrong at the strategic level (rare), ESCALATE to the user and let them decide; do not `git reset` unilaterally.

## Adversarial review contract

Reviewers return:

```json
{
  "verdict": "APPROVE | APPROVE_WITH_COMMENTS | REWORK | BLOCK",
  "angle": "<the review lens>",
  "findings": [
    { "severity": "BLOCKING|HIGH|MEDIUM|LOW",
      "file": "<path>", "line_range": "NN-MM",
      "summary": "<one line>",
      "disposition_required": "CLOSED|SCOPE_TRANSFERRED|ESCALATED" }
  ],
  "grep_calls_on_code": 0
}
```

`grep_calls_on_code` MUST be 0 — reviewers use CBM on code files. Non-zero rejects the return.

## Review-only personas

`qa-architect`, `security-engineer`, `trading-sme`, `ux-design-lead`, `integration-architect`, `chart-qa-verifier`, `marketplace-qa` have **no** `Write` / `Edit` / `NotebookEdit` in their tools list. They emit findings; impl personas apply fixes.

## No-deferrals (from core.md §8)

Every finding exits as CLOSED, SCOPE-TRANSFERRED, or ESCALATED. Main loop rejects pod returns with findings not dispositioned.

## Small-agent principle

Prefer two agents with 8 objectives each over one agent with 16. Focus scales; monolithic prompts lose focus ~20 objectives in.

## Escape hatches

None for sequential reviewer dispatch — if a reviewer depends on another reviewer's output, decompose the review scope. `DESKMODAL_LAX=1` bypasses the integration gate in emergencies; audit-logged.
