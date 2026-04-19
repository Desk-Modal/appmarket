# DeskModal Constitution

> Authoritative workspace-level invariants. Applies to every spec, task, persona,
> and verification path. Supersedes any per-spec or per-session convention.
> Amendments follow the Governance section below.

## Article I — Evidence & Honesty

(Source: `.claude/rules/honesty.md`, `.claude/rules/context-discipline.md` §2)

- **Cardinal rule**: never claim success without proof. "It works" requires a passing test, verified output, or confirmed behavior — not a running process, open socket, or mapped dylib.
- **Verification hierarchy** (strongest → weakest): (1) user-facing outcome, (2) screenshot / visual proof, (3) test output, (4) direct observation (logs, responses, data), (5) CDP / DOM assertion, (6) process inspection (lsof, ps, network), (7) file existence, (8) assumption (NEVER acceptable).
- **Banned phrases unless immediately followed by a citation** (file:line, command stdout + exit code, or log excerpt): "I believe / I think / probably", "should work / ought to", "the tests pass" (without `0 failed`), "it's fixed" (without re-running the failing gate). If you lack evidence, say "unverified" and propose the command that would verify.
- **Attribution rule**: when observing system behavior (connections, memory, file access), identify WHICH component produced it. If you cannot distinguish (e.g., parent process shows child's sockets), say so — never assume attribution.
- **Self-correction protocol**: when a prior statement proves wrong, (1) state clearly what was wrong and why, (2) state what is actually true, (3) fix the root cause, not the symptom, (4) do NOT minimize ("slight overstatement") — call it what it is.
- **User-facing outcome is the only thing that matters**: backend "working" means nothing if the user cannot see the result. Always verify the end-to-end path: service → channel → app → render → user sees it.
- **Never declare completion** — report what changed, what was verified, what was NOT verified. The user decides when a task is done.

## Article II — Context Discipline

(Source: `.claude/rules/context-discipline.md`)

- **Handoff as the single source of live state**: `.session-state/handoff.md` at the workspace root. The SessionStart hook surfaces it; every session reads it before acting.
- **Action thresholds for writing a fresh handoff**: ≥ 70% of context window consumed, OR ≥ 40 tool calls since last durable state, OR ≥ 30 min wall time on a single task with no commit/handoff. Meeting any one threshold triggers a handoff write.
- **Never claim "I don't have context"** — write the handoff, then escalate. The handoff IS the solution to context pressure, not an excuse.
- **Mandatory handoff sections** (§3 of context-discipline.md): Task, Current gate / checklist state, What this session achieved, Dead-ends (do NOT retry), Open work in priority order, Files modified this session, Flags to the next session.
- **Dead-end registry**: hypotheses already disproved in the handoff must not be retried. Re-trying them is a hallucination-class defect.
- **Tool budget enforced by `.claude/hooks/cbm-code-discovery-gate.sh`**: 1st Grep/Read/Glob call is BLOCKED; 10/20/30 trigger CBM reminders; 40 requires a fresh handoff before any further Grep/Read.
- **Determinism**: pin toolchain versions via `mise.toml`; avoid raw `sleep` except to wait on an observable signal with a deadline; never hide flakiness with retry loops — name it in the handoff and propose isolation.

## Article III — Code Discovery (CBM-First)

(Source: `.claude/rules/code-discovery.md`)

- **Graph-first is MANDATORY** for every code question. The indexed graph (codebase-memory-mcp) carries function signatures, call chains, type relations, and cross-file dependencies — text search does not.
- **Tool precedence**: (1) `search_graph` for finding functions/types/routes by keyword or regex, (2) `trace_path` for call chains and impact analysis, (3) `get_code_snippet` to read source by qualified name (~500 tokens, not ~80K), (4) `detect_changes` to map git diffs to impacted symbols, (5) `get_architecture` for crate-level overview, (6) `Grep`/`Read`/`Glob` only for non-code content (markdown, YAML, TOML, JSON, string literals) or as fallback when the graph is empty.
- **Session bootstrap** (every new session): `list_projects()` → `index_status(project=<platform>)` → `index_status(project=<tradesurface>)` → `manage_adr(project=<platform>, mode="get")`. Re-index with `mode="fast"` if stale.
- **Project names are path-derived, per-developer**: CBM encodes the absolute repo path into the project name (e.g. `Users-alice-deskmodal-platform` vs `home-bob-deskmodal-platform`). Never hardcode project names in skills, rules, specs, or prompts — always resolve via `list_projects()`.
- **Auto-reindex is ON**: `mode="fast"` after minor edits; `mode="full"` after structural changes (new crates, moved modules). Absolute paths required by the indexer; compute at invocation time, never bake into committed artefacts.

## Article IV — Verification

(Source: `.claude/rules/verification.md`, CLAUDE.md "Verification Standards")

- **One canonical verification path**: every Verification command in a spec, rule, agent prompt, runbook, or CI workflow uses one of — `scripts/local-ci.sh --fast` (per-commit), `scripts/local-ci.sh --full` (pre-push Rust), `scripts/local-ci.sh --full --sign` (signed plugin touch), `scripts/launch.sh --verify` (end-to-end GUI/FDC3/plugin/dist truth), `scripts/build-dist.sh --sign` (explicit artefact), or `.claude/scripts/optiscript-prod-check.sh` / `scripts/prod-check.sh` (gate runner).
- **`dist/` IS the runtime**: `install_root()` walks from the binary up to find `config/desk.toml`; `target/` has no such marker. Launching from `target/` runs a different code path than teammates and users. Signed plugins are part of the production contract — verifying unsigned hides regressions.
- **CDP closes the loop**: CLI / build success is not user-facing success. `launch.sh --verify` launches DeskModal, asserts apps render, FDC3 channels publish, prices flow end-to-end — no other path does this.
- **Raw `cargo` / `pnpm` / `npm` / `npx` are dev conveniences, not verification**. They do NOT satisfy any Acceptance clause and are flagged by `scripts/audit-verify-discipline.sh` in spec Verification sections.
- **Permitted exceptions** (enumerable, not an escape hatch): `scripts/setup.sh`, `scripts/local-ci.sh`, `scripts/build-dist.sh` and their callees (they implement the pipeline); hook regression tests under `.claude/hooks/tests/*.test.sh`; per-crate developer iteration outside of commit verification; implementation helpers under `scripts/quality-gates/**`, `scripts/lib/**`, `.claude/scripts/**`, `tools/**` (extension-scoped to `*.sh/ps1/cmd/py/rs/toml` only — docs under those roots still audit).
- **Per-line bypass**: `<!-- audit:allow: <non-empty reason> -->` at column 0, same line as the forbidden command. Empty reasons are rejected. Every honoured bypass is appended to `.prod-check/audit-allow-bypasses.log` (git-ignored) for reviewer oversight.
- **CI/CD parity**: `.github/workflows/prod-check.yml` runs `scripts/setup.sh --ci` + gate runner. Local verification hits the same gates — local-green → remote-red divergence kills trust.

## Article V — Parallelism with Determinism

(Source: `.claude/rules/parallelism.md`)

- **Cardinal rule**: parallelism is the default execution mode; determinism is the floor no parallel decision is allowed to break. Every planning decision — task spec, `/loop` iteration, Agent dispatch, review pass — considers parallelism explicitly.
- **Determinism mechanism 1 — worktree isolation**: every Agent dispatched concurrently runs in its own `git worktree` via `Agent(isolation: "worktree")`, pinned to a specific `main` SHA, landing on a dedicated branch. Merge-back conflicts surface as deterministic failures, not silent corruption.
- **Determinism mechanism 2 — declared file-sets**: every task spec's `## Parallelism` section declares Reads, Writes, Concurrent with, Serialise after, Wave eligibility, and Worktree isolation. Specs missing this section are REJECTED at Phase 1. The scheduler refuses to dispatch tasks whose write-sets intersect (or read/write races).
- **Determinism mechanism 3 — single-writer state files**: `.session-state/handoff.md`, `.session-state/loop-state.json`, `.prod-check/status.json`, `.prod-check/workspace.json`, `specs/compat-ladder.yml`, and anything under `specs/tasks/queue/done/` are written by the main `/loop` only. Sub-agents return structured JSON; the main loop merges.
- **Determinism mechanism 4 — task-number integration order**: when N parallel Agents finish a wave, the main loop integrates in task-number order (lowest NNN first), not completion-time order. Same input set → byte-identical integration history.
- **Determinism mechanism 5 — structured JSON outputs**: sub-agents return `{branch, commit_sha, verification_all_passed, evidence_paths, ...}`; the main loop parses JSON, does not interpret prose. Model IDs are pinned on every dispatch.
- **Parallelism is forbidden** for: constitution amendments (`.specify/memory/constitution.md`), compat-ladder amendments (`specs/compat-ladder.yml`), any edit to `.claude/rules/*.md` or `.claude/settings.json`, Phase 4 rework cycle, Phase 6 archive + handoff. Mark these `wave_eligibility: exclusive` or `serial`.
- **Escape hatch**: `DESKMODAL_LAX=1` bypasses enforcement (audit-logged); use only for one-off hotfixes.

## Article VI — Agent Team (Native Claude Code)

(New — reflects the `refactor/native-agent-teams` migration in flight, extends `.claude/rules/agent-team.md`)

- **Native persona location**: every persona is a markdown file at `.claude/agents/<kebab-name>.md` with YAML frontmatter (`name`, `description`, `tools`, `model`). Legacy `specs/personas/*.md` content seeds these; the native directory is the runtime source of truth.
- **Spec-Kit integration**: every task row in `.specify/templates/tasks-template.md` (and every generated `tasks.md`) carries `persona: <kebab-name>` naming the implementation agent and `reviewers: <name>,<name>` naming adversarial reviewers (≥ 1). `/speckit.implement` dispatches via `Agent(subagent_type=<persona>)` and, for each reviewer, `Agent(subagent_type=<reviewer>)` in parallel per wave member.
- **Tool scoping is per persona**: review-only personas have no `Write`/`Edit`/`NotebookEdit` in their `tools` list. Security gets `brave-search` for CVE lookup; Rust gets `rust-analyzer`-class MCPs; visual personas get CDP tooling. Violations are caught at the persona-audit gate.
- **Adversarial review matrix** (from `.claude/rules/agent-team.md`): no code ships without review by a domain-hostile persona. Financial logic REQUIRES `trading-sme` approval (can block). Visual changes REQUIRE `trading-ux-architect`. Every change REQUIRES `qa-architect`. Security-sensitive REQUIRES `security-engineer`.
- **SDLC mandatory workflow**: ORIENT → PLAN → IMPLEMENT → REVIEW → VERIFY → DOCUMENT → COMMIT. No steps optional; no steps deferred.
- **CDP verification is non-negotiable for GUI**: before/after screenshots, `python scripts/cdp-test-runner.py` after deploy, assertions in `scripts/cdp-assertions/*.json`, temporary screenshots deleted after review.
- **Quality gates before commit**: typecheck = 0 errors, tests = all pass, zero BLOCKING/HIGH adversarial findings, CDP green for GUI, memory files current if architecture changed.
- **Every persona carries the context-discipline banner** pointing to `.claude/rules/context-discipline.md`. Sub-agent dispatch hygiene: pack full relevant context, reference the active handoff path, require handoff-format return (§3), require CBM-before-Grep/Read verbatim.

## Article VII — Production Code Discipline

(Source: `.claude/rules/production-code.md`, CLAUDE.md "Code Quality")

- **No TODO / FIXME / HACK / placeholder / demo / stub** in shipped code. Production-grade only.
- **No `console.log`** — use the structured logging service. No `println!` in shipped Rust code outside of CLI entry points.
- **No versioned interfaces** (`FooV2`, `BarNew`) — evolve in place. Single source of truth per concept.
- **No locks**: use `ArcSwap`, `DashMap`, `flume` channels, atomics, or the actor pattern. Zero `Mutex`/`RwLock` in shipped DeskModal code.
- **Error handling on every async operation**; loading states for every async UI; graceful degradation when DeskModal APIs are unavailable.
- **Zero hardcoded absolute paths** in any committed file or generated config: no `/Users/...`, `/home/...`, or `C:\Users\...`. Use `${CLAUDE_PROJECT_DIR}`, `$ROOT_DIR`, or computed relative paths.
- **Adversarial review required** — no self-approving work. A domain-hostile reviewer persona must approve before merge.
- **Incremental builds always** — never rebuild everything when only one component changed. Use `cargo check -p <name>` and `pnpm nx affected` for iteration; the canonical verification path covers full builds.

## Article VIII — Naming

(Source: `.claude/rules/naming.md`)

- **Components**: PascalCase (`OrderBook.tsx`).
- **Hooks**: camelCase with `use` prefix (`useExchangeConnections.ts`).
- **Services**: camelCase (`feed-service.ts`).
- **Types**: PascalCase (`ExchangeAdapter`).
- **Constants**: SCREAMING_SNAKE (`MAX_RECONNECT_ATTEMPTS`).
- **CSS tokens**: `--ts-{category}-{property}` (`--ts-surface-primary`).
- **FDC3 app IDs**: `deskmodal.{name}` (`deskmodal.feeds`).

## Article IX — Dist IS the Runtime

(Source: CLAUDE.md "Dist Output", "Runtime Directory", `.claude/rules/verification.md`)

- **`install_root()` discovery**: the binary walks up from `std::env::current_exe()` (up to 5 levels) looking for the marker file `config/desk.toml` (see `platform/apps/deskmodal-agent/src-tauri/src/main.rs:310`). The first parent containing the marker is the install root; everything else is relative to it.
- **Portable by construction**: `dist/` is self-contained — `DeskModal{.exe}` at the root, `config/desk.toml` marker, `plugins/<id>/...` per installed plugin, `data/` for logs/storage/keys. Copy `dist/` anywhere (USB stick, `/opt/deskmodal-prod/`, tarball) and it runs.
- **User data follows the binary**: logs and storage live at `<install-dir>/data/` (override via `DESKMODAL_DATA_DIR`). `~/.deskmodal/` is only used when `install_root()` falls back to home (no marker next to binary).
- **Flat binary placement**: `DeskModal{.exe}` MUST sit at the root of `dist/`, not under `dist/platform/<os-arch>/`. The dist layout is platform-flat — one OS per dist — not multi-arch fat.
- **Signed plugins are the production contract**: every service cdylib is accompanied by `publisher.pub` (read from the plugin's own dir, `deskmodal-service-host/src/cdylib_runner.rs:425`) and a `<lib>.sig` file. Verifying against an unsigned cdylib hides signature regressions.
- **Verification entrypoint for any GUI / FDC3 / plugin / dist change**: `scripts/launch.sh --verify` — runs `local-ci --full --sign`, `build-dist --release --sign`, then launches and runs the CDP assertion suite. No other path closes this loop.
- **Per-plugin releases** (`--sign`): `dmpkg release` produces signed `.dmpkg` tarballs in `dist/releases/` — the artefact shape the appmarket aggregator consumes.

## Governance

- **Supremacy**: this constitution supersedes per-session convention, ad-hoc READMEs, and persona self-imposed rules. Where a rule file under `.claude/rules/` and this constitution disagree, the rule file is the detailed expansion; the article here is the invariant. Amend both in the same commit when they drift.
- **Amendment process**: a PR that edits this file plus adversarial review by `integration-architect` + `qa-architect` + `security-engineer` (minimum — all three must APPROVE). Article VI (Agent Team) amendments additionally require `maestro-orchestrator` review.
- **Parallelism posture**: constitution amendments are `wave_eligibility: exclusive` per Article V — alone in their wave, no concurrent edits to `.specify/memory/constitution.md`.
- **Version bumps on amendment**:
  - **MAJOR**: principle removal or inversion (breaks an existing invariant).
  - **MINOR**: principle addition (new article, new invariant).
  - **PATCH**: clarification, rewording, source citation fix — no semantic change.
- **Enforcement**: `scripts/audit-verify-discipline.sh` audits Verification sections; the `/loop` refuses specs without `## Parallelism`; the persona-audit gate checks tool scoping per Article VI; `.claude/hooks/cbm-code-discovery-gate.sh` enforces Article III.
- **Escape hatch of last resort**: `DESKMODAL_LAX=1` — audit-logged, for one-off hotfixes only. Any use requires a follow-up PR that fixes the root cause.

**Version**: 1.0.0 | **Ratified**: 2026-04-19 | **Last Amended**: 2026-04-19
