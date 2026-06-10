---
title: Discipline
authority: derives from `core.md`; topic-file for §9 + §12 + §13 + §14 + §26 + §33
load_when: session start/end, between-wave checkpointing, deciding when to push, resuming after `/clear`, deciding when to clear/compress context
---

# Discipline

Lean topic-file. Each §-anchor below preserves its cardinal invariant + lookup tables in-file; verbose forbidden/optimal lists + incident narratives live in `wiki/playbooks/discipline/*.md` (NOT auto-loaded; queried on demand via `mcp__wiki-mcp__wiki_get_page playbooks/discipline/<theme>`).

## Wiki playbook map

| § | Playbook | Theme |
|---|---|---|
| §26 | `wiki/playbooks/discipline/context-window-management.md` | Forbidden/optimal patterns + /clear-when/never + session-pressure + edit-verification incident + honesty-under-compression |
| §26.1 + §26.2 | `wiki/playbooks/discipline/sdlc-optimization-and-skills.md` | Per-/loop-wake audit bash + 14-row known-patterns register + Skill-tool mechanics |

---

## 9. Handoff protocol

Commit-driven. When a commit moves task state, the post-commit hook appends to the active handoff (`.session-state/handoff.md`, or per-feature `.session-state/handoffs/<id>.md`). Edit free-form context on the next turn if needed.

Session pressure checkpoint: at ≥ 70% context, write a fresh handoff before `/clear`. Below that, commits are the durable state — no preemptive handoffs needed.

## 12. Tool discipline

- No `--no-verify` on commits unless you've proven the hook is a false positive and documented the diagnosis in the commit body.
- No `--force` push.
- No deleting branches, files, or data without confirming the state is recoverable.
- No `sync-specs.sh --apply` while another session is editing sub-repo canonical files — ownership is split (`parallel-sessions.md`).
- One terminal + one cloud + one `/launch --verify` in flight at a time per machine (launch-lockfile `/tmp/deskmodal-launch.lock`).

## 13. Autonomy protocol

Goal: user never re-pastes prompts or re-explains context. State lives in git + `.session-state/`. On session start the `context-load` SessionStart hook prints active feature, branch + ahead/behind, gate state, latest handoff — read that before asking the user anything.

Resume contract (F157 Layer 9 autonomous-SOTA-delivery loop):
1. Read `.session-state/handoff.md` (or per-feature `handoffs/<feature>.md`). Skip any "Dead-ends" hypothesis.
2. Read the active feature's `spec.md` + `benchmark.md`.
3. Declare write-set bounds + check cross-session conflicts (native worktree isolation; single-session default per §33).
4. Surface findings from other parallel sessions (native memory + handoff bus).
5. Re-verify LIVE state — gates, branch, dirty files. Handoff is a SNAPSHOT; the gate file is LIVE.
6. Session runs ultracode (settings `effortLevel: xhigh` + `ultracode: true`, durable — ULTRACODE-FOR-ALL 2026-06-10); no per-session `/effort` downgrade (medium tier retired).
7. Declare `/goal <terminal-condition>` if the work has a verifiable end-state.
8. Continue. Don't ask the user to re-state the goal unless you hit a BLOCK.

`--resume`/`--continue`: an active goal is restored. A commit is the durable checkpoint; the post-commit hook appends the handoff. `.session-state/active-feature` (optional) holds one feature-id for the statusline. Never claim "I don't have context" — write a handoff and continue.

## 14. Output style

Default output style is `concise`:
- Short, dense sentences. Commands over descriptions.
- State changes + decisions directly. Cite file:line, exit codes, SHAs.
- No teaching tone, no motivational framing, no "let me explain."
- End-of-turn summary = 1-2 sentences MAX. What changed + what's next.
- Working update = 1 sentence per key moment (finding, direction change, blocker).

## 26. Context-window management — clear/compress optimally, never hallucinate, never lose data

**Cardinal directive (user 2026-05-17 verbatim — preserved per §1 honesty rule):** "you should be optimally managing your context windows to minimize token usage, you can clear, compress or whatever is optimal to ensure no hallucincations, no data loss, across sessions, restarts, but optimally planny context clears, research and critique the optimal approache then update our directives, ensure our directives are cohesive"

**Persistence-tier hierarchy** (all 4 tiers used together; never collapse to fewer):

| Tier | Mechanism | Survives | Use for |
|---|---|---|---|
| **1. CANONICAL git** | `.claude/rules/*.md`, `specs/**`, `wiki/**`, committed memory | Everything (machine, dev, `/clear`, time) | Rules, specs, architectural reasoning, agent defs |
| **2. DURABLE auto-memory** | `~/.claude/projects/.../memory/feedback_*.md` + `MEMORY.md` index | `/clear`, restart, multi-session, cross-dev `git pull` (per-user copy) | User prefs, anti-pattern discoveries, durable critique rules |
| **3. EPHEMERAL handoffs** | `.session-state/handoffs/<feature>.md` (gitignored; per-repo-dir) | Session restart; not cross-dev | Live in-flight state: findings, agent IDs, dispatch plans, BLOCKING dispositions |
| **4. CONVERSATIONAL window** | Current turn-by-turn chat | Until `/clear` or auto-compact ~95% | Active reasoning + tool calls + just-returned reports being processed |

**Edit-verification discipline (durable; 2026-05-17 incident — Edit "success" ≠ persisted to disk; full narrative in playbook):**
1. After ANY Edit on a canonical/rule/spec/commit-bound file, IMMEDIATELY verify via `grep -n "<distinctive-new-string>" <file>` OR `wc -l <file>`.
2. NEVER trust the "successfully updated" message alone.
3. If verify fails: re-Read fresh (current disk state), then re-Edit. Don't amend a stale in-memory view.
4. Multi-paragraph inserts: prefer one whole-block Edit over many small ones — shrinks the race window.
5. Canonical files mid-pod (other agents running): Read fresh BEFORE editing — concurrent agents shift line numbers.

Forbidden: committing a change without verifying the diff landed (`git diff --stat` shows the file). Honest failure mode is "Edit lost; re-applying" — never silent "I edited it" without verification.

**Honesty under compression (per §1):** every claim STILL cites evidence (file:line / SHA / log path / exit code) even when compressed. Compression compresses VERBOSITY, never CITATIONS.

**Full forbidden/optimal-pattern lists + /clear-when/never rules + session-pressure checkpoint + edit-verification incident narrative:** `wiki/playbooks/discipline/context-window-management.md`. Memory mirrors: `feedback_context_window_management.md` + `feedback_edit_verification_discipline.md`.

**Pairs with:** §1 (honesty) · §3 (MCP-first) · §9 (handoff) · §13 (resume) · §26.1 (apply-everywhere).

## 26.1 Continuous SDLC optimization — apply every learning to every surface (NEVER FORGOTTEN)

**Cardinal directive (user 2026-05-19 verbatim — preserved per §1 honesty rule):** "ensure we're applying these optimisations to everything used by our SDLC, and all other optimisations, then ensure we remember to always optimise leveraging all of the learnings"

**The rule:** every optimization pattern proven on ONE SDLC surface MUST be applied to EVERY equivalent surface workspace-wide. Optimizations compound; under-applied wins decay.

**7 SDLC surfaces (the /loop-wake audit register):**

| # | Surface | Anti-pattern signal | Optimization pattern |
|---|---|---|---|
| 1 | Auto-loaded rules (`.claude/rules/**`) | Any single file > 40K chars OR deprecated content auto-loaded | Stub + wiki playbook split OR move to `.claude/rules-archive/<date>/` |
| 2 | Auto-loaded CLAUDE.md | > 15K chars OR mirrored rule content | Pointer + cross-ref only |
| 3 | Agent prompts (`.claude/agents/*.md`) | > 35-line body OR re-stated workflow rules | Frontmatter + ≤35-line body; cite `.claude/rules/<file>.md §N` |
| 4 | Sub-agent dispatch | Inline-quoting audit/spec/finding | Audit-by-path; agent reads source once (core.md §4) |
| 5 | Code discovery | Grep/Read on `.rs/.ts/.tsx/.py` OR `wiki/**` | CBM-first / wiki-mcp first per question shape |
| 6 | Verification | Workspace-wide rebuild when scope unchanged | Affected-mode + last-green-SHA diff base (architecture.md §29) |
| 7 | Memory | MEMORY.md > 24KB OR entries > 200 chars | Index ≤ one-line entries; detail in topic memory files |

**Apply-everywhere contract:** when any optimization is proven, the NEXT /loop wake MUST (1) inventory the 7 surfaces for the same anti-pattern, (2) fix-in-wave OR scope-transfer per §18.1, (3) codify as a memory entry, (4) add an audit gate when mechanical.

**Per-/loop-wake audit bash + the 14-row known-patterns "remember-to-optimize" register + banned postures:** `wiki/playbooks/discipline/sdlc-optimization-and-skills.md`. Memory mirror: `feedback_continuous_sdlc_optimization.md`.

**Pairs with:** §26 (parent) · §18.2 (5-axis hygiene — this is the 6th axis) · §18.4 (cleanup wave) · core.md §3 + §4 · architecture.md §28 + §29 + §30.

## 26.2 Skill-invocation discipline — use the Skill tool correctly; USE our skills, never hand-roll them

**Cardinal rule:** when a DeskModal skill covers the task, invoke it via the Skill tool — do NOT re-implement its logic inline. Hand-rolling a tier-A verify or a spec amend wastes tokens and drifts from the canonical schema.

**Correct Skill-tool mechanics (terse):** invoke via the `Skill` tool with `skill: <name>` (no leading slash; plugin-namespaced as `plugin:namespace:skill`); pass `args` as a free-form string (skills are NOT typed-parameter APIs); invoke ONLY skills in the session's available-skills list (never invent from training data); a skill body runs synchronously in the main conversation and its `allowed-tools` frontmatter scopes tools while active; if a `<command-name>` tag is already in the turn the skill is ALREADY loaded — follow it directly.

**USE-our-skills mandate (canonical SDLC skills):**

| Task | Invoke (do not hand-roll) |
|---|---|
| Scoped Tier-A verify (`cargo check -p` / `cargo test -p` / `pnpm --filter`) after an impl wave | `deskmodal-verify-tier-a` |
| Atomic spec §6 / benchmark / open-concern update (per §21) | `deskmodal-spec-amend` |

Built-in commands (`/clear`, `/compact`, `/review`, `/security-review`, `/goal`) are NOT skills — they are harness commands; never route them through the Skill tool. Full mechanics detail in `wiki/playbooks/discipline/sdlc-optimization-and-skills.md`.

**Cross-refs:** §26 (persistence tiers) · §26.1 (surface #3 agent prompts) · agents.md §"Skills preloaded".

## 33. Multi-session coordination — native worktree + single-session default

**Stub (Session Mesh retired 2026-06-07 per `feedback_sdlc_lean_toward_native`).** The bespoke filesystem mesh (`.session-state/mesh/` + 8 `scripts/session-mesh/*.sh` + the `deskmodal-mesh-claim`/`deskmodal-mesh-findings` skills) is replaced by native Claude Code primitives: **per-agent/Workflow `isolation:"worktree"`** for FS-level write-set isolation, **single-session default** as the operating posture, and **native auto-memory** as the cross-session findings bus. Cross-session write-set conflict avoidance is handled by worktree isolation + the `parallel-sessions.md` canonical-file-ownership contract; live findings persist via memory tier 2 + handoff tier 3 (§26). No mesh-claim/heartbeat machinery to run.

**Pairs with:** parallelism.md §4 (worktree isolation per dispatch) · parallel-sessions.md (canonical-file ownership) · §26 (persistence tiers 2+3 carry findings).
