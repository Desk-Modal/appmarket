---
title: Discipline
authority: derives from `core.md`; topic-file for §9 + §12 + §13 + §14 + §26
load_when: session start/end, between-wave checkpointing, deciding when to push, resuming after `/clear`, deciding when to clear/compress context
---

# Discipline

## 26. Context-window management — clear/compress optimally, never hallucinate, never lose data

**Cardinal directive (user 2026-05-17 verbatim — preserved per §1 honesty rule):** "you should be optimally managing your context windows to minimize token usage, you can clear, compress or whatever is optimal to ensure no hallucincations, no data loss, across sessions, restarts, but optimally planny context clears, research and critique the optimal approache then update our directives, ensure our directives are cohesive"

**Persistence-tier hierarchy** (all 4 tiers used together; never collapse to fewer):

| Tier | Mechanism | Survives | Use for |
|---|---|---|---|
| **1. CANONICAL git** | `.claude/rules/*.md`, `specs/**`, `wiki/**`, memory files committed via auto-memory | Everything (machine, dev, `/clear`, time) | Rules, specs, architectural reasoning, agent definitions |
| **2. DURABLE auto-memory** | `~/.claude/projects/.../memory/feedback_*.md` + `MEMORY.md` index | `/clear`, restart, multi-session, cross-dev `git pull` (per-user copy) | User preferences, anti-pattern discoveries, durable critique-driven rules |
| **3. EPHEMERAL handoffs** | `.session-state/handoffs/<feature>.md` (gitignored; per-repo-dir) | Session restart; not cross-dev | Live in-flight state: reviewer findings, agent IDs, pod plans, BLOCKING dispositions |
| **4. CONVERSATIONAL window** | Current turn-by-turn chat | Until `/clear` or auto-compact ~95% | Active reasoning + tool calls + just-returned agent reports being processed |

**Forbidden anti-patterns (token-waste; from today's audit of my own behaviour):**
- Pasting full reviewer JSON returns into commit messages (use handoff path citation; commit body cites SHA + 1-line summary)
- Reading 300+ line logs (`launch.sh --verify` etc.) when targeted `grep` would suffice
- Inline-quoting full reviewer find-sets in re-dispatch prompts (cite handoff path; agent reads once)
- Re-stating user directives verbatim in every commit (cite §-rule + memory-file once; subsequent commits cite the rule SHA)
- Re-reading `.rs/.ts/.tsx/.py` files with `Read` when CBM `get_code_snippet` is ~500 tokens vs 80K (per architecture.md §3 + §17)
- Not invoking `/clear` at natural checkpoints — burns context on stale conversation history when next pod is unrelated

**Optimal patterns (canonical; apply per /loop wake):**

1. **Audit-by-path discipline** (from core.md §4 — applies workspace-wide): every parallel-agent prompt passes file paths, not inline content. Saves ~30-80K tokens per dispatch × N agents.

2. **Eager handoff write after every reviewer batch:** capture full JSON returns into `.session-state/handoffs/<feature>.md` BEFORE the orchestrator compresses to disposition tags in main context. Cost: 1 Bash append. Saves re-reading reviewer JSON later.

3. **Memory mirror for every cross-session-relevant rule/decision:** if it's worth following next session, it lives in `~/.claude/projects/.../memory/feedback_*.md`. `/clear` doesn't lose reasoning.

4. **Compress in main context, expand in handoff:** main context carries `commit-SHA` + 1-line summary. Handoff carries full report. Anti-pattern: copy-pasting reviewer JSON into the commit message body.

5. **CBM-first for every code question** (architecture.md §3): `get_code_snippet(qualified_name)` ≈ 500 tokens vs `Read(file)` ≈ 80K for typical .rs service file. Same for `search_graph` vs `Grep`.

6. **/clear at natural checkpoint boundaries:**
   - Pod completes + all commits land + `local-ci.sh --fast` rc=0 + no in-flight reviewer findings unhandled + memory mirror written → safe to `/clear`
   - Major directive pivot (today's V1/V2 ban / OptiScript-everywhere / branding / context-mgmt) — write memory mirror first, THEN consider `/clear`

7. **NEVER /clear when:**
   - Reviewer batch in flight (findings not yet in handoff)
   - Mid-pod with uncommitted patches in working tree
   - Unresolved BLOCKING finding not dispositioned per §18.1
   - Within 60s of an agent return (race against auto-notification)

**Session pressure checkpoint (per §9):** at ≥ 70% context utilisation, write fresh handoff before `/clear`. The handoff IS the solution to context pressure, not a failure mode.

**Cross-session resumption contract (per §13 autonomy protocol):** SessionStart hook surfaces:
- Active feature + branch + ahead/behind
- Latest handoff entry
- Recent committed waves

Agent reading the handoff continues without user re-stating intent. The MEMORY.md index lists durable rules; loading on relevance per topic file is the §3-discovery-order optimal path.

**Audit gate (queued):** `quality:context-discipline-self-check` — scans for token-waste anti-patterns in main-loop tool calls (e.g. Read of >5KB log file when grep could suffice; inline-quoting reviewer JSON in commit body). Advisory until promoted.

**Honesty contract under compression (per §1):** every claim STILL cites evidence (file:line / SHA / log path / exit code) even when compressed. Compression compresses VERBOSITY, never CITATIONS. If a claim would lose its citation under compression, expand it first.

**Edit-verification discipline (durable; 2026-05-17 incident lesson):** the Edit tool's "file has been updated successfully" message is NOT a guarantee that the change persisted to disk. Incident 2026-05-17: two consecutive Edit calls on `.claude/rules/architecture.md` both reported success; `wc -l` later showed file unchanged at original size; the §27 content was lost on disk despite green tool responses. Root cause unconfirmed (likely harness cache vs disk race when concurrent agents are in flight, OR a `linter has modified file` post-write hook reverting our diff).

Rules (apply to every critical edit):
1. After ANY Edit on a canonical / rule / spec / commit-bound file, IMMEDIATELY verify via `grep -n "<distinctive-new-string>" <file>` OR `wc -l <file>` (expect new line count).
2. NEVER trust the "successfully updated / file state is current" message alone.
3. If verify fails: re-Read the file fresh (gets current disk state), then re-Edit. Do NOT amend a stale in-memory view.
4. For multi-paragraph inserts: prefer a single Edit with the whole block over multiple smaller Edits — reduces the race window.
5. For canonical-files mid-pod (other agents running): Read fresh BEFORE editing — concurrent agents may have shifted line numbers.

Forbidden: committing a code/rule change without verifying the diff lands on disk (`git diff --stat` shows expected file). Honest failure mode is "Edit lost; re-applying" — never silent "I edited it" without verification.

**Memory mirror:** `~/.claude/projects/-Users-adrian-deskmodal/memory/feedback_context_window_management.md` + `feedback_edit_verification_discipline.md` (durable per cross-session persistence pattern).

**Pairs with:**
- §1 (honesty — every claim cites; compression keeps citations)
- §3 (MCP-first discovery — CBM avoids re-reads)
- §4 (audit-by-path agent dispatch)
- §9 (handoff protocol — durable state between sessions)
- §13 (autonomy protocol — session resume contract)
- §18.7 (always-parallel-always-verify — context held for in-flight work)
- §18.7.2 (never-block continuous-parallel — handoff is the resume primitive)
- §21 (spec-hygiene — specs are CANONICAL persistence; commits update specs)
- §26.1 (continuous SDLC optimization — apply every learning to every surface)

## 26.1 Continuous SDLC optimization — apply every learning to every surface (NEVER FORGOTTEN)

**Cardinal directive (user 2026-05-19 verbatim — preserved per §1 honesty rule):** "ensure we're applying these optimisations to everything used by our SDLC, and all other optimisations, then ensure we remember to always optimise leveraging all of the learnings"

**The rule:** every optimization pattern proven on ONE SDLC surface MUST be applied to EVERY equivalent surface workspace-wide. Optimizations compound; under-applied wins decay. The /loop wake protocol audits the 7 SDLC surfaces below for known anti-patterns BEFORE planning new work.

**7 SDLC surfaces + their optimization patterns (canonical list):**

| # | Surface | Anti-pattern signal | Optimization pattern | Reference |
|---|---|---|---|---|
| 1 | Auto-loaded rules (`.claude/rules/**`) | Any single file > 40K chars OR any deprecated/archive content auto-loaded | Stub + wiki playbook split (`wiki/playbooks/<theme>/`) OR move to `.claude/rules-archive/<date>/` | architecture.md F157 split 2026-05-19; §26 |
| 2 | Auto-loaded CLAUDE.md | > 15K chars OR mirrored content from rules | Pointer + cross-ref only; canonical detail in topic files | §26 tier-1 canonical |
| 3 | Agent prompts (`.claude/agents/*.md`) | > 35 lines body OR re-stated workflow rules | Frontmatter + ≤35-line body; cite `.claude/rules/<file>.md §N` | agents.md model tiering + skills |
| 4 | Sub-agent dispatch (Agent tool) | Inline-quoting audit/spec/finding in prompt | Audit-by-path; agent reads source once | core.md §4 (durable) |
| 5 | Code discovery | Grep/Read on `.rs/.ts/.tsx/.py` OR `wiki/**` | CBM-first / wiki-mcp first per question shape | core.md §3 + architecture.md §30 |
| 6 | Verification (`local-ci.sh --fast`) | Workspace-wide rebuild when scope didn't change | Affected-mode + last-green-SHA diff base | architecture.md §29 |
| 7 | Memory (`~/.claude/.../memory/`) | MEMORY.md > 24KB OR entries > 200 chars | Index ≤ one-line entries; detail in topic memory files | MEMORY.md schema |

**The "apply everywhere" contract:**

When any optimization pattern is proven (lands a wave green, removes a measurable inefficiency, or closes a user-directive), the orchestrator's NEXT /loop wake MUST:

1. **Inventory the 7 surfaces** above for instances of the same anti-pattern.
2. **For each match:** either fix in current wave OR scope-transfer to a named cleanup wave per §18.1.
3. **Codify the pattern** as a memory entry + cross-link to the rule that introduced it.
4. **Add an audit gate** when the pattern is mechanical (e.g., `quality:auto-loaded-rule-size-ceiling` flags any `.claude/rules/*.md` > 40K chars).

**Per-/loop-wake audit hook (extends §26 Step-1):**

Add to the orient step (~10s):

```bash
# Surface 1: rule-tree size
find .claude/rules -maxdepth 1 -name '*.md' -exec wc -c {} + | awk 'END{print "Auto-load rule-tree:", $1, "chars"}'
# Hard threshold: total > 200K = act. Per-file > 40K = act.

# Surface 6: any pre-existing drift?
scripts/local-ci.sh --fast 2>&1 | grep -E '^(FAIL|RED)' | head -5
```

If thresholds breach: add findings to the wave's `open_concerns` with disposition CLOSED-IN-WAVE or SCOPE-TRANSFERRED per §18.1.

**Known patterns to ALWAYS check on /loop wake (the "remember to optimize" register):**

These are the durable optimization patterns that have shipped + the surface they apply to. New entries append; entries never silently disappear.

| Pattern | Origin | Applies to |
|---|---|---|
| Stub-and-playbook split for >40K-char auto-loaded rule | architecture.md split 2026-05-19 (commit e608e32) | Every `.claude/rules/*.md` |
| Move legacy/deprecated rules outside auto-load tree | rules-archive move 2026-05-19 | Future `_deprecated-*/` under `.claude/rules/` |
| Audit-by-path agent dispatch (paths not inline quotes) | core.md §4 amendment 2026-05-16 | Every `Agent()` dispatch |
| CBM-first for code-structure questions | core.md §3 (durable) | Every `.rs/.ts/.tsx/.py` discovery |
| wiki-mcp-first for synthesis questions | core.md §3 + architecture.md §30 | Every governance/inventory/brand question |
| Per-question-shape MCP routing | architecture.md §30 | Every diagnostic / library-doc / visual question |
| Tier A/B/C verification batching | architecture.md §29 + quality.md §18.7.1 | Every wave's verification scope decision |
| Cache-aware ScheduleWakeup (60-270s or 1200-1800s; never 300s) | architecture.md §28 | Every `/loop` heartbeat |
| Warm-agent SendMessage for true continuations | parallelism.md §4 + agents.md | Every wave-N+1 with same persona |
| Per-file ≤300 LOC split-never-cut | architecture.md §24 | Every production source file |
| Per-capability repo + tier metadata | architecture.md §27 | Every new capability |
| Auto-load tree size ceiling (~150-200K chars total) | This rule 2026-05-19 | Every change to `.claude/rules/**` or CLAUDE.md |
| Workspace task list size ceiling — ≤25 active items; aggressively `TaskUpdate status=deleted` completed-historical at every /loop wake; durable audit log lives in `.session-state/handoffs/<feature>.md`, NOT the task list | 2026-05-23 sweep (170→12 tasks; ~85% reminder bloat reduction) | Every /loop wake + session-start |
| Agent dispatch hard caps — ≤3 files write-set, ≤300 LOC/file, ≤5 read paths pre-staged, ≤480s self-imposed budget (600s harness limit is failure not target), Tier-A scope only (no workspace tests, no workspace clippy fix) | F156 G1-W1 timeout 2026-05-19 (commit cycle 4a43cb6) | Every impl `Agent()` dispatch |
| Reviewers ONLY at phase-boundary (read-only parallel pod); world-class verification batched per `quality.md §18.8`, NOT per-wave | F156 phase 1 BLOCK verdict 2026-05-19 | Every wave's APPROVE path |
| Explicit `git stash` ban in every impl-persona prompt + use `git show HEAD:<path>` for baselines | F156 P1-F/G/H all violated stash ban 2026-05-19 | Every impl `Agent()` dispatch |
| LSP/rust-analyzer diagnostics are advisory ONLY — `cargo check` is the verification truth (LSP cache flaps in hot sessions) | F156 multiple stale-LSP false-blocks 2026-05-19 | Every Rust agent return |

**Banned posture:**
- "We'll apply the optimization elsewhere later" — applies to the 7 surfaces NOW or scope-transfers per §18.1.
- "It only matters for X" — every optimization compounds; missed application leaks compound interest.
- Adding a rule/spec/skill without checking auto-load size impact (run `find .claude/rules -name '*.md' -exec wc -c {} +` BEFORE landing).
- Restoring deprecated content into `.claude/rules/**` (it auto-loads; use `.claude/rules-archive/<date>/` instead).

**Memory mirror:** `~/.claude/projects/-Users-adrian-deskmodal/memory/feedback_continuous_sdlc_optimization.md` (durable per cross-session persistence pattern).

**Pairs with:**
- §1 (honesty — never claim "optimized" without measuring the size before+after)
- §26 (context-window management — this rule's parent)
- §18.2 (5-axis hygiene — this rule is the 6th axis: optimization hygiene)
- §18.4 (per-iteration cleanup wave — natural home for this rule's audits)
- core.md §3 + §4 (MCP-first + audit-by-path; both ARE optimizations enforced via this rule)
- architecture.md §28 + §29 + §30 (the three architecture-level optimization rules this rule binds workspace-wide)

## 9. Handoff protocol

Commit-driven. When a commit moves task state, the post-commit hook appends to the active handoff (`.session-state/handoff.md` by default, or a per-feature handoff under `.session-state/handoffs/<id>.md`). You edit free-form context on the next turn if needed.

Session pressure checkpoint: at ≥ 70% of context window, write a fresh handoff before `/clear`. Below that, commits are the durable state; no preemptive handoffs required.


## 12. Tool discipline

- No `--no-verify` on commits unless you've proven the hook is producing a false positive and document the diagnosis in the commit body.
- No `--force` push.
- No deleting branches, files, or data without confirming the state is recoverable.
- No invoking `sync-specs.sh --apply` while another session is actively editing sub-repo canonical files — canonical file ownership is split, see `.claude/rules/parallel-sessions.md`.
- One terminal + one cloud + one `/launch --verify` in flight at a time per machine (launch-lockfile at `/tmp/deskmodal-launch.lock`).


## 13. Autonomy protocol

Goal: user never re-pastes prompts or re-explains context. State lives in git + `.session-state/`.

On session start, the `context-load` SessionStart hook prints: active feature, branch + ahead/behind, gate state, latest handoff entry. Read that before asking the user anything.

When resuming a task per F157 Layer 9 autonomous-SOTA-delivery loop:
1. Read `.session-state/handoff.md` (workspace) or `.session-state/handoffs/<feature>.md` (per-feature). Skip any hypothesis in the "Dead-ends" section.
2. Read the active feature's `spec.md` + `benchmark.md` (if applicable).
3. **F157 Layer 11**: Invoke `/deskmodal-mesh-claim <feature> <program> <write-set-globs>` to declare write-set bounds + check for cross-session conflicts. If conflict, resolve before proceeding.
4. **F157 Layer 11**: Invoke `/deskmodal-mesh-findings` to surface findings from other parallel sessions in the last 24h.
5. Re-verify live state — gates, branch, dirty files — don't trust the handoff as ground truth. Handoff is a SNAPSHOT; the gate file is LIVE.
6. Declare `/effort xhigh` unless the task is mechanical (then `medium`).
7. Declare `/goal <terminal-condition>` if the work has a verifiable end-state.
8. Continue. Do not ask the user to re-state the goal unless you have hit a BLOCK.

When `--resume` or `--continue`: a goal that was active when the session ended is restored. Mesh claim is recreated by SessionStart hook.

Between sessions:
- A commit is the durable checkpoint. Post-commit hook appends to the handoff automatically.
- `.session-state/active-feature` (optional) holds one feature-id string; the statusline surfaces it.
- Never claim "I don't have context" — write a handoff and continue.


## 14. Output style

Claude Code default output style for this workspace is `concise`. Prefer:
- Short, dense sentences. Commands over descriptions.
- State changes and decisions directly. Cite file:line, exit codes, SHAs.
- No teaching tone. No motivational framing. No "let me explain."
- End-of-turn summary = 1-2 sentences MAX. What changed + what's next.
- Working update = 1 sentence per key moment (finding, direction change, blocker).

