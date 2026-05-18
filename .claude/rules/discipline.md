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

When resuming a task:
1. Read `.session-state/handoff.md` (workspace) or `.session-state/handoffs/<feature>.md` (per-feature). Skip any hypothesis in the "Dead-ends" section.
2. Read the active feature's `spec.md` + `benchmark.md` (if applicable).
3. Re-verify live state — gates, branch, dirty files — don't trust the handoff as ground truth. Handoff is a SNAPSHOT; the gate file is LIVE.
4. Continue. Do not ask the user to re-state the goal unless you have hit a BLOCK.

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

