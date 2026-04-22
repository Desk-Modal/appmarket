# Context Discipline

Applies to the main agent and every sub-agent persona. The rules below
are enforced because a hallucinating or context-starved agent costs the
user money and time, and burns trust faster than a slow one.

## 1. Budget awareness

Handoffs are **commit-driven**, not session-clock-driven. Claude Code's
native auto-compact handles the window-pressure case at ~95% — you do
not need to race it. The only threshold you track manually:

| Metric | Threshold |
|---|---|
| **Conversation token count** | ≥ 70% of window → **advisory**: consider writing a handoff before `/clear` so state survives the compact/clear cycle |

The old 40-tool-call and 30-minute thresholds are retired — they
double-counted what commit boundaries already track. A commit is the
durable checkpoint; see §3 for the new write-triggers.

Never claim "I don't have context room" as an excuse — **write the
handoff, then escalate**. The handoff IS the solution to context
pressure, not a failure mode.

## 2. Evidence gates (no hallucinations)

Every claim about system state must cite one of:

- A file path + line number the claim rests on.
- The stdout/stderr of a command, with its exit code.
- The content of a persisted log / memory file.

The following phrases are **banned** unless immediately followed by a
citation:

- "I believe / I think / probably"
- "should work / ought to"
- "the tests pass" (without the `cargo test` output showing `0 failed`)
- "it's fixed" (without a re-run of the gate that was failing)

If you cannot cite evidence, say "unverified" explicitly and propose the
command that would verify.

Auto-test your own claims when cheap. Example: after an edit, re-run
`cargo check` or the single failing test, then cite that output.

## 3. Session handoff protocol

A handoff is a plain-English state dump a successor session can pick up
without reading any prior messages. Location:
`.session-state/handoff.md` in the workspace root.

Write one at these **three commit-adjacent moments** — no more, no less:

- **After any commit that moves the task forward.** The post-commit
  hook (`.claude/hooks/post-commit-handoff.sh`, wired via
  `PostToolUse:Bash(git commit*)`) auto-appends the commit SHA + short
  message; you edit the rest. If the auto-append already captures
  everything a successor needs, no manual edit required.
- **Before `/clear` or session end with uncommitted state.** The Stop
  hook emits a passive reminder only when the working tree is dirty AND
  >5 files are modified AND no commit has happened this session — the
  usual "probably safe to clear" case stays silent.
- **Before dispatching to an `Agent` sub-agent.** Include the handoff
  path in the sub-agent's prompt so it inherits the dead-end registry.

Everything else — the old 40-tool-call / 30-minute / "every Stop"
triggers — is retired. Commits are the durable checkpoint; the hook is
the mechanism.

A handoff has exactly these sections:

```markdown
# Session handoff — <ISO timestamp>

## Task
<one sentence — what the user asked for>

## Current gate / checklist state
<paste from .prod-check/status.json or equivalent>

## What this session achieved
- <bullet — must cite file paths or gate names>
- <bullet — must cite evidence>

## Dead-ends (do NOT retry these)
- <hypothesis> — <why it was disproved> — <evidence path>

## Open work, in priority order
1. <concrete next step with the exact command>
2. <…>

## Files modified this session
<git status --short output>

## Flags to the next session
- Auth state: <e.g. "sub-agent dispatch requires re-login first">
- Environment: <anything unusual>
```

Before starting work, **read the existing `.session-state/handoff.md`**
if one exists. The SessionStart hook surfaces it automatically.

## 4. Determinism

- Pin toolchain versions via `mise.toml` (already done).
- Avoid raw `sleep` in tests except to wait on an observable signal with
  an explicit deadline.
- Avoid "retry until it works" loops without a cause analysis.
- Every command you run should be reproducible by the next session with
  the exact same arguments and the exact same dist state.

If a test is flaky, **name the flakiness** in the handoff and propose an
isolation strategy — never hide it by retrying.

## 5. Context clearing

When you hit the handoff threshold:

1. Write `.session-state/handoff.md` per §3.
2. Commit or stash in-flight work if the user asked for autonomy.
3. Suggest the user run `/clear` or explicitly re-invoke the loop — do
   not try to "finish one more thing" once the handoff is written; you
   will drift.

When resuming:

1. Read `.session-state/handoff.md` in full before acting.
2. Read `MEMORY.md` index + relevant memory files.
3. Re-run the gate / status command ("Current gate" from the handoff)
   to verify the world still matches. The handoff is a SNAPSHOT, not
   a guarantee.
4. Only then continue work.

## 5b. Tool discipline (enforced by hooks)

These aren't opinions — the PreToolUse hook at
`.claude/hooks/cbm-code-discovery-gate.sh` counts every Grep / Glob /
Read call and escalates:

| Grep/Read calls per session | Hook behaviour |
|---|---|
| 1st call | **BLOCK** with a retry-with-CBM message |
| 10th, 20th, 30th | Reminder to use CBM + consider Agent dispatch |
| 40th | Handoff threshold reached — **write `.session-state/handoff.md` before any further Grep/Read** |

The rule you must follow, in priority order, when you want to find code:

1. **`mcp__codebase-memory-mcp__search_graph`** — by name pattern, label, or natural-language query. This is your default for "where is X defined / where is X called / what does X look like".
2. **`mcp__codebase-memory-mcp__trace_path`** — for call chains / impact analysis.
3. **`mcp__codebase-memory-mcp__get_code_snippet`** — read source by qualified name (~500 tokens, not ~80K).
4. **`mcp__codebase-memory-mcp__detect_changes`** — map git diff to impacted symbols.
5. **`mcp__codebase-memory-mcp__get_architecture`** — crate-level overview.
6. **`Grep` / `Read`** — only for non-code content (markdown, YAML, TOML, JSON, string literals), or as fallback when the graph has no entry.

If you catch yourself reaching for Grep on a `.rs` / `.ts` / `.tsx` /
`.py` file, stop. Use CBM. If CBM returns nothing useful, log that as a
dead-end in the handoff.

## 6. Sub-agent dispatch discipline

**Dispatch trigger** — when ANY of these is true:

- You've spent ≥10 tool calls on one problem without making measurable progress.
- The same hypothesis has failed twice in a row.
- The work is clearly in a different persona's domain (check the routing table in `memory/optiscript_production_gates.md`).
- You'd rather protect the main session's context than grind inline.

**Dispatch hygiene**:

- Pack the prompt with **every relevant fact** — file paths, line numbers, what was ruled out. Sub-agents start with zero context.
- Include the phrase "Read `.session-state/handoff.md` first — it lists the dead-ends you must NOT retry."
- Require the sub-agent to **use CBM before any Grep/Read** — repeat that instruction verbatim in the agent prompt. Sub-agents forget this even more than the main loop does.
- Require the sub-agent to return in the handoff format (§3) — not free-form prose. This keeps its output composable.
- Never dispatch an agent for work you can do inline in <10 tool calls. Dispatch is expensive (~8–15 min per agent) and introduces an uncorrectable failure mode (auth errors, as observed in this project's history).

**Anti-pattern**: dispatching an agent to "figure it out for me" when you haven't defined the exact question. Sub-agents without a tight question fan out to shallow exploration and burn minutes. If you can't write the agent's task in two sentences with concrete file paths, you don't know the question well enough yet — inline a few more tool calls first.

## 7. Enforcement

The SessionStart hook at `.claude/hooks/session-handoff-load.sh`
surfaces the current handoff. The gate runner at
`.claude/scripts/optiscript-prod-check.sh` writes a fresh handoff when
it stops with un-finished work.

Deviations from this rule are hallucination-class defects. Treat them
as such.
