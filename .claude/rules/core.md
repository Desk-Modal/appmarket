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
2. **`mcp__wiki-mcp__*`** — cross-cutting synthesis from `wiki/`. First stop for any synthesis question. Tools: `wiki_search`, `wiki_get_page`, `wiki_get_links`, `wiki_check_staleness`, `wiki_get_visual`.
3. **`mcp__rust-analyzer__*`** — for Rust only. Symbol references, hover, diagnostics, rename prep.
4. **`mcp__playwright__browser_*`** — for visual / CDP / DOM verification.
5. **`mcp__github__*`** — for PR / issue / run / workflow queries.
6. **Grep / Read** — fallback only when the MCPs return nothing useful, AND only for non-code/non-wiki content.

Non-code, non-wiki (markdown specs, TOML, YAML, JSON, shell): Grep/Read directly.

**Anti-patterns flagged by hooks:**
- Grep on `.rs` / `.ts` / `.tsx` / `.py` before CBM = hallucination vector.
- Grep / Read on `wiki/**` paths before wiki-mcp = same.

**CBM team-shared graph artifact — explicitly NOT used** (decision 2026-05-17). The 5-reason rationale lives in `wiki/governance/rules-charter.md`. The local CBM cache (`~/.cache/codebase-memory-mcp/*.db`) + on-demand reindex (auto_index ~30s/repo) is sufficient.

Specs and rules are *cited from*, not *discovered through*. Use the active feature spec for current intent; rules/agents for workflow contract; CBM for code; wiki-mcp for synthesis.

## 10. Stop signals

Stop when: the task converges, the user says stop, or a blocker requires human input. Never stop because "I can't verify visually" — find another path (logs, DOM inspection, source read). Never stop without stating what verified vs what didn't.

For **autonomous /goal-driven sessions**: `/goal`'s supervisor evaluator judges each turn against the declared terminal condition; auto-clears on met. Don't stop manually inside an active /goal unless the evaluator says yes or the user intervenes. Per F157 spec at `specs/157-autonomous-delivery-operating-model/spec.md`.

## 11. Persistent autonomous-delivery operating model (F157)

`specs/157-autonomous-delivery-operating-model/spec.md` codifies the 12-layer persistent operating model: Settings (`effort: xhigh` + hooks + concurrency env) / Skills / Agents (25 personas) / Hooks / Slash-command discipline / MCPs + plugins / Cloud orchestration / Memory / Self-orchestration / Honesty + persistence / Multi-session coordination (native worktree isolation, architecture.md §33) / Cost control. Memory mirror: `feedback_f157_autonomous_delivery.md`.

**Discipline matrix for autonomous primitives (Layer 5):**

| When | Use | When NOT to use |
|---|---|---|
| Verifiable terminal condition | `/goal <condition>` (one per session) | Routine impl where Tier A verifies |
| Time-paced re-check | `/loop <interval> <prompt>` | When `/goal` fits |
| Dependency-ordered multi-step graph / fan-out research / context-offload | dynamic `Workflow` tool (ONE phase per invocation; `parallelism.md §4.1`) | One-shot wave (use `Agent`); canonical-file writes (main loop only) |
| All DeskModal work | session ultracode — settings `effortLevel: xhigh` + `ultracode: true` (durable; ULTRACODE-FOR-ALL 2026-06-10) | — medium tier RETIRED; no per-task downgrade |
| Phase-boundary review | `/review` + `/security-review` (native) | Per-wave — use local reviewer pod |
| Cross-stack impl + GUI verify | local `Agent` dispatch | Source edits via cloud (cloud DISABLED per quality.md §18.7 #2) |
| Multi-session work | native per-repo worktree isolation (parallel-sessions.md) | Agent-teams (high cost; experimental) |

## Topic-file index (load on relevance)

Section numbers are **stable anchors** — `core.md §17` and `architecture.md §17` resolve to the same content. The split is structural; numbering preserved so existing citations across `specs/`, agent prompts, hooks, and memory continue to work.

| File | Sections | Load when… |
|---|---|---|
| **[`parallelism.md`](parallelism.md)** | §4 (parallelism + pods + speculation + warm-agent) · §15 (wave discipline — evolve-and-fix-forward; verification cadence; rollback ban) | Planning a wave, dispatching pods, fix-forward vs reset, audit-by-path |
| **[`quality.md`](quality.md)** | §5 (production-code + no-V1/V2 + no-pre-existing-drift) · §6 (naming) · §7 (reviewer matrix) · §8 (no deferrals) · §11 (DESKMODAL_LAX) · §18 (quality discipline — zero tolerance, 5-axis hygiene, marketplace distribution, parallel+verify, cadence batching, never-block resumability, scoped tests + currency, world-class verification) | Reviewing impl, dispatching reviewer pod, closing findings, hygiene-sanity per /loop wake, test scope, world-class terminal checks |
| **[`architecture.md`](architecture.md)** (lean stubs; full in [`wiki/playbooks/architecture/`](../../wiki/playbooks/architecture/)) | §16 + §17 · §19 + §20 · §21 + §23 + §24 · §25 + §27 · §28 + §29 + §30 · §31 + §32 + §33 | Authoring services / plugins / SDKs / OptiScript; platform vs plugins; settings IPC; spec currency; file-split vs cut; repo boundaries; multi-session. Stubs preserve every §-anchor + cardinal directive; query playbooks via `mcp__wiki-mcp__wiki_get_page playbooks/architecture/<theme>` |
| **[`copilot.md`](copilot.md)** | §22 (copilot eval + RAG + persistent learning + multi-model + shared KB) | Any work touching `plugins/copilot/`, RAG indexing, model registry, golden-set eval, persistent memory, deployment topology |
| **[`discipline.md`](discipline.md)** | §9 (handoff protocol) · §12 (tool discipline) · §13 (autonomy protocol — context-load hook + resume contract) · §14 (output style) · §26 (context-window management + SDLC optimization + skill discipline) | Session start/end, between-wave checkpointing, deciding when to push, resuming after `/clear` |
| **[`agents.md`](agents.md)** | Sub-agent dispatch (model tiering, dispatch patterns, return contract) | Dispatching impl or reviewer Agents |
| **[`parallel-sessions.md`](parallel-sessions.md)** | Multi-session isolation contract (CLAUDE_PROJECT_DIR, canonical-file ownership, sync-specs usage, launch lockfile) | Working alongside another local session |

## Authority order

When surfaces conflict, walk down: source code → gate scripts → CBM symbol graph → compat ladder + plugin manifests → `.claude/rules/*.md` + `.specify/memory/constitution.md` → `.claude/agents/*.md` → CBM ADR ledgers → active feature `specs/NNN/spec.md` → wiki → CLAUDE.md → free-form docs. A wiki page conflicting with cited canonical source means the wiki page is stale.

## Mirror discipline

`.claude/rules/**` is canonical at root + mirrored to 7 sub-repos via `scripts/_deprecated-2026-04-23/sync-specs.sh --apply` (on-demand, advisory; rsync `--delete` propagates drops). After editing any rule file or moving content to a wiki playbook: run `sync-specs.sh --apply` from a clean root with no sub-repo session mid-edit on canonical paths. See [`parallel-sessions.md`](parallel-sessions.md) §Canonical file ownership.

## Audit gate

`scripts/audit-core-md-coverage.sh` (BLOCKING in `local-ci.sh --fast`) asserts the auto-loaded rule tree stays lean + complete via three checks: (1) **size CEILING** on `$RULES_DIR/*.md` total chars (replaces the former pre-split LOC floor); (2) **file-agnostic anchor PRESENCE** — every externally-cited §N anchor appears as a heading in ANY rule file OR a §N stub-line in this index (permits relocation/collapse; preserves the §N↔topic-file dual-resolution property); (3) **cardinal-invariant MARKER** check — each must-keep directive string (honesty-citation / verification-path / discovery-order / no-fallback / no-V1-V2 / split-never-cut / OptiScript / branding / service-first / reviewer-matrix / evolve-fix-forward / zero-tolerance-dispositions) appears somewhere in the concatenated tree. Verbose bodies live in wiki playbooks (`wiki/playbooks/{architecture,quality,discipline,copilot}/*.md`) which remain canonical synthesis; the gate counts only the auto-loaded root tree against the ceiling.
