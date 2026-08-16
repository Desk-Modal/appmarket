# DeskModal workspace — CLAUDE.md

**SessionStart hook `context-load.sh` surfaces active feature, branch, gate state, and current handoff. Read that before asking the user anything. See `.claude/rules/core.md` §13 (Autonomy protocol).**

**Resume reference (lodestar-first; SOTA-MASTER sprawl retired 2026-07-01): the cross-session reference is lodestar verified-knowledge (`knowledge_get` / `knowledge_claims` / `knowledge_coverage`) + native auto-memory + the active `.session-state/handoffs/<feature>.md`. Capability/architecture state (what's BUILT) is FACT-derived from code + lodestar — never a hand-maintained status doc. The SINGLE task backlog (open work / milestone / decisions / who-holds-what-repo) is `TRACKER.md` (root) — `DONE` rows cite the pushed SHA + lodestar claim so status stays fact-derived, not drift; facts live in lodestar, TRACKER holds only the work. Do NOT restore the retired `specs/SOTA-MASTER/*` sprawl (30-doc set removed 2026-07-01) — TRACKER.md is the ONE tracker. Parallel sessions coordinate disjoint-by-repo — see `.claude/rules/parallel-sessions.md`.**

## What's native vs augmentation

Claude Code (May 2026) provides natively: `Agent` tool for sub-agents, the dynamic `Workflow` tool (graph-driven background orchestration; see `.claude/rules/parallelism.md §4.1`), hook events (SessionStart/PreToolUse/PostToolUse/Stop/SubagentStop), plugin marketplaces, MCP servers, auto memory, CLAUDE.md, custom skills, `/loop` and `/schedule` scheduling primitives, routines, native `/review` and `/security-review`.

**We augment with:**
- Workflow policy (`.claude/rules/*.md`) — when to dispatch, reviewer matrix, wave discipline
- Personas (`.claude/agents/*.md`) — domain-scoped system prompts with tool scoping
- Atomic multi-agent integration (`scripts/pod-apply.sh` + `scripts/wave-sandbox.sh`) — prevents partial-landing failure modes native doesn't address
- Domain pipeline (`scripts/local-ci.sh`, `scripts/launch.sh`, `scripts/build-dist.sh`) — DeskModal Cargo/Nx/signed-dist specifics
- Feature-scoped handoffs (`.session-state/handoffs/<feature>.md`) — execution state, distinct from native auto-memory's learnings

**We do NOT replicate:** scheduling (use `/schedule` + `/loop`), orchestration primitive (use native `Agent` tool; maestro is workflow policy), code review skill (use native `/review`).

## Rules (authoritative)

- `.claude/rules/core.md` — honesty, verification path, discovery order (MCP-first), parallelism (single-agent default), production-code, naming, reviewer matrix, handoff, autonomy, output style, wave discipline.
- `.claude/rules/agents.md` — dispatch patterns (workflow policy on native `Agent`), return contract.
- `.claude/rules/parallel-sessions.md` — multi-session isolation (`CLAUDE_PROJECT_DIR`, branch discipline, canonical-file ownership, launch-lockfile).

The legacy 12 rule files (superseded 2026-04-23 by the lean topic-file split, then kept under `.claude/rules-archive/2026-04-23/` until they were removed in W5 legacy cleanup) live only in git history now — recover via `git log --diff-filter=D -- .claude/rules-archive` if ever needed.

## Structure

```
<repo-root>/
├── platform/                    # Rust/Tauri FDC3 2.2 desktop agent (own git repo)
├── plugins/
│   ├── tradesurface/            # 8-app charting plugin (own git repo)
│   └── optiscript/              # OptiScript runtime + editor (own git repo)
├── plugin-tools/                # dmpkg CLI (own git repo)
├── marketplace/
│   ├── appmarket/               # Catalog aggregator (own git repo)
│   └── plugin-index/            # Plugin discovery index (own git repo)
├── core-server-api/             # Backend control plane (own git repo)
├── dist/                        # Build output — `scripts/build-dist.sh` populates; IS the runtime
├── scripts/                     # Developer tooling
└── specs/                       # Cross-cutting specs, ADRs, feature benchmarks
```

Each sub-directory is a **separate git repo**, not a submodule. Parallel sessions isolate via `CLAUDE_PROJECT_DIR` + per-repo branches — see `.claude/rules/parallel-sessions.md`.

## MCP servers (`.mcp.json`)

| MCP | Use for | Tool prefix |
|---|---|---|
| `codebase-memory-mcp` | Code symbol / call-chain / impact analysis | `mcp__codebase_memory_mcp__*` / `mcp__lodestar__*` |
| `wiki-mcp` | Cross-cutting **synthesis** layer — governance, brand, naming, design-system, capabilities, playbooks, risks, operations, inventory, targets, entities | `mcp__wiki-mcp__*` |
| `rust-analyzer` | Rust symbol refs, diagnostics, rename prep | `mcp__rust-analyzer__*` |
| `playwright` | Headless browser for GUI / CDP / DOM verification | `mcp__playwright__browser_*` |
| `github` | PR / issue / workflow queries | `mcp__github__*` |

Discovery order per `core.md` §3: **codebase-memory-mcp** (code-structure facts) → **wiki-mcp** (cross-cutting synthesis facts) → rust-analyzer → playwright → github → Grep/Read. Never skip MCPs for code files; never use Grep/Read on `wiki/**` when wiki-mcp answers it. **For any SDK question** (`@deskmodal/sdk-*`, `deskmodal-service-sdk`, `dmpkg` CLI), the SDK's wiki entity page (`wiki/entities/sdk-*.md`) is the symbolic reference — query via `wiki_get_page entities/sdk-<name>` before reading source files. **For lifecycle questions** (install/update/uninstall/start/stop/drain/reload), `wiki_get_page entities/lifecycle-protocol` is the symbolic reference entry point (F125 SOTA).

## Wiki — synthesis layer over canonical sources

`wiki/` (root) + 7 sub-repo `wiki/` mirrors. Built on Karpathy "LLM Wiki" pattern. Schema authority: `wiki/CLAUDE.md`. Currency: per-page `last_verified_against_sha` frontmatter + `evidence_sources`. Gates: `scripts/wiki-lint.sh` + `scripts/wiki-coverage.sh`. Generators: `scripts/wiki-gen-{personas,mcps,compat-ladder,hooks,plugins,tokens,apis,dependencies,cost-model,kpis,migrations,surfaces}.sh` (14 total). Mirror: `scripts/wiki-mirror.sh`. **Reading-order entry points** by audience in `wiki/index.md`.

The wiki is **synthesis over canonical sources, not replacement**. Canonical sources (`.claude/rules/`, `.claude/agents/`, `.specify/memory/constitution.md`, lodestar ADR ledgers, `specs/compat-ladder.yml`, plugin manifests) remain authoritative. Wiki indexes, cross-links, and contextualises them.

## Authority order (when surfaces conflict)

1. **Source code** — ultimate truth.
2. **Gate scripts** (`scripts/local-ci.sh`, `scripts/launch.sh --verify`, `wiki-lint.sh`, `wiki-coverage.sh`) — pass/fail truth.
3. **lodestar symbol graph** — code-structure facts.
4. **Compat ladder + plugin manifests** — cross-stack contracts.
5. **`.claude/rules/*.md` + `.specify/memory/constitution.md`** — workflow + governance.
6. **`.claude/agents/*.md`** — persona scope + tool allowlist.
7. **lodestar ADR ledgers** — architectural rationale.
8. **Active feature `specs/NNN/spec.md`** — current intent.
9. **Wiki** — cross-cutting synthesis (gate-checked, MCP-served).
10. **CLAUDE.md** — onboarding pointers.
11. **Free-form docs / READMEs** — advisory only.

Conflict resolution: walk down the list. A wiki page conflicting with cited canonical source means the wiki page is stale.

## Verification (one canonical path)

| Scope | Command |
|---|---|
| Per-commit sanity | `scripts/local-ci.sh --fast` |
| Rust-touching | `scripts/local-ci.sh --full` |
| GUI / FDC3 / plugin / dist | `scripts/launch.sh --verify` (single-instance via `/tmp/deskmodal-launch.lock`) |
| Targeted CDP (Windows WebView2) | `python scripts/cdp-test-runner.py --config scripts/cdp-assertions/<name>.json` — requires `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--remote-debugging-port=9222"`. Windows-only. |
| **E2E login + full flow (canonical)** | `scripts/run-gui-tests.sh --e2e [--no-build]` — **LANDED**. Builds `--features dev-webdriver` (tauri-plugin-webdriver v0.2.1), launches on `TAURI_WEBDRIVER_PORT=4445`, drives `scripts/webdriver-assertions/login-and-verify.json`: REAL login (`verify@deskmodal.local` → core-server-api **:8080**, the real form — no dev-skip) → authenticated-shell assert → live RunIndicator→indicator-result roundtrip (real plot values) → CreateAlert handler-resolves. **Verification of user-facing flows is E2E-with-login, never mock/unit/LOG-only** (`feedback_e2e_login_verification_standard`). Prereqs: core-server-api up on :8080; `ulimit -n 8192`. Limit: tauri-plugin-webdriver v0.2.1 exposes only the shell `main` handle — plugin-webview DOM not assertable; verify backend roundtrips via Tauri-IPC bridge + desk.log corroboration. |
| macOS WebView inspection | Manual via Safari → Develop → DeskModal (Tauri `devtools` feature is on). Programmatic: `screencapture -x -tpng /tmp/<name>.png` for full-screen sanity. |
| Pod atomic merge | `scripts/pod-apply.sh` (applies N persona patches atomically + verifies integrated state) |

Raw `cargo build|test|check|run` and `pnpm nx build|test` are dev-iteration only — not verification. Do not cite them in Acceptance sections.

## Build targets (use incremental)

| Target | Command |
|---|---|
| Single crate | `cd platform && cargo check -p <name>` |
| Agent binary | `cd platform && cargo build -p deskmodal-agent` |
| Single TradeSurface app | `cd plugins/tradesurface && pnpm nx run @deskmodal/app-<name>:build` |
| Affected TS apps | `cd plugins/tradesurface && pnpm nx affected -t build` |
| Full dist | `scripts/build-dist.sh --sign` |
| Release | `scripts/build-dist.sh --release --sign` |

Never rebuild the workspace when one crate/package changed. Cargo and Nx both do incremental — use them.

## Dist layout (`scripts/build-dist.sh` populates `dist/`)

`dist/` is self-contained + portable. Copy anywhere; DeskModal resolves paths from `install_root()` (walks up from the binary looking for `config/desk.toml`). See `platform/apps/deskmodal-agent/src-tauri/src/main.rs:310`.

- Binary at root: `dist/DeskModal{.exe}` (flat, not nested under `<os-arch>/`).
- `dist/config/desk.toml` — `install_root` marker.
- `dist/plugins/<id>/` — one dir per installed plugin; `plugin.toml` + `app/` + `icons/` + `services/` + `publisher.pub` + signed `.sig`.
- `dist/data/` — user logs + storage + keys (moves with the binary).
- `dist/releases/` — signed `.dmpkg` tarballs (`--sign` only).

Platform-flat: one OS per dist, not multi-arch fat. Library extension picked at build time (`.dll`/`.dylib`/`.so`).

## Agents

24 personas in `.claude/agents/*.md`. Each: frontmatter (`name`, `description`, `tools`, `model`) + ≤35-line body (Domain + Invariants + Exit criteria).

Model: **every persona runs on `claude-opus-4-8`** (policy 2026-05-14 — Sonnet/Haiku tiers retired; Opus 1M ctx dominates the cost trade-off for cross-stack DeskModal waves). See `.claude/rules/agents.md` §Model tiering.

Dispatch: `Agent(subagent_type=<name>, model=<pinned>)`. All reviewers for a task in ONE parallel Agent batch (agents.md §Pod patterns).

## Session workflow

| Phase | Command |
|---|---|
| First setup (any machine) | `scripts/setup.sh` |
| Quick check | `scripts/local-ci.sh --fast` |
| Full CI | `scripts/local-ci.sh --full --sign` |
| Launch DeskModal | `scripts/launch.sh --fast-build` |
| Verify end-to-end | `scripts/launch.sh --verify` |
| Open task | `scripts/task-new.sh <slug> "<title>"` (Spec Kit — use for multi-persona work only) |
| Autonomy loop | `/loop <prompt>` (self-paced) or `/schedule` (cloud cron) |

## Cross-repo coordination

- Canonical files (`.claude/`, `CLAUDE.md`, `.mcp.json`, `specs/personas/`) live at root + mirror to 7 sub-repos via `scripts/sync-specs.sh` (on-demand, not pre-commit-gated).
- Platform's `.claude/` is gitignored — its working tree is the mirror; don't try to commit platform's `.claude/`.
- Before `sync-specs.sh --apply`, verify no sub-repo has uncommitted canonical edits (would be overwritten).

## What NOT to do

- Don't claim "works end-to-end" without CDP evidence path.
- Don't rationalise `rc≠0` as "outside my write-set" — reject the APPROVE.
- Don't commit individual persona patches — personas return patches; main loop applies via `pod-apply.sh`.
- Don't run `scripts/launch.sh --verify` while another session holds `/tmp/deskmodal-launch.lock`.
- Don't invent MCP / Claude Code APIs — confirm in official docs or `--help` output.
- Don't skip handoff-reading on session resume — it's the autonomy mechanism.
