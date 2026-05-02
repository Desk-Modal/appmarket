# Agent dispatch

## Canonical

Personas live in `.claude/agents/<name>.md` with YAML frontmatter (`name`, `description`, `tools`, `model`, optional `color`, `permissionMode`, `memory`). Body is ≤ 15 lines: domain scope + invariants + exit criteria. Central rules come from `.claude/rules/core.md`.

Dispatch: `Agent(subagent_type=<name>, model=<pinned>)`. Claude's native router matches task wording against each agent's `description`.

## Model tiering

| Tier | Model | Use for |
|---|---|---|
| Orchestrator | `claude-opus-4-7` | `maestro-orchestrator` |
| Adversarial review | `claude-opus-4-7` | `qa-architect`, `security-engineer`, `trading-sme`, `ux-design-lead` |
| Architecturally critical | `claude-opus-4-7` | `rust-systems-architect`, `integration-architect` |
| Impl (default) | `claude-sonnet-4-6` | `frontend-architect`, `interaction-designer`, `data-pipeline-engineer`, `charting-expert`, `fdc3-protocol-engineer`, `build-deploy-engineer`, `plugin-sdk-engineer`, `trading-ux-architect`, `service-plugin-exemplar`, `documentation-engineer`, `deskmodal-design-agent`, `marketplace-architect`, `marketplace-ux-engineer`, `verification-gateway-engineer` |
| Trivial | `claude-haiku-4-5-20251001` | `style-bot` (new — token replacements, lint fixes, naming sweeps) |

Impl personas that show REWORK > 1 per 5 iterations get promoted to Opus. Adjust per observed quality.

## Dispatch patterns

Claude Code's native sub-agent system is the dispatch mechanism (`Agent` tool). This section is workflow POLICY for when to use it.

**Default is single-agent per wave.** Opus 4.7 1M-ctx owns cross-stack work end-to-end; contract-edge violations impossible; token cost ~50% vs multi-agent.

| Pattern | When | How |
|---|---|---|
| **Single-agent** (default) | Any wave — one agent owns Rust + TS + CSS end-to-end | One `Agent` call; agent edits in-place; returns unified diff via JSON |
| **Sequenced single-agent** | Rare — if a commit must land before the next step can proceed (e.g. serde shape change that forces downstream TS regen) | Sequential `Agent` calls with a commit between |
| **Pod** (rare exception) | Proven-disjoint write-sets AND zero contract edges between members (style-bot CSS sweep, perf bench wave, independent docs) | Parallel `Agent` batch; `scripts/pod-apply.sh` atomic-merges all patches or rolls back |
| **Angle-swarm** (review only) | One reviewer persona, multiple lenses | Parallel dispatch of same persona with angle-specialised prompts |
| **Adversarial review** (mandatory every wave) | All declared reviewers for the wave | ONE parallel `Agent` batch per core.md §7 |

Reviewers always parallel (read-only, no race risk). Impl single-agent by default.

Each prompt ≤ 15 concrete objectives. Past that: decompose the wave, not the agent.

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
