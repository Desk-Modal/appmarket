# Anthropic Claude Code Alignment

This rule codifies which DeskModal agent/team conventions align with
Anthropic's official Claude Code docs (canonical), which we extend
beyond the docs (DeskModal-specific, intentional), and which
Anthropic-native patterns we're adopting.

**Source of truth** (2025-2026):
- [code.claude.com/docs/en/sub-agents](https://code.claude.com/docs/en/sub-agents)
- [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks)
- [code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings)
- [code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp)
- [code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices)
- [code.claude.com/docs/en/agent-teams](https://code.claude.com/docs/en/agent-teams)

## 1. What we match canonically (keep as-is)

| Area | DeskModal | Anthropic | Status |
|---|---|---|---|
| Subagent file location | `.claude/agents/<name>.md` | Same | ✅ |
| Required frontmatter | `name`, `description` | Same | ✅ |
| Tool scoping | `tools:` allowlist + review-only omits `Write/Edit/NotebookEdit` | Same | ✅ |
| Model pinning | `model: opus` / inherit | Same | ✅ |
| Parallel dispatch | Multiple `Agent()` calls in ONE assistant message | Documented as the official parallel primitive (no `batch{}` wrapper) | ✅ |
| Hook events used | `SessionStart`, `PreToolUse`, `PostToolUse`, `Stop` | All canonical | ✅ |
| Hook matcher syntax | `Grep\|Glob\|Read`, `Bash`, `*`, regex | Canonical — pipe-separated exact or JS regex | ✅ |
| Settings shape | `permissions.{allow,ask,deny,defaultMode}`, `env`, `hooks` | Canonical (plus newer `agent` key for default subagent) | ✅ |
| MCP config shape | `.mcp.json` with `${CLAUDE_PROJECT_DIR}` | Canonical substitution variable | ✅ |
| Skills layout | `.claude/skills/<name>.md` or `<name>/SKILL.md` | Both supported | ✅ |
| CBM-first discovery | `mcp__codebase-memory-mcp__search_graph` before Grep/Read | Aligned with "use subagents/MCP to isolate high-volume ops" | ✅ |

## 2. What we extend beyond Anthropic (DeskModal-specific, intentional)

Every extension below is encoded in an existing rule file and has a
hook or regression test enforcing it.

| Extension | DeskModal rule | Anthropic posture | Why we extend |
|---|---|---|---|
| **Mandatory parallel reviewers** | `.claude/rules/agent-team.md` §"Parallel reviewers are mandatory" | Recommended but optional | Sequential reviewer dispatch was the #1 quality slow-down; mandate + audit via Phase-3 single-message contract |
| **Declared read/write sets per task** | `.claude/rules/parallelism.md` §1 (Parallelism section in every spec) | Not documented | Lets the scheduler greedily parallelise without human triage |
| **Single-writer state files** | `.claude/rules/parallelism.md` §3 (`.session-state/handoff.md`, `.prod-check/*`, `specs/compat-ladder.yml`, `specs/tasks/queue/done/`) | Not documented | Sub-agents return structured JSON; main loop merges — no write-after-write race |
| **Deterministic integration order** | `.claude/rules/parallelism.md` §4 (task-number ascending merge-train) | Not documented | Same input → same history byte-identically; critical for team reproducibility |
| **`review_angles` / `impl_angles` frontmatter** | `.claude/rules/agent-team.md` §"Granular reviewer decomposition" / `.claude/rules/parallelism.md` §4 | Anthropic describes angle-dispatch as runtime, not frontmatter | Declaring angles in frontmatter lets the scheduler pre-plan fan-out; Anthropic's runtime pattern is equivalent for cost, but our spec-driven workflow prefers static declarations |
| **No deferrals rule** | `.claude/rules/no-deferrals.md` | Warns against deferral, doesn't forbid | Deferrals were the #1 vector for quality evaporation across waves |
| **Commit-driven handoffs** | `.claude/rules/context-discipline.md` §3 + `.claude/hooks/post-commit-handoff.sh` | Documents `/rewind` + `/clear` instead | Handoffs are a durable state snapshot usable by the next session or a sub-agent; `/rewind` is local-session-only |
| **Spec Kit task queue + `/loop`** | `scripts/task-new.sh`, `specs/tasks/queue/` + `.claude/rules/parallelism.md` §"How the /loop plans waves" | Agent-teams has `~/.claude/tasks/` (simpler, no spec files) | Spec-driven planning + declarative parallelism + merge-train ordering = reproducibility; Anthropic's intent-driven approach doesn't scale to 20-persona team |
| **ADR discipline (in-commit or trailer opt-out)** | `.claude/rules/adr-discipline.md` + `scripts/adr-drift-check.sh` | Not documented | Architectural knowledge decays without codified cadence |
| **Canonical verification path** | `.claude/rules/verification.md` + `scripts/audit-verify-discipline.sh` | Suggests verification, doesn't mandate a path | One path = one CI reality; "works on my machine" defeated by construction |
| **Drift-hash self-heal** | `.claude/hooks/drift-check.sh` | Not documented | Every `git pull` auto-applies env-contract changes — no manual re-setup |
| **Commit-message honesty hook** | `.claude/hooks/commit-message-honesty.sh` | Not documented | Banned phrases + evidence requirement — institutionalises `.claude/rules/honesty.md` |

**All DeskModal extensions are:**
- Additive (Anthropic's engine ignores unknown frontmatter fields).
- Tested (every rule has a `.claude/hooks/tests/*.test.sh`).
- Enforceable (hooks block violations rather than relying on human discipline).

## 3. What we adopt from Anthropic docs (active gaps being closed)

| Anthropic feature | DeskModal adoption | Target |
|---|---|---|
| **`color:` frontmatter** | Add to all 25 personas for visual disambiguation in multi-agent dispatches | `review-only → warm (red/orange/pink)`, `impl → cool (blue/cyan/green)`, `orchestrators → yellow` |
| **`memory: project` frontmatter on reviewers** | Add to 7 review-only personas — accumulates findings across waves without polluting impl context | `qa-architect`, `security-engineer`, `trading-sme`, `chart-qa-verifier`, `marketplace-qa`, `integration-architect`, `ux-design-lead` |
| **`SubagentStop` hook event** | New hook at `.claude/hooks/subagent-stop.sh` — appends completion entry to `.session-state/subagent-completions.log` so the /loop can observe parallel-dispatch fan-in | Wired in `.claude/settings.json` hooks block |
| **`skills:` frontmatter** | Preload `speckit-*` SKILL.md content into implementation personas so they don't re-learn the workflow per dispatch | Impl personas only |
| **`disallowedTools` field** | Belt-and-braces with `tools:` allowlist on review-only personas — explicit deny of `Write`, `Edit`, `NotebookEdit` | Future hardening; optional |
| **`background: true` on long-running subagents** | Use for build-deploy-engineer + verification-gateway-engineer when dispatched on 10+ minute jobs | Per-dispatch, not frontmatter |
| **`permissionMode` frontmatter** | `acceptEdits` on impl personas, `default` on reviewers | Future hardening; optional |
| **`PreCompact` / `PostCompact` hooks** | Write a pre-compact hook that dumps the CBM query cache before compaction so context survives — future work | Not yet prioritised |

## 4. What we intentionally do NOT adopt

| Anthropic feature | Why we skip |
|---|---|
| **Experimental agent-teams feature flag** (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) | Our /loop + Spec Kit cover the same ground with declarative parallelism + merge-train. Agent-teams' teammate-messaging + split-pane display don't fit a 20-persona dispatch model. |
| **`~/.claude/tasks/<team-name>/`** (agent-teams) | We use git-tracked `specs/tasks/queue/` so teammates on `git pull` get the same queue state. Per-user local queues would break reproducibility. |
| **`/rewind` + `/clear` as the primary context-reset** | Our commit-driven handoffs persist state across sessions. `/rewind` is local-only; our handoffs survive machine reboots and are inspectable. |
| **Agent-teams `SendMessage` tool** | Only available inside the experimental agent-teams feature. Our parallel dispatch returns structured JSON to the main loop, not ad-hoc messages. |

## 5. Divergence audit

**Periodic (every 3 months or on a Claude Code major release):**

1. Dispatch `Agent(subagent_type="claude-code-guide")` with a prompt to re-check each row of §1 + §3 against the current Anthropic docs.
2. For any new Anthropic-supported field, evaluate adoption.
3. Update this rule with date-stamped deltas.

**Owner:** `documentation-engineer` (primary) + `integration-architect` (review).

**Ratchet:** this rule is itself hashed by `drift-check.sh` via the
`.claude/rules/*.md` glob — changing it re-runs `setup.sh
--config-only` on teammates.

## 6. Amendment

Amendments follow `.specify/memory/constitution.md` Governance. Required
reviewers: `documentation-engineer` (primary), `integration-architect`
(review), `qa-architect` (CI gate integrity).
