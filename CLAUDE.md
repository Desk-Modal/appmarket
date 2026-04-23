# DeskModal workspace — CLAUDE.md

**SessionStart hook `context-load.sh` surfaces active feature, branch, gate state, and current handoff. Read that before asking the user anything. See `.claude/rules/core.md` §13 (Autonomy protocol).**

## Rules (authoritative)

- `.claude/rules/core.md` — honesty, verification path, discovery order (MCP-first), parallelism, production-code, naming, reviewer matrix, handoff, autonomy, output style.
- `.claude/rules/agents.md` — persona dispatch, pod patterns, return contract.
- `.claude/rules/parallel-sessions.md` — multi-session isolation (`CLAUDE_PROJECT_DIR`, branch discipline, canonical-file ownership, launch-lockfile).

Legacy 12 rule files preserved under `.claude/rules/_deprecated-2026-04-23/` for reference.

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
| `codebase-memory-mcp` | Code symbol / call-chain / impact analysis | `mcp__codebase-memory-mcp__*` |
| `rust-analyzer` | Rust symbol refs, diagnostics, rename prep | `mcp__rust-analyzer__*` |
| `playwright` | Headless browser for GUI / CDP / DOM verification | `mcp__playwright__browser_*` |
| `github` | PR / issue / workflow queries | `mcp__github__*` |

Discovery order per `core.md` §3: CBM → rust-analyzer → playwright → github → Grep/Read. Never skip MCPs for code files.

## Verification (one canonical path)

| Scope | Command |
|---|---|
| Per-commit sanity | `scripts/local-ci.sh --fast` |
| Rust-touching | `scripts/local-ci.sh --full` |
| GUI / FDC3 / plugin / dist | `scripts/launch.sh --verify` (single-instance via `/tmp/deskmodal-launch.lock`) |
| Targeted CDP | `python scripts/cdp-test-runner.py --config scripts/cdp-assertions/<name>.json` |
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

26 personas in `.claude/agents/*.md`. Each: frontmatter (`name`, `description`, `tools`, `model`) + ≤35-line body (Domain + Invariants + Exit criteria).

Model tiering per `.claude/rules/agents.md`:
- **Opus 4.7** — orchestrator, adversarial reviewers (qa-architect, security-engineer, trading-sme, ux-design-lead, chart-qa-verifier, marketplace-qa, integration-architect), arch-critical impl (rust-systems-architect).
- **Sonnet 4.6** — default impl.
- **Haiku 4.5** — `style-bot` (trivial CSS/lint sweeps).

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

- Canonical files (`.claude/`, `CLAUDE.md`, `.mcp.json`, `specs/personas/`) live at root + mirror to 7 sub-repos via `scripts/_deprecated-2026-04-23/sync-specs.sh` (on-demand, not pre-commit-gated).
- Platform's `.claude/` is gitignored — its working tree is the mirror; don't try to commit platform's `.claude/`.
- Before `sync-specs.sh --apply`, verify no sub-repo has uncommitted canonical edits (would be overwritten).

## What NOT to do

- Don't claim "works end-to-end" without CDP evidence path.
- Don't rationalise `rc≠0` as "outside my write-set" — reject the APPROVE.
- Don't commit individual persona patches — personas return patches; main loop applies via `pod-apply.sh`.
- Don't run `scripts/launch.sh --verify` while another session holds `/tmp/deskmodal-launch.lock`.
- Don't invent MCP / Claude Code APIs — confirm in official docs or `--help` output.
- Don't skip handoff-reading on session resume — it's the autonomy mechanism.
