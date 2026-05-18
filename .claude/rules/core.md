---
title: Core rules (index)
authority: 1 of N rule files; index for the lean rule-set
mirrors: .claude/rules/*.md → 7 sub-repos via scripts/_deprecated-2026-04-23/sync-specs.sh --apply
---

# Core rules

Lean index. The four universal sections (Honesty / Verification / Discovery / Stop) live here because every persona reads them on every dispatch. Topic-scoped rules live in sibling files — load on relevance.

## 1. Honesty

Every factual claim cites evidence: a file:line, a command's stdout/stderr + exit code, or a persisted log path. Banned phrases unless immediately followed by a citation: "should work", "tests pass", "I believe", "probably fine". Instead, say "unverified" and propose the command that would verify.

If a claim turns out wrong: state what was wrong, what's actually true, fix the root cause. Don't minimise.

## 2. Verification — one canonical path

| Scope | Command |
|---|---|
| Per-commit sanity | `scripts/local-ci.sh --fast` |
| Rust-touching | `scripts/local-ci.sh --full` |
| GUI / FDC3 / dist touch | `scripts/launch.sh --verify` |
| Targeted visual regression | `python scripts/cdp-test-runner.py --config scripts/cdp-assertions/<name>.json` |
| Perf budget | `cargo bench --bench <bench>` (invoked by launch.sh --verify) |

Raw `cargo build|test|check|run` and `pnpm nx build|test` are dev iteration, not verification. Don't cite them in Acceptance sections.

**`rc ≠ 0` is never APPROVE.** No "failures outside my write-set" rationalisation. Either the failures were pre-existing on `origin/main` with identical signatures (cite the SHA of the passing baseline) or rc=0 is required.

## 3. Discovery order — MCP first, always

Strict priority. **Two MCPs share top tier** — pick by question shape:

| Question shape | First MCP |
|---|---|
| "Where is symbol X / what calls Y / what does Z look like / impact analysis" — **code-structure facts** | `mcp__codebase-memory-mcp__*` (CBM symbol graph) |
| "How does the FDC3 bridge work / what's the brand voice / which persona owns Y / what playbook covers Z / what governance applies / cross-cutting synthesis" — **synthesis facts** | `mcp__wiki-mcp__*` (wiki synthesis layer) |

Then in priority order:

1. **`mcp__codebase-memory-mcp__*`** — code symbol graph; first stop for every code-structure question for `.rs`, `.ts`, `.tsx`, `.py`.
2. **`mcp__wiki-mcp__*`** — cross-cutting synthesis from `wiki/` (84 root pages + 7 sub-repo mirrors). First stop for any synthesis question. Tools: `wiki_search`, `wiki_get_page`, `wiki_get_links`, `wiki_check_staleness`, `wiki_get_visual`.
3. **`mcp__rust-analyzer__*`** — for Rust only. Symbol references, hover, diagnostics, rename prep.
4. **`mcp__playwright__browser_*`** — for visual / CDP / DOM verification. Replaces ad-hoc screenshot scripts.
5. **`mcp__github__*`** — for PR / issue / run / workflow queries. Faster than shelling to `gh`.
6. **Grep / Read** — fallback only when the MCPs return nothing useful, AND only for non-code/non-wiki content.

Non-code, non-wiki (markdown specs, TOML, YAML, JSON, shell): Grep/Read directly.

**Anti-patterns flagged by hooks:**
- Grep on `.rs` / `.ts` / `.tsx` / `.py` before CBM = hallucination vector.
- Grep / Read on `wiki/**` paths before wiki-mcp = same. The wiki has its own MCP for a reason.

**CBM team-shared graph artifact — explicitly NOT used.** CBM v0.6.1 supports committing `.codebase-memory/graph.db.zst` (zstd-compressed snapshot) so teammates skip reindex on first clone. Decision 2026-05-17: **do not enable** for DeskModal. Reasons: (a) auto_index runs in ~30s/repo so the savings are marginal (~4 min total per new-dev onboarding); (b) ~100MB git-history bloat without LFS, LFS dependency complexity with it; (c) cloud workers bypass CBM entirely so they don't benefit; (d) the artifact is a periodic snapshot, not authoritative — creates "is it current?" doubt; (e) `merge=ours` race silently overrides on parallel writes. The local CBM cache (`~/.cache/codebase-memory-mcp/*.db`) is sufficient; reindex on demand is fast enough.

Specs and rules are *cited from*, not *discovered through*. Use the active feature spec for current intent; use rules/agents for workflow contract; use CBM for code; use wiki-mcp for synthesis.

## 10. Stop signals

Stop when: the task converges, the user says stop, or a blocker requires human input. Never stop because "I can't verify visually" — find another path (logs, DOM inspection, source read). Never stop without stating what verified vs what didn't.

For **autonomous /goal-driven sessions**: `/goal`'s supervisor evaluator (Haiku-default small fast model per Claude Code v2.1.139) judges each turn against the declared terminal condition; auto-clears on met. Don't stop manually inside an active /goal unless the evaluator says yes or the user intervenes. Per F157 spec at `specs/157-autonomous-delivery-operating-model/spec.md`.

## 11. Persistent autonomous-delivery operating model (F157)

`specs/157-autonomous-delivery-operating-model/spec.md` codifies the 12-layer persistent operating model:

1. **Settings** — `.claude/settings.json` with `effort: xhigh` + 14 hook events wired + 3 concurrency env vars
2. **Skills** — 11 custom DeskModal skills under `.claude/skills/deskmodal-*/`
3. **Agents** — 25 personas with `effort` + `skills` + `hooks` + `disallowedTools` frontmatter
4. **Hooks** — 12 new scripts (stop-canonical-committed / stop-tier-a-verify / SubagentStart-Stop / TaskCreated-Completed / Pre-PostCompact / StopFailure / InstructionsLoaded / FileChanged / SessionEnd)
5. **Slash-command discipline** — /goal for terminal-condition, /loop for time-paced, /effort xhigh default, /ultrareview at phase boundary
6. **MCPs + plugins** — 7 MCPs + frontend-design + plugin-dev + perf-debug-mcp
7. **Cloud orchestration** — Routines on web for nightly tasks
8. **Memory** — 8 persistence tiers
9. **Self-orchestration** — autonomous SOTA delivery loop per session
10. **Honesty + persistence** — never lose effort, never hallucinate
11. **Session Mesh** — filesystem-backed cross-session coordination at `.session-state/mesh/`
12. **Cost control** — concurrency caps + routine-vs-on-demand routing

Memory mirror: `~/.claude/projects/-Users-adrian-deskmodal/memory/feedback_f157_autonomous_delivery.md`.

**Discipline matrix for autonomous primitives (Layer 5):**

| When | Use | When NOT to use |
|---|---|---|
| Verifiable terminal condition | `/goal <condition>` (one per session) | Routine impl where Tier A verifies |
| Time-paced re-check | `/loop <interval> <prompt>` | When `/goal` fits |
| Cross-stack DeskModal impl | `/effort xhigh` (default) | Mechanical sweeps — use `medium` |
| Phase-boundary review | `/ultrareview` (cloud fleet) | Per-wave — use local reviewer pod |
| Cloud research / markdown | `RemoteTrigger` / `/schedule` | Source edits (.rs/.ts/.tsx/.py/.toml) |
| Multi-session work | F157 Layer 11 Session Mesh | Agent-teams (high cost; experimental) |

## Topic-file index (load on relevance)

Section numbers are **stable anchors** — `core.md §17` and `architecture.md §17` resolve to the same content. The split is structural; numbering is preserved so existing citations across `specs/`, agent prompts, hooks, and memory continue to work.

| File | Sections | Load when… |
|---|---|---|
| **[`parallelism.md`](parallelism.md)** | §4 (parallelism + pods + speculation + warm-agent reuse) · §15 (wave discipline — evolve-and-fix-forward; verification cadence; rollback ban) | Planning a wave, dispatching pods, deciding fix-forward vs reset, audit-by-path discipline |
| **[`quality.md`](quality.md)** | §5 (production-code + no-V1/V2 + no-pre-existing-drift) · §6 (naming) · §7 (reviewer matrix — capability-driven) · §8 (no deferrals — CLOSED / SCOPE-TRANSFERRED / ESCALATED) · §11 (DESKMODAL_LAX escape hatch) · §18 (quality discipline — zero tolerance, 5-axis hygiene, marketplace distribution, parallel+verify, verification cadence batching, never-block resumability, scoped tests + test currency, world-class verification) | Reviewing impl, dispatching reviewer pod, closing findings, hygiene-sanity per /loop wake, deciding test scope, world-class terminal-condition checks |
| **[`architecture.md`](architecture.md)** (lean stubs; full content in [`wiki/playbooks/architecture/`](../../wiki/playbooks/architecture/)) | §16 + §17 (runtime-services) · §19 + §20 (scripting-config) · §21 + §23 + §24 (spec-quality) · §25 + §27 (distribution) · §28 + §29 + §30 (performance) · §31 + §32 + §33 (orchestration) | Authoring services / plugins / SDKs / OptiScripts; deciding what goes in platform vs plugins; choosing settings IPC; verifying spec currency; deciding file-split vs cut; new repo boundaries; multi-session work. Stubs preserve every §-anchor + cardinal directive; query playbooks via `mcp__wiki-mcp__wiki_get_page playbooks/architecture/<theme>` for verbose details |
| **[`copilot.md`](copilot.md)** | §22 (copilot eval + RAG + persistent learning + multi-model + shared KB) | Any work touching `plugins/copilot/`, RAG indexing, model registry, golden-set eval, persistent memory, deployment topology |
| **[`discipline.md`](discipline.md)** | §9 (handoff protocol — commit-driven) · §12 (tool discipline — no --no-verify / --force / parallel sync-specs) · §13 (autonomy protocol — context-load hook + resume contract) · §14 (output style — concise) | Session start / end, between-wave checkpointing, deciding when to push, resuming after `/clear` |
| **[`agents.md`](agents.md)** | Sub-agent dispatch (model tiering, dispatch patterns, return contract) | Dispatching impl or reviewer Agents |
| **[`parallel-sessions.md`](parallel-sessions.md)** | Multi-session isolation contract (CLAUDE_PROJECT_DIR, canonical-file ownership, sync-specs usage, launch lockfile) | Working alongside another local session / cloud lane |

## Authority order

When surfaces conflict, walk down: source code → gate scripts → CBM symbol graph → compat ladder + plugin manifests → `.claude/rules/*.md` + `.specify/memory/constitution.md` → `.claude/agents/*.md` → CBM ADR ledgers → active feature `specs/NNN/spec.md` → wiki → CLAUDE.md → free-form docs. A wiki page conflicting with cited canonical source means the wiki page is stale.

## Mirror discipline

`.claude/rules/**` is canonical at root + mirrored to 7 sub-repos via `scripts/_deprecated-2026-04-23/sync-specs.sh --apply` (on-demand, advisory). After editing any rule file: run `sync-specs.sh --apply` from a clean root with no sub-repo session mid-edit on canonical paths. See [`parallel-sessions.md`](parallel-sessions.md) §Canonical file ownership.

## Audit gate

`scripts/audit-core-md-coverage.sh` (BLOCKING in `local-ci.sh --fast`) asserts every numbered § anchor from the pre-split monolithic core.md is preserved across this index + the 6 topic files + the 6 architecture wiki playbooks at `wiki/playbooks/architecture/*.md`. The LOC floor counts rules + playbook lines together — the 2026-05-19 architecture.md stub-and-playbook split moved verbose content from architecture.md to wiki playbooks; both remain canonical. Any new § added to a topic file appends to the registry; renumbering within a file requires updating cross-references workspace-wide.
