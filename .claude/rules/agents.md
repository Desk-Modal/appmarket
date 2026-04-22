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
| Impl (default) | `claude-sonnet-4-6` | `frontend-architect`, `interaction-designer`, `data-pipeline-engineer`, `charting-expert`, `fdc3-protocol-engineer`, `build-deploy-engineer`, `plugin-sdk-engineer`, `trading-ux-architect`, `service-plugin-exemplar`, `documentation-engineer`, `deskmodal-design-agent`, `marketplace-architect`, `marketplace-ux-engineer`, `npm-registry-engineer`, `verification-gateway-engineer` |
| Trivial | `claude-haiku-4-5-20251001` | `style-bot` (new — token replacements, lint fixes, naming sweeps) |

Impl personas that show REWORK > 1 per 5 iterations get promoted to Opus. Adjust per observed quality.

## Pod patterns

| Pattern | When | How |
|---|---|---|
| **Direct** | Single-domain, one impl agent | Single `Agent` call |
| **Pod** | Multi-domain, disjoint writes, ≤3 impls | Parallel `Agent` batch in one message |
| **Pair** | Backend + frontend slice | 2 parallel Agents; each owns its file set |
| **Pipeline** | One persona, overlapping writes | Sequential calls with handoff |
| **Angle-swarm** | One reviewer persona, multiple lenses | Up to 5 parallel of same persona, each with an angle prompt |
| **Adversarial pod** | Any impl review | All declared reviewers in ONE parallel batch (mandatory) |

Each prompt ≤ 15 concrete objectives. Past that: decompose into more agents.

## Return contract (every impl sub-agent)

```json
{
  "patch": "<unified-diff string>",
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

Main loop rejects returns where:
- `write_set_actual ⊄ write_set_declared`
- `verification_exit_code != 0`
- `self_assessment == APPROVE` with non-empty `open_concerns`

Personas NEVER commit or push their own work — they return patches. Main loop applies patches atomically (see `scripts/pod-apply.sh`).

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
