---
title: Architecture
authority: derives from `core.md`; topic-file for §16 + §17 + §19 + §20 + §21 + §23 + §24 + §25 + §27 + §28 + §29 + §30
load_when: authoring services / plugins / SDKs / OptiScripts / branding / new repos / multi-agent dispatch / verification; deciding what goes in platform vs plugins; choosing settings IPC; verifying spec currency; deciding file-split vs cut; deciding repo boundaries + tier metadata + graceful degradation + licensing; ensuring no-edit-loss + accelerated parallel coding; choosing verification scope (only-what-changed); choosing MCP for Rust diagnostics / visual design / library docs / cross-stack discovery
---

# Architecture

## 30. Aggregate MCP capabilities — deterministic Rust + visual-design SOTA (May 2026)

**Cardinal directives (user 2026-05-18 verbatim — preserved per `core.md §1` honesty rule):**

1. "how can we avoid clippy issues up front, can we enable tighter integration with Rust for the ultimate deterministic claude code rust experience. Research and suggest any improvements as may 2026"
2. "and how could we consider the optimal aggregate capabilities with rust-analyzer with our other plugins and mcps? Also are we leveraging the optimal mcps and plugins for visual design as per our apps, research and suggest if there are any improvements"
3. "we need to ensure we do not slow things down too much, research to determine the best mix of results and speed."

**The principle: every code-discovery, diagnostic, library-docs, and visual-verification question dispatches to the MCP whose latency × correctness × scope is optimal for that question shape. The "best mix" is per-question-shape routing, NOT one-MCP-rules-all.**

### 30.1 Registered MCP servers (current — `.mcp.json` 2026-05-18)

| Server | Tool prefix | Primary role | Cost class |
|---|---|---|---|
| `codebase-memory-mcp` (CBM) | `mcp__codebase-memory-mcp__*` | Symbol graph (functions / classes / routes / call-chains / impact) across all 7 indexed repos | ~50-500ms per query |
| `wiki-mcp` | `mcp__wiki-mcp__*` | Cross-cutting synthesis (governance / brand / personas / playbooks / inventory) | ~100-300ms per query |
| `rust-analyzer` | `mcp__rust-analyzer__*` | Rust LSP — type inference, diagnostics, hover, definitions, references, code-actions | ~100-500ms per query (LSP warm) |
| `playwright` | `mcp__playwright__browser_*` | Headless browser — navigate, DOM snapshot, evaluate JS, screenshot, network | ~1-3s per action |
| `github` | `mcp__github__*` | PR / issue / run / workflow queries | ~200-800ms per query |
| `context7` | `mcp__plugin_context7_context7__*` | Official library docs fetch (Cargo deps / npm packages / framework docs) | ~500ms-2s per query |
| `chrome-devtools-mcp` *(if registered)* | `mcp__chrome-devtools-mcp__*` | Lighthouse audits / perf-trace / memory-snapshot / CDP-level inspection | ~5-15s per audit | <!-- audit:allow-naming-tauri-not-decoration: chrome-devtools-mcp official MCP tool name -->

CBM + wiki-mcp share top-tier discovery priority per `core.md §3`. The matrix below extends §3 with rust-analyzer + playwright + context7 + chrome-devtools routing. <!-- audit:allow-naming-tauri-not-decoration: chrome-devtools-mcp official MCP tool name -->

### 30.2 Extended MCP discovery matrix — question-shape routing

| Question shape | First MCP | Why | Speed |
|---|---|---|---|
| "What is the type of X / does this coerce / what's the trait bound" — **Rust type / coercion / borrow-check** | `rust-analyzer` (`rust_analyzer_hover` / `rust_analyzer_workspace_diagnostics`) | LSP holds the real Rust type system — answers compile-time before write | 100-500ms |
| "Where is symbol X / what calls Y / impact of Z" — **cross-stack symbol graph** | CBM (`search_graph` / `trace_path`) | Indexed across all 7 repos including TS + Rust; faster than rust-analyzer for cross-file / cross-language | 50-500ms |
| "How does the FDC3 bridge work / which persona owns Y / cross-cutting synthesis" | wiki-mcp (`wiki_search` / `wiki_get_page`) | Synthesis layer — designed for this | 100-300ms |
| "How do I use cargo-deny / what's the Tauri API for X / which React 19 hook" — **official library docs** | context7 (`resolve-library-id` + `query-docs`) | Up-to-date upstream docs; faster than WebFetch; less stale than training data | 500ms-2s |
| "Render this page / take screenshot / inspect DOM / run axe-core" — **visual + a11y verification** | playwright (`browser_navigate` / `browser_snapshot` / `browser_evaluate` / `browser_take_screenshot`) | Headless Chromium; ARIA tree snapshots; in-page JS eval for axe-core | 1-3s |
| "Lighthouse perf score / memory snapshot / CPU profile" — **perf + heap analysis** | chrome-devtools-mcp (`lighthouse_audit` / `take_memory_snapshot` / `performance_analyze_insight`) | Lighthouse + DevTools profiler integration; playwright lacks lighthouse | 5-15s | <!-- audit:allow-naming-tauri-not-decoration: chrome-devtools-mcp official MCP tool name -->
| "PR status / CI run / issue search" | github-mcp | Native GitHub API access; richer than `gh` shell | 200-800ms |
| "Plain markdown / TOML / YAML / shell file content" | Grep / Read | Non-code; MCPs don't add value | 10-100ms |

**Anti-patterns banned by hooks:**
- Grep on `.rs` / `.ts` / `.tsx` / `.py` files before CBM — hallucination vector
- Grep / Read on `wiki/**` before wiki-mcp
- WebFetch for an officially-documented library before context7
- Manual `cargo check` parse loop when `rust_analyzer_workspace_diagnostics` answers in ~500ms
- Manual screenshot script when `browser_take_screenshot` is two tool calls

### 30.3 Rust-prevention discipline (avoid clippy + type errors up front)

DeskModal's recurrent Rust failure mode is `Arc<dyn Trait>` coercion + lifetime + send/sync errors caught post-write at compile time. Cost: 5-30s per `cargo check -p <crate>` × N retry-edits per wave. Solution: **shift correctness left via rust-analyzer MCP queries BEFORE writing.**

**Three integration tiers (composable; per-persona OPT-IN):**

**Tier 1: Pre-write type query (OPTIONAL, advisory)** — for Rust personas (`rust-systems-architect`, `plugin-sdk-engineer`, `service-plugin-exemplar`) when adding a new function signature, trait impl, or generic bound:
```
mcp__rust-analyzer__rust_analyzer_hover(file, line, col)  -- get inferred type at point
mcp__rust-analyzer__rust_analyzer_definition(symbol)      -- locate trait def + see required methods
mcp__rust-analyzer__rust_analyzer_references(symbol)      -- see how callers expect it
```
Cost: ~100-500ms per query; saves 5-30s per failed `cargo check`. Net win at any time the agent isn't 100% certain about a trait bound.

**Tier 2: Post-edit workspace diagnostics (MANDATORY in agent return contract)** — Rust personas MUST run before claiming APPROVE:
```
mcp__rust-analyzer__rust_analyzer_workspace_diagnostics()
```
Returns full workspace diagnostic list (errors + warnings + clippy lints if `clippy::all` configured in `rust-analyzer.check.command`). Cost: 500ms-2s warm; catches type errors, missing trait impls, unused imports, common clippy lints without spawning a cargo process.

**Tier 3: cargo check -p (MANDATORY in agent return contract)** — final ground-truth before APPROVE:
```
cargo check -p <crate>
```
Cost: 5-30s incremental. Cannot be skipped — rust-analyzer's check is a fast preview, not a substitute for the actual compiler. This is the per `core.md §2` verification authority for Rust changes.

**Combined budget (Tier 2 + Tier 3):** ~5-30s per agent return for Rust waves. Well under wave wall-clock; correctness shifted left by minutes of compile retry.

**Cargo + clippy preflight discipline (cheap):**
- Repo-root `clippy.toml` declares lint level (`warn` for advisory, `deny` for BLOCKING gates)
- Per-workspace `[lints]` in `Cargo.toml` propagates lint config to all members
- `cargo clippy --workspace --all-targets -- -D warnings` enforced at `local-ci.sh --full` Tier C (per `core.md §2`)
- `cargo deny check` for advisory deps + license (per `core.md §2` Rust-touching path)
- Rust personas configure their LSP `rust-analyzer.check.command = "clippy"` so Tier 2 diagnostics include clippy lints proactively

**Trait-object boundary pattern (builder over coercion):**
- Return concrete types from internal functions; coerce to `Arc<dyn Trait>` only at module boundaries (factory / SDK entry points)
- Prefer `impl Trait` returns within crates; reserve `Arc<dyn Trait>` for FFI / dynamic-dispatch edges
- Where dyn-trait return is required: use a builder/constructor pattern that performs the coercion once (`Arc::new(concrete) as Arc<dyn Trait>`) inside the factory, not at every call site
- Applies forward; not BLOCKING for existing code per `core.md §5` (evolve in place; same-wave delete of old surface only when refactoring that surface)

### 30.4 Visual-design MCP optimum (May 2026 SOTA for Tauri/React trading apps)

Two-MCP composition. Each has unique strengths; consolidate-to-one would lose capability.

**playwright-mcp — primary for visual + functional + a11y verification:**

| Question | Tool |
|---|---|
| Render DeskModal at a URL / take screenshot | `browser_navigate` + `browser_take_screenshot` |
| Inspect DOM / ARIA tree (no screenshot — token-efficient) | `browser_snapshot` |
| Run axe-core a11y inside the page | `browser_evaluate` with axe.run() injected |
| Click / type / drag interaction | `browser_click` / `browser_type` / `browser_drag` |
| Network capture (API calls / WebSocket frames) | `browser_network_requests` |
| Pixel-diff regression (compare two screenshots) | `browser_take_screenshot` + downstream pixelmatch |
| Brand-token verification (computed `--deskmodal-*` CSS vars at runtime) | `browser_evaluate` with `getComputedStyle(document.documentElement).getPropertyValue('--deskmodal-accent')` |
| Cross-window FDC3 broadcast smoke | `browser_navigate` + `browser_evaluate` to invoke fdc3 channel APIs |

Speed: 1-3s per action. `--headless` + `chromium` keeps cost low; PLAYWRIGHT_BROWSERS_PATH caches downloads per `.mcp.json`.

**chrome-devtools-mcp — secondary for perf + heap + Lighthouse:** <!-- audit:allow-naming-tauri-not-decoration: chrome-devtools-mcp official MCP tool name -->

| Question | Tool |
|---|---|
| Full Lighthouse audit (perf / a11y / SEO / best-practices score) | `lighthouse_audit` |
| Memory heap snapshot (leak hunt) | `take_memory_snapshot` |
| Performance trace + insight | `performance_analyze_insight` |
| CDP-level navigation / inspection beyond playwright surface | underlying CDP commands |

Speed: 5-15s per audit. Used at logical-impact-batch boundaries (per `core.md §28.6` Tier C) — not per-wave.

**Composition pattern (typical visual-regression wave):**
1. `browser_navigate` to candidate URL — 1s
2. `browser_snapshot` for ARIA + DOM check — 1s (token-efficient; no image bytes)
3. `browser_evaluate(axe.run())` for WCAG 2.2 AA — 2s
4. `browser_take_screenshot` for pixel-diff vs baseline — 1s
5. (impact-batch boundary only) `lighthouse_audit` — 10s

Total per-wave visual cost: ~5s. Per-impact-batch cost: ~15s (adds Lighthouse).

**context7 for library docs (Tauri / React / Vite / Cargo deps):**
- `resolve-library-id` returns the canonical id for a library (e.g. `@tauri-apps/api` → `tauri-apps/api/v2`)
- `query-docs` returns up-to-date upstream documentation snippets
- Use when authoring SDK calls, Tauri commands, React 19 hooks, vite config, candle inference, fastembed
- Faster than WebFetch (no HTML parse); less stale than training data; preferred over speculation

**Existing scripts/cdp-test-runner.py (Windows-only):**
- Retained for Windows WebView2 CDP automation where playwright-mcp's chromium isn't equivalent (uses Tauri's embedded WebView2 directly via `--remote-debugging-port=9222`)
- macOS / Linux paths preferred via playwright-mcp + manual Safari devtools for Tauri-native WebView inspection
- Not obsoleted by playwright-mcp; the two cover different runtime targets (Chromium vs Tauri-WebView2)

### 30.5 Aggregate orchestration — speed-vs-correctness optimum

**The "best mix" answer to user directive #3:** layer the four mechanisms by per-question scope; do not run all four on every Edit; do not run none.

| Mechanism | Scope | Cost | Cadence |
|---|---|---|---|
| **MCP discovery routing (§30.2)** | Every code question | 50-500ms per MCP query (vs 5-80K tokens for Grep+Read) | Every dispatch |
| **rust-analyzer Tier 1 pre-write hover** | Rust personas, when uncertain about a trait bound / type | 100-500ms per query | OPT-IN per persona; advisory |
| **rust-analyzer Tier 2 workspace_diagnostics** | Rust personas in agent return contract | 500ms-2s per call | MANDATORY pre-APPROVE for Rust personas |
| **cargo check -p (Tier 3)** | Rust personas in agent return contract | 5-30s incremental | MANDATORY pre-APPROVE (current rule, unchanged) |
| **PreToolUse-on-Edit rust-analyzer hook** | Every Edit on `*.rs` in declared write-set | +500ms per Edit | OPT-IN per Rust persona; default OFF; enable via env flag |
| **playwright visual snapshot** | UI-touching waves | 1-3s per snapshot | Per-wave for UI changes |
| **chrome-devtools Lighthouse / memory** | Logical-impact-batch boundary | 5-15s per audit | Tier C per `§28.6` | <!-- audit:allow-naming-tauri-not-decoration: chrome-devtools-mcp official MCP tool name -->
| **context7 library docs** | When authoring SDK / framework calls | 500ms-2s per query | On-demand per dispatch |

**Speed budget per wave (Rust impl):** Tier 2 (1-2s) + Tier 3 cargo check -p (5-30s) ≈ **6-32s total prevention** for ~minutes of saved retry. Net acceleration: dominant.

**Speed budget per wave (UI impl):** playwright snapshot + axe-core eval (3-5s) + token-efficient ARIA tree (1s) ≈ **4-6s total verification** for full a11y + visual confirmation.

**Speed budget per logical-impact-batch (UI):** add Lighthouse audit (10s) + optional memory snapshot (5s) = **15-20s** at phase boundary only.

**Optional PreToolUse-on-Edit-rust hook (.claude/hooks/post-edit-rust-diagnostics.sh):**
- Fires AFTER any Edit on `*.rs` in declared write-set
- Queries rust-analyzer for diagnostics scoped to that file
- Surfaces errors / warnings as advisory output to the persona before next tool call
- OPT-IN via env flag `DESKMODAL_RUST_LSP_HOOK=1` to avoid the +500ms per-Edit overhead on personas not touching Rust
- Rust personas (`rust-systems-architect`, `plugin-sdk-engineer`, `service-plugin-exemplar`) default ON; other personas OFF

### 30.6 Per-persona MCP routing requirement

Update `agents.md` Return contract — Rust personas MUST cite Tier 2 + Tier 3 verification in their return JSON:

```json
{
  "verification_command": "scripts/local-ci.sh --fast",
  "verification_exit_code": 0,
  "rust_analyzer_diagnostics": {
    "tool": "mcp__rust-analyzer__rust_analyzer_workspace_diagnostics",
    "errors": 0,
    "warnings": 0,
    "clippy_lints": 0
  },
  "cargo_check_per_crate": [
    { "crate": "deskmodal-order-engine", "rc": 0 },
    { "crate": "brand-service", "rc": 0 }
  ]
}
```

Non-Rust personas (frontend-architect, ux-design-lead, charting-expert) skip the Rust block; UI personas include a `visual_verification` block citing playwright snapshot path + axe-core score.

### 30.7 Plugin gaps — capabilities currently unmet (advisory; not blocking)

| Need | Current solution | Future improvement |
|---|---|---|
| Tauri runtime state inspection (window lifecycle / IPC channels / plugin state) | Manual `tauri::AppHandle` reads via Rust agents | Tauri-MCP authoring queued (advisory; not blocking; the alternative is rust-analyzer + CBM on `tauri-app::*`) |
| Cargo incremental build orchestration beyond rust-analyzer | `cargo check -p` shell calls | Sufficient via §29 incremental verification + Tier 3 contract; no Cargo-MCP needed |
| Cross-platform WebDriver GUI test orchestration | `tauri-plugin-webdriver` documented but not landed (per `core.md §2`) | F-WebDriver feature spec; W3C WebDriver via Tauri plugin is the SOTA path; no MCP needed |
| OptiScript runtime introspection (compiled binary / capability grants / audit chain) | Manual via rust-analyzer + CBM on optiscript-runtime crate | OptiScript-MCP authoring queued in F147 wave plan (advisory) |

No MCPs blocked from landing per this rule; queued gaps are tracked for future authoring waves.

### 30.8 BLOCKING audit gates queued (F155 follow-up)

- `quality:rust-agent-return-contract` — Rust persona returns MUST cite `rust_analyzer_diagnostics` + `cargo_check_per_crate` blocks; missing = reject
- `quality:mcp-routing-discipline` — scans agent dispatch prompts for Grep/Read on `.rs` / `.ts` / `.tsx` / `.py` / `wiki/**` paths before CBM/rust-analyzer/wiki-mcp; advisory until promoted
- `quality:ui-agent-visual-evidence` — UI persona returns MUST cite playwright snapshot path + axe-core score for any user-visible change

### 30.9 Cascading amendments queued

- `core.md §3` discovery order — extend with §30.2 question-shape matrix (one-liner cross-ref to §30)
- `agents.md` Return contract — add §30.6 Rust + UI verification blocks
- `.claude/hooks/post-edit-rust-diagnostics.sh` NEW — OPT-IN per-persona PreToolUse-on-Edit hook
- `.claude/settings.json` — declare hook wiring; per-persona `DESKMODAL_RUST_LSP_HOOK` env flag default
- `.claude/agents/rust-systems-architect.md` + `plugin-sdk-engineer.md` + `service-plugin-exemplar.md` — set `DESKMODAL_RUST_LSP_HOOK=1` default in agent prompt
- F155 master spec (NEW) — aggregate MCP capabilities + Rust prevention + visual-design SOTA + 3 audit gates

### 30.10 Anti-patterns banned

- Dispatching a Rust agent without Tier 2 (rust-analyzer workspace_diagnostics) + Tier 3 (cargo check -p) in return contract
- Running `cargo check --workspace` per-wave when Tier 3 `cargo check -p <crate>` covers the changed crate (per `§29` incremental)
- Using playwright for Lighthouse audits (chrome-devtools-mcp has the native integration) <!-- audit:allow-naming-tauri-not-decoration: chrome-devtools-mcp official MCP tool name -->
- Using chrome-devtools-mcp for routine screenshots (playwright is 5× faster) <!-- audit:allow-naming-tauri-not-decoration: chrome-devtools-mcp official MCP tool name -->
- WebFetch for officially-documented libraries when context7 has them
- Grep on `wiki/**` paths — always wiki-mcp
- Grep on `.rs`/`.ts`/`.tsx`/`.py` for symbol discovery — always CBM first
- Adding a per-Edit rust-analyzer hook globally (the +500ms per Edit on non-Rust personas is waste)

### 30.11 Cross-references

- `core.md §1` (honesty — every diagnostic claim cites MCP tool + exit code)
- `core.md §2` (verification — one canonical path; rust-analyzer is preview, cargo is authority)
- `core.md §3` (MCP-first discovery — §30 extends with rust-analyzer + playwright + context7 routing)
- `agents.md` Return contract — extended per §30.6
- `architecture.md §28.6` (Tier A/B/C verification cadence — chrome-devtools-mcp at Tier C boundary) <!-- audit:allow-naming-tauri-not-decoration: chrome-devtools-mcp official MCP tool name -->
- `architecture.md §29` (incremental-only verification — Tier 3 `cargo check -p` scoped per §29.1 changed scope)
- `quality.md §18.7.1` (verification cadence — rust-analyzer Tier 2 is part of Tier A agent-self)
- `parallelism.md §4` (audit-by-path dispatch — pass MCP query results as paths, not inline content)

**Memory mirror:** `~/.claude/projects/-Users-adrian-deskmodal/memory/feedback_mcp_aggregate_capabilities.md` (durable per cross-session persistence pattern).

**Pairs with §28 (durability + acceleration) + §29 (incremental verification) + `core.md §3` (MCP-first discovery) + `agents.md` (return contract per-persona MCP routing) + `quality.md §18.7.1` (Tier A/B/C verification batching).**

---

## 29. Incremental-only verification — never rebuild what hasn't changed

**Cardinal directive (user 2026-05-17 verbatim — preserved per §1 honesty rule):** "deskmodal was built to allow incremental builds, and we should only rebuild something if it's actually changed... Update our processes so they're optimal" + "we need to ensure we're not waiting to determine issues slowly"

**The principle: every verification command MUST be scoped to what actually changed since the last green run.** Workspace-wide rebuilds are wasteful and serve only as confirmation at logical-impact-batch boundaries (per §28.6 Tier C).

### 29.1 Change-detection contract

Before any verification dispatch, the orchestrator computes the **changed scope** since the last green checkpoint:

```bash
# Files changed since last green run (default: HEAD~1; or .session-state/last-green-sha)
CHANGED_FILES=$(git diff --name-only HEAD~1..HEAD)

# Affected Cargo crates (parse Cargo.toml from changed files)
AFFECTED_CARGO=$(echo "$CHANGED_FILES" | xargs -I{} dirname {} | sort -u | xargs -I{} sh -c 'cd {} && cargo locate-project --workspace 2>/dev/null' | jq -r '.workspace_root' | sort -u)

# Affected Nx projects
AFFECTED_NX=$(pnpm nx show projects --affected --base=HEAD~1 --head=HEAD)

# Touched plugin.toml manifests
TOUCHED_MANIFESTS=$(echo "$CHANGED_FILES" | grep 'plugin\.toml$')
```

### 29.2 Per-gate change-gating rules

Every gate in `scripts/local-ci.sh` MUST short-circuit if its scope is unaffected:

| Gate | Skip when |
|---|---|
| `platform:rust:fmt` | no `*.rs` files changed under `platform/` |
| `platform:rust:clippy` | no `*.rs` or `Cargo.toml` files changed under `platform/` |
| `platform:rust:test` | no `*.rs` or `Cargo.toml` files changed under `platform/` |
| `tradesurface:rust:*` | no `*.rs` files changed under `plugins/tradesurface/services/` |
| `tradesurface:ts:typecheck` | no `*.ts(x)` files changed under `plugins/tradesurface/` |
| `tradesurface:ts:build` | no `*.ts(x)` files changed; `--filter` by `nx affected` for partial build |
| `optiscript:rust:*` | no `*.rs` files changed under `plugins/optiscript/` |
| `quality:bundle-coherence` | no `plugin.toml` files changed |
| `quality:bundle-dependency-graph` | no `plugin.toml` files changed |
| `quality:fdc3-targetapp-shape` | no `*.ts(x)` files changed under `plugins/*/apps/` |
| `quality:design-tokens-complete` | no `*.css` or `*.tsx` files changed |
| `quality:design-system-and-screens` | no `*.tsx` files changed |
| `prod-check:platform:fast` | no platform Rust/Cargo changes |
| `prod-check:optiscript:fast` | no optiscript Rust/Cargo changes |

Skipped gates print `SKIP: <gate-name> (no changes since last-green)` — explicit, not silent.

### 29.3 Last-green checkpoint discipline

`.session-state/last-green.sha` records the last SHA at which `local-ci.sh --fast --full-rebuild` returned rc=0. Subsequent runs use this as the diff base:

```bash
LAST_GREEN_SHA=$(cat .session-state/last-green.sha 2>/dev/null || git rev-parse HEAD~1)
CHANGED_FILES=$(git diff --name-only "$LAST_GREEN_SHA..HEAD")
```

On green run completion, write current HEAD SHA back:
```bash
git rev-parse HEAD > .session-state/last-green.sha
```

`.session-state/last-green.sha` is gitignored (per-machine cache). Lost cache → assume HEAD~1 baseline (still incremental for current wave; full rebuild only if 0 files changed).

### 29.4 Three verification modes

| Mode | Flag | Scope | Cadence | Cost |
|---|---|---|---|---|
| **Affected** (DEFAULT) | `--fast` | Only gates with changed scope | Every wave commit | 5-30s typical |
| **Workspace** | `--fast --full-rebuild` | All gates (current local-ci.sh --fast) | At phase boundary | 2-5 min |
| **Pre-push** | `--full --sign` | Full Rust + GUI + sign + bench | Pre-push only | 10-15 min |

`--fast` (default) is incremental. `--fast --full-rebuild` is the override for phase-boundary confirmation. `--full` always runs full-fidelity per §28.6 Tier C.

### 29.5 Per-app incremental build commands

For app-scope work, use the app's own build command instead of workspace-wide:

```bash
# Per-app TS build (Vite incremental; 5-30s typical)
pnpm nx run @deskmodal/app-chart:build
pnpm nx run @deskmodal/app-watchlist:build

# Per-crate Rust build (Cargo incremental; 5-30s typical)
cargo check -p deskmodal-order-engine
cargo check -p brand-service

# Per-package TS test (vitest scoped; 3-15s)
pnpm --filter @deskmodal/sdk-config test
pnpm --filter @deskmodal/sdk-brand test

# Nx affected across multiple apps
pnpm nx affected -t build --base=HEAD~5 --head=HEAD
pnpm nx affected -t test
```

### 29.6 Cache-warming discipline (per §28.4)

Cargo `target/`, Nx daemon graph, Vite buildcache, TypeScript `.tsbuildinfo` MUST survive across waves. **Forbidden** during /loop session:
- `cargo clean` / `nx reset` / `rm -rf target/` / `rm -rf node_modules/` / `pnpm install --force`

Permitted ONLY at deliberate reset points (`scripts/setup.sh --reset`) or pre-release (`build-dist.sh --release` once).

### 29.7 The `scripts/local-ci-affected.sh` helper (NEW)

```bash
#!/usr/bin/env bash
# Runs only the gates whose scope is touched since last-green checkpoint.
# Usage: scripts/local-ci-affected.sh [--base <sha>]
set -euo pipefail
BASE="${1:-$(cat .session-state/last-green.sha 2>/dev/null || git rev-parse HEAD~1)}"
CHANGED=$(git diff --name-only "$BASE..HEAD")
# Dispatch per-scope gates only if affected
[ -n "$(echo "$CHANGED" | grep -E '^platform/.*\.rs$')" ] && bash scripts/gate-platform-rust.sh
[ -n "$(echo "$CHANGED" | grep -E '^plugins/tradesurface/.*\.rs$')" ] && bash scripts/gate-tradesurface-rust.sh
# ... etc per gate
echo "rc=$? — incremental gates only"
```

### 29.8 Anti-patterns banned

- Re-running `local-ci.sh --fast` workspace-wide between every wave when only one crate changed
- `cargo test --workspace` when only one crate's tests are affected (use `cargo test -p <crate>`)
- `pnpm nx run-many -t test` when `nx affected -t test` would suffice
- Building dist (`build-dist.sh`) per wave (Tier C is logical-impact-batch boundary only)
- Workspace-wide `tsc --noEmit -p .` when `pnpm --filter <pkg> tsc` covers the change
- Running gates whose scope is provably unaffected (waste; failure mode is FAIL on pre-existing drift unrelated to wave)

### 29.9 Cascading amendments queued

- `scripts/local-ci.sh` — add `--full-rebuild` flag + per-gate change-gating
- `scripts/local-ci-affected.sh` NEW — incremental dispatcher
- `.session-state/last-green.sha` — checkpoint (gitignored)
- F154 build-strategy.md amendment — cite §29 as canonical authority

**Pairs with:**
- `core.md §2` (verification — one canonical path)
- `quality.md §18.7.1` (Tier A/B/C batching cadence)
- `architecture.md §28.4` (incremental cache discipline)
- `architecture.md §28.6` (Tier A/B/C verification cadence)
- `parallelism.md §15` (wave discipline)

**Memory mirror:** `feedback_incremental_only_verification.md`.

## 28. Deterministic + accelerated + perfect coding for mission-critical multi-agent (NEVER FORGOTTEN)

**Cardinal directive (user 2026-05-17 verbatim — preserved per §1 honesty rule):** "we do not want to lose updates, but we don't want to waste time, repeating slow processes.. we want the optimal deterministic, accelerated and perfect coding experience for massive mission critical products like DeskModal"

**The core insight: git is the ONLY durable state; working tree is ephemeral. Five invariants compound to give perfect determinism + maximum acceleration with zero update loss.**

### 28.1 Auto-commit-per-edit on canonical surfaces (durability)

Every Edit/Write on canonical files MUST land on disk **and in git** within seconds, before any subsequent action that could lose it.

**Canonical surfaces (auto-commit BLOCKING):**
- `.claude/rules/**` (all rule files)
- `.claude/agents/**` (all persona definitions)
- `.claude/settings.json` + `.mcp.json` (workflow config)
- `.specify/memory/**` (constitution + memory ledger)
- `specs/**/spec.md` + `specs/**/benchmark.md` (active feature specs)
- `CLAUDE.md` (workspace onboarding)

**Workflow:**
1. `Read <file>` to load fresh disk state into context (ALWAYS read fresh for canonical mid-pod per §26 #5)
2. `Edit/Write <file>` with the new content
3. `grep -n "<distinctive-new-string>" <file>` to verify diff landed (per §26)
4. `git add <file>` IMMEDIATELY (within same Bash invocation if possible)
5. `git commit -m "wip(canonical): <reason>"` (squash-merged at wave-boundary)

`scripts/wave-commit.sh <file> "<reason>"` automates steps 4-5 atomically.

**Why this is mandatory:** the 2026-05-17 incident (lost §27 architecture.md edits 2× consecutively) was caused by an agent's `git stash --keep-index` capturing my unstaged edits + the stash-pop failing. Staged content is safe from `stash --keep-index`; committed content is fully durable.

### 28.2 Forbid `git stash` of orchestrator state (per §28.1)

Agents in declared write-sets MUST NOT execute `git stash` against the outer workspace's working tree during pod execution. This was the root cause of the 2026-05-17 edit-loss incident.

**Codified in `agents.md` return contract:** every agent's verification protocol explicitly forbids:
- `git stash` / `git stash --keep-index` / `git stash push` on canonical files
- `git stash pop` (which can fail mid-pop and lose state)

**Allowed alternatives for agent baseline verification:**
- `git worktree add /tmp/agent-baseline-<id> origin/main` — fresh tree; doesn't touch ours
- `git show HEAD:<file>` — extract file content without stashing
- Direct read of file at specific SHA: `git cat-file -p HEAD:<file>`

### 28.3 Per-agent worktrees for parallel pods (FS-level isolation)

For pods with N≥3 agents touching declared-disjoint write-sets in the SAME repo, dispatch each agent in its own `git worktree add` instance. Eliminates write-set conflicts at the filesystem level; orchestrator integrates via merge-train per `parallelism.md §15` evolve-and-fix-forward.

**Pattern:**
```bash
# orchestrator pre-dispatch
git worktree add /tmp/wave-N/agent-A -b feat/wave-N-agent-A origin/main
git worktree add /tmp/wave-N/agent-B -b feat/wave-N-agent-B origin/main
# ... up to 7

# orchestrator passes CLAUDE_PROJECT_DIR per agent
Agent(subagent_type=..., prompt="cwd=/tmp/wave-N/agent-A; ...")

# orchestrator post-return: merge-train per parallelism.md §15
git merge --no-ff feat/wave-N-agent-A
git merge --no-ff feat/wave-N-agent-B
# ... fix-forward each
```

Single-repo pods of 2 or N≤2: in-tree edits are safe (no race). Worktrees overhead unjustified.

Cross-repo pods (e.g. plugins/tradesurface + platform + plugin-tools): in-tree per-repo edits are safe (different .git/index).

### 28.4 Incremental cache discipline — never `cargo clean`, never `nx reset`

Cargo's `target/`, Nx's distributed cache, Vite's buildcache, TypeScript's `.tsbuildinfo` are the second-largest accelerator after CBM (per architecture.md §3 discovery order). They survive across waves IF you run scoped commands.

**Forbidden during a /loop session:**
- `cargo clean` (destroys 5-30 min of compile cache)
- `nx reset` (destroys Nx daemon graph cache)
- `rm -rf target/` (same as `cargo clean`)
- `rm -rf node_modules/` (destroys pnpm content-addressable cache too)
- `pnpm install --force` (re-downloads + re-builds; slow path)

**Permitted (only at well-documented reset points):**
- `scripts/setup.sh --reset` (deliberate fresh setup)
- `cargo build --release` only at pre-release dist build (per `scripts/build-dist.sh --release`)

**Scoped commands (warm-cache):**
- `cargo check -p <crate>` — ~5-30s; keeps Y warm
- `cargo test -p <crate>` — same
- `pnpm --filter @deskmodal/<pkg> test`
- `pnpm nx affected -t test` (uses git base for diff)

**Workspace-wide (per `quality.md §18.7.1` Tier B):** ONCE per phase boundary, never per-wave. `cargo test --workspace` warm-cache is ~2-10 min; without warm-cache it's 20+ min.

### 28.5 Audit-by-path dispatch + warm-agent SendMessage (token acceleration)

**Already codified in `parallelism.md §4`; emphasised here for §28 completeness:**
1. Every parallel-agent prompt passes **file paths**, not inline content. Agent reads the path once. Saves 30-80K tokens per dispatch × N parallel = 150-400K wasted tokens at N=5.
2. **Warm-agent reuse via SendMessage** for true continuations (same persona + loaded context). Saves ~30-50K cold-start re-read tokens per dispatch.
3. **Speculative N+1 dispatch** (per `parallelism.md §4`) — while wave N reviewers run, dispatch wave N+1 against current HEAD. Discard on REWORK. Saves 10-20 min per wave.

### 28.6 Verification cadence — Tier A/B/C batching (acceleration without correctness loss)

Already codified in `quality.md §18.7.1`. Reiterated here as the §28 SOTA pattern:

| Tier | Scope | Cadence | Cost |
|---|---|---|---|
| **A. Agent-self** | Agent's own write-set (one crate/package) | EVERY wave (mandatory) | ~30s per agent |
| **B. Phase-boundary** | Integrated wave-batch | ONCE per phase boundary | 2-5 min |
| **C. Pre-push / pre-release** | Workspace-wide full-fidelity + GUI/CDP | ONCE pre-push for `--full`; ONCE per logical-impact batch for `launch.sh --verify` | 10-15 min + 5-10 min |

**Never:**
- Re-run Tier B per-wave (50+ min wasted per phase at N=10)
- Re-run Tier C per-wave (10-15 min × N = hours wasted)
- Background-poll for completion when the harness notifies on completion (per `discipline.md §26` anti-patterns)

### 28.7 Stale-agent recovery via SendMessage

If an agent is stuck >30 min (typically in `until grep` polling loops, or compile timeouts), `SendMessage(to: <agent-id>)` with an "ABORT polling, return now with partial state" directive. Codified workflow:

1. Check agent's `.output` file mtime — if no update >30 min, suspect stalled
2. Tail last 100 lines via `tail -100 <agent-output-file>` to see what it's stuck on
3. SendMessage with explicit instruction: stop polling + return partial JSON now + cite what's on disk
4. Wait 60s for agent to return; if still no return, treat as REWORK and dispatch fresh agent

**Today's case (2026-05-17 F151 W3):** agent stuck since 21:59 in `until grep -qE "test result|error..."` polling 2 empty bash background tasks. SendMessage nudge sent; agent should return within 60s.

### 28.8 Edit-verification triple-check (durability + zero-loss)

Per `discipline.md §26 Edit-verification`:
1. Edit → grep verify → wc/diff verify → `git add` immediately → `git commit` to wip
2. NEVER trust "successfully updated" alone
3. For canonical mid-pod: Read fresh BEFORE edit (concurrent agents may have shifted line numbers)
4. For multi-paragraph inserts: prefer ONE Edit over many (race window minimised)

### 28.9 Cache-aware ScheduleWakeup intervals (Anthropic prompt-cache discipline)

Per `core.md §3` + ScheduleWakeup tool description:
- 60-270s delays stay in cache (5-min TTL); use for active polling of external state harness can't notify on
- 300s is the worst-of-both (cache miss + only 5 min wait)
- 1200-1800s — pay one cache miss, get 20-30 min idle; right for fallback heartbeats
- Default for idle ticks (no specific signal): 1500s. Right for "/loop wake-up with no event"

### 28.10 The `scripts/wave-commit.sh` helper (NEW; durability-as-tool)

```bash
#!/usr/bin/env bash
# Atomic stage + commit canonical-file edits before any further action.
# Usage: scripts/wave-commit.sh <file> "<reason>"
set -euo pipefail
FILE="${1:?file required}"
REASON="${2:?reason required}"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE not found"; exit 1; }
git add "$FILE"
git diff --cached --quiet "$FILE" && { echo "noop: $FILE already committed"; exit 0; }
git commit -m "wip($FILE): $REASON

Auto-staged per architecture.md §28.1 durability rule.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>" >/dev/null
echo "wip-committed: $(git rev-parse --short HEAD) $FILE"
```

Called from main-loop right after every critical Edit on canonical surfaces.

### 28.11 BLOCKING audit gates (queued)

- `quality:no-canonical-uncommitted` — at end of every /loop iteration, no canonical-file changes uncommitted (verifies §28.1 compliance)
- `quality:no-cargo-clean-mid-loop` — git log scan for `cargo clean` invocations during /loop session (verifies §28.4 compliance)
- `quality:agent-no-stash` — agent return contract scan for `git stash` calls (verifies §28.2 compliance)

### 28.12 Cascading rule amendments

- `discipline.md §26` (Edit-verification) — already codified; §28 references it
- `parallelism.md §4` (audit-by-path + warm-agent + speculative N+1) — already codified; §28 references it
- `parallelism.md §15` (wave discipline + merge-train) — already codified; §28 leverages it
- `agents.md` Return contract — add §28.2 stash-forbidden invariant
- `quality.md §18.7.1` Tier A/B/C cadence — already codified; §28 references it
- `.claude/settings.json` permissions — add deny rule for `git stash` in agent allowed-tools

### 28.13 The session-coherent invariant

Every /loop wake's first 3 actions:
1. `Read .session-state/handoff.md` — context state
2. `git status --short` — uncommitted canonical state (should be 0 per §28.1)
3. Identify in-flight agents + nudge stalled ones per §28.7

Every /loop wake's last 3 actions:
1. Audit-by-path dispatch next pod (pairwise-disjoint write-sets per `§4`)
2. `git push origin main` opportunistically (each completed wave)
3. ScheduleWakeup 1200-1800s fallback heartbeat per §28.9

**Memory mirror:** `~/.claude/projects/-Users-adrian-deskmodal/memory/feedback_deterministic_accelerated_coding.md` (durable; NEVER FORGOTTEN per user directive).

**Pairs with:**
- `core.md §1` (honesty — verify before claim)
- `core.md §3` (CBM-first discovery — fastest accelerator)
- `parallelism.md §4 + §15` (parallel dispatch + wave discipline)
- `quality.md §18.7.1 + §18.7.2 + §18.7.3` (verification cadence + never-block + scoped tests)
- `discipline.md §26` (context-window + edit-verification)
- `architecture.md §17 + §24 + §27` (plugin architecture + file-size + per-capability repos)

---

## 27. Per-capability repo + tier metadata + graceful degradation + footprint + licensing

**Cardinal directives (user 2026-05-17 verbatim — preserved per §1 honesty rule):**

1. "we should create repos optimally and through best practice with our plans to evolve individual components with AI Coding, but then considering which capabilities are optional/required/etc"
2. "it's critical that nothing breaks if capbilities are not installed, but this should be handled optimaly. indeed if it's more logical to make capabilities required we should still consider our targets of making sure deskmodal an optimal on memory usage and installation size so users can step up and down capabilities based on their requirements and resources, also enabling deskmodal to license capbilities seperately"

### 27.1 One repo per capability

Each independently-installable `.dmpkg` capability lives in its own git repo at `github.com/Desk-Modal/<capability-id>`. Outer workspace tracks specs+rules+wiki+scripts only; `plugins/*/` are gitignored mount-points each holding an independent clone. Cross-capability shared `Cargo.toml` or `package.json` root forbidden (exempt: plugin-tools/ + platform/).

### 27.2 Tier metadata in plugin.toml [bundle] (F148 W2 landed)

- **REQUIRED** — default-installed; can't uninstall (price-feed / brand-service / chart / notifications-center / order-engine)
- **RECOMMENDED** — default-installed; user can uninstall (alerts / watchlist / screener / feeds / enricher / news / earnings)
- **OPTIONAL** — marketplace opt-in (copilot / collab / orderflow / optiscript-editor / analytics / depth / 5×new-* / brand-editor)

Tier informs install flow + CI gates + audit-bundle-coherence cross-validation.

### 27.3 AI-driven evolution invariants

- One AI agent = one repo per dispatch (bounded write-set + clean diff)
- Cross-capability via outer-workspace specs + atomic per-repo wave commits
- Independent semver per capability; marketplace tracks per-capability
- Independent CI/CD per repo
- PR per capability per evolution

### 27.4 Cross-capability coordination

FDC3 contracts in `plugin-tools/typescript/packages/@deskmodal/fdc3/`; SDK surfaces in `plugin-tools/typescript/packages/sdk-*`. Capabilities CONSUME via `@deskmodal/*` aliasing through `sdk/typescript/` symlink workspace.

### 27.5 F153 migration of plugins/tradesurface legacy monorepo

19 capabilities → 19 standalone repos via `git filter-repo` history preservation. 6 waves: W0 GitHub remotes for existing 10 capability repos (8 lack remotes); W1 REQUIRED-tier extract; W2 RECOMMENDED; W3 OPTIONAL; W4 tradesurface-bundle → meta-plugin; W5 workspace mount-points + per-repo CI/CD; W6 audit-gates promotion.

### 27.6 Repo creation checklist (every new capability)

1. Repo at `github.com/Desk-Modal/<id>` (NOT inside existing monorepo)
2. Local clone at `plugins/<id>/` (gitignored from outer)
3. plugin.toml `[plugin]` + `[bundle]` (tier + lead + member_of + unlocks)
4. plugin.toml `[license]` + optional `[license.commercial]` (per §27.12)
5. plugin.toml `[resources]` (per §27.11)
6. plugin.toml `[dependencies]` (per §27.10)
7. Own Cargo.toml/package.json — never shared root
8. Per-repo `local-ci.sh --fast` scope + GitHub Actions
9. License declared + README + llms.txt for AI discoverability

### 27.10 Graceful degradation — nothing breaks when capability is uninstalled

Every consumer code path runtime-detects capability presence + degrades gracefully when absent:

1. **FDC3 `findIntent()` BEFORE `raise()`** for any OPTIONAL/RECOMMENDED capability dependency. Empty result = capability not installed → render disabled state + "Install <capability>" CTA via marketplace (per F125 lifecycle). Forbidden: `raise()` without prior `findIntent()` for non-REQUIRED capabilities.

2. **Sentinel UI patterns (in `@deskmodal/ui-components`):**
   - `<CapabilityRequired capability="copilot">…</CapabilityRequired>` — disabled placeholder + install CTA when absent
   - `<CapabilityOptional capability="collab" fallback={<…/>}>…</CapabilityOptional>` — fallback when absent
   - Cmd+K HIDES (not greys) commands from uninstalled capabilities
   - Toolbar buttons REMOVED when capability uninstalled

3. **Service-side (Rust):** `ServiceClient::has_grant("deskmodal.copilot.events")` before broadcast; no-op when absent; never hard-fail.

4. **Cross-capability deps declared in plugin.toml:**
   ```toml
   [dependencies]
   required = ["deskmodal.price-feed"]                    # REQUIRED-tier guarantee
   recommended = ["deskmodal.notifications-center"]       # fallback if absent
   optional = ["deskmodal.copilot"]                       # disabled if absent
   ```
   F125 lifecycle enforces `required` invariant before activation.

5. **Hot-swap install/uninstall:** broadcast `deskmodal.lifecycle.installed`/`uninstalling`/`uninstalled` → dependent apps refresh capability detection. No DeskModal restart. Running state preserved in sdk-storage namespace `service:<id>:state`.

### 27.11 Memory + install footprint — step up / step down

**Targets (measured per F146 distribution spec):**
- **REQUIRED only:** ≤ 80 MB disk + ≤ 250 MB RAM idle
- **RECOMMENDED default-install:** ≤ 220 MB disk + ≤ 450 MB RAM
- **All OPTIONAL installed:** ≤ 1.5 GB disk + ≤ 1.2 GB RAM (incl. F150 copilot models)

**Invariants per capability:**
1. **Lazy-load** — services autostart only when ≥1 FDC3 channel subscriber (per F125 lifecycle).
2. **Asset on-demand** — icons / fonts / models pulled from sdk-storage cache on first use.
3. **Resource profile declared** — `plugin.toml [resources] disk_mb / ram_mb_idle / ram_mb_peak / cpu_pct_steady`. Verified per F146 W3 bench.
4. **Step-down UX** — Settings → Resource Usage panel + uninstall affordance for capabilities exceeding user-set caps (per F149 sdk-config `deskmodal.resources.cap_*`).
5. **Step-up UX** — Marketplace auto-suggests RECOMMENDED-tier install when free RAM > capability's `ram_mb_peak` × 2.

### 27.12 Per-capability licensing — independent license + payment models

```toml
[license]
spdx = "Apache-2.0"
notice = "© 2026 Acme Capital, Inc."
terms_url = "https://acme.example/license"

[license.commercial]                       # optional — paid capabilities
model = "subscription"                     # subscription | per-seat | per-api-call | one-time | trial
price_usd_per_month = 99.00
trial_days = 14
license_check_endpoint = "https://api.acme.example/license/verify"
required_grants = ["network:acme.example"]
```

**License-token verification:**
1. Commercial capabilities require Ed25519-signed token from publisher's server.
2. Token cached at `dist/data/licenses/<capability-id>.token` (sig + expiry + entitlements).
3. Re-verify on each DeskModal boot + every 24h background.
4. Expired/revoked → capability installed but FDC3 intents return `license_expired` → consumer renders "License expired" CTA linking to billing portal.

**Free / Trial / Subscription / Per-API-call routing:**
- Free (Apache 2.0 / MIT / permissive): no token; install immediately
- Trial: 14-day signed grant; user identifier hashed via F141 audit chain
- Subscription: endpoint check; credentials via OsKeychainStore (§5)
- Per-API-call: F141 chain logs metered usage; publisher reconciles

**Marketplace publishing:** Verification Gateway enforces `[license]` presence; signed `.dmpkg` carries terms; users see license + price before install.

**Enterprise:** site-wide tokens at `dist/data/licenses/_enterprise.token`; Admin Settings UI propagates via core-server-api; F143-D OrderAuditLog logs every check.

### 27.13 BLOCKING audit gates (queued F153 W6)

- `quality:per-capability-repo` — every `plugins/<id>/` has own .git + GitHub remote OR is on F153 migration list
- `quality:capability-tier-declared` — every plugin.toml [bundle] declares tier ∈ {REQUIRED, RECOMMENDED, OPTIONAL}
- `quality:no-cross-capability-shared-root` — no shared Cargo.toml / package.json (exempt: plugin-tools/ + platform/)
- `quality:graceful-degradation` — scans for `raise(` without prior `findIntent(` for OPTIONAL/RECOMMENDED deps
- `quality:resources-declared` — every plugin.toml has [resources] block
- `quality:license-declared` — every plugin.toml has [license]; commercial additionally [license.commercial]
- `quality:dependencies-declared` — every plugin.toml has [dependencies] required/recommended/optional

### 27.14 Cascading spec amendments (queued)

- **F153 master spec** (NEW) — repo migration + graceful degradation + footprint + licensing (6+ waves)
- **F125 lifecycle amendment** — install/uninstall hot-swap + capability-detection broadcast
- **F146 distribution amendment** — footprint targets verified per release
- **F148 architecture amendment** — `[dependencies]` schema + cross-capability graph
- **F149 sdk-config amendment** — `deskmodal.resources.cap_*` + `deskmodal.licenses.*` namespaces
- **F151 copilot amendment** — license-gated intent dispatch
- **Every plugin spec** — declare `[resources]` + `[license]` + `[dependencies]` blocks

**Pairs with §17 (plugin invariants) + §18.4.1 (marketplace signed) + §20 (sdk-config) + §25 (branding REQUIRED) + §16 (no-fallbacks — graceful degradation is USER-VISIBLE STATE not silent fallback) + F125 lifecycle + F141 audit chain + F143-D OrderAuditLog.**

**Memory mirrors:** `feedback_per_capability_repo.md` + `feedback_graceful_degradation_footprint_licensing.md` (durable; cross-session persistence).

## 25. Branding — single brand capability across every surface + OS conformance (NEVER FORGOTTEN)

**Cardinal directive (user 2026-05-17 verbatim — preserved per §1 honesty rule):** "we need to ensure we have a single theming experience via the brands capability, optimally implemented across the editor, then in the settings to select brands, market to download published brands, ensuring the brands cover the entirety of the possibilities of plugins, deskmodal, windows designs, icons and every other point to ensure we have a fully configurable, brandable experience in the most intuitive way, then ensuring all plugins, all windows, fully adhere to the branding services, updating as brands are updated or installed, research competitor stlying and ensure we can create the worlds most beautiful state of the art platform and experience across DeskModal and any FDC3 plugin, but certainly making our trade surface experiences richer, absolutely stunning and bettering our competition in every way. Update our directives to include this concisely so it's never forgotten" + follow-up: "then plan to spec this full experience, including how it works across our host operating systems so they conform, yet can be evolved with the power of DeskModal."

**The rules — single brand capability authoritative for ALL visual surfaces (OS-native conformance + DeskModal evolution):**

1. **`brand-service` cdylib (REQUIRED tier)** — single canonical broadcast source of brand state. Every plugin / window / app surface subscribes via `@deskmodal/sdk-brand` hooks; ZERO bespoke theming in plugin source.

2. **`@deskmodal/sdk-brand` SDK surface (F152 W2):**
   - `useBrand()` — current brand metadata (palette / typography / radii / iconography / motion / window-decoration tokens / OS-conformance overrides)
   - `useBrandTokens()` — flat `--deskmodal-*` CSS token map
   - `useBrandAssets(category)` — icons / logos / chart-glyphs / cursor / loading-spinner per current brand
   - `useBrandOsConformance()` — OS-specific override layer (macOS accent / Windows accent + system theme / Linux GTK theme bridge)
   - `subscribeBrand(handler)` — live update channel
   - Rust service-side: `ServiceClient::brand()` → same surface via FDC3 channel

3. **Brand schema (comprehensive — covers entirety of visual surface):**
   - **Palette:** primary / accent / surface / surface-elevated / text / text-muted / success / warning / danger / info (OKLCH-defined, dark + light variants)
   - **Typography:** font-family-sans / mono / display + scale + weights + tabular-nums overrides
   - **Spacing:** 4px grid base + scale (4/8/12/16/24/32/48/64)
   - **Radii:** sharp / soft / pill (radius-0/4/8/12/full)
   - **Motion:** spring (stiffness/damping per category) + duration (200/350/500ms)
   - **Glassmorphism:** dual-blur radius + opacity for floating layers
   - **Iconography:** icon-family (optical / outline / filled) + size scale + per-category overrides
   - **Window decorations:** title bar styling within Tauri-native constraints per §17 — brand styles content BELOW the native title bar, not the bar itself
   - **Chart styling:** candle up/down / grid / axis / crosshair / drawing-tool / heatmap palette / VPVR / TPO
   - **Trading-specific:** price-up / price-down / fill-confirmed / order-pending / alert-fired / risk-warning / killswitch-engaged tokens
   - **Cursor / loading / empty-state / error / brand-mark** asset overrides

4. **OS-native conformance + DeskModal evolution (dual-layer):**
   - **Conformance layer:** brand reads OS-native accent + dark/light + reduced-motion + high-contrast + reduce-transparency preferences via `tauri::os` API. Default brand DERIVES from OS preferences so DeskModal feels native on macOS / Windows / Linux out of the box.
   - **Evolution layer:** user-installed brand OR per-plugin brand OVERRIDES the conformance defaults. SDK exposes `useBrandOsConformance()` returning `{os_accent, os_theme, os_reduced_motion, os_high_contrast}` so brand designers can choose CONFORM vs EVOLVE per token.
   - macOS: title bar respects Tauri-native decorations (per §17); window vibrancy material picks up brand accent; SF Pro fallback when brand font missing
   - Windows: title bar respects native min/max/close + theme color; Mica/Acrylic backdrop picks up brand accent
   - Linux: GTK theme bridge for window decorations; Cairo glyph rendering parity
   - Brand schema includes `os_overrides` block: each token can declare `{conform: true}` (read from OS) OR `{conform: false, value: "..."}` (DeskModal evolution)

5. **Brand editor `plugins/brand-editor/` (EXPANDED from F138):**
   - Live preview of every component (chart / blotter / order-ticket / heatmap / alert toast / Cmd+K / Settings / About)
   - Per-token live edit with OKLCH picker + WCAG 2.2 AA contrast check
   - OS-conformance toggle per token
   - Asset upload (icons / logos / cursors)
   - Export brand as signed `.dmbrand` bundle (separate manifest from `.dmpkg`)
   - Per-section diff-from-default
   - A11y validation gate before publish

6. **Settings UI brand selector** (per §20 sdk-config auto-registering Settings UI):
   - `deskmodal.brand.active` setting key
   - Live-swap (no app restart; broadcast on `deskmodal.brand.changed`)
   - Preview-before-apply affordance
   - Per-plugin brand override (advanced; per-tile)
   - Per-OS preference layer (DeskModal default vs custom brand)

7. **Marketplace brand publishing:**
   - Brands ship as signed `.dmbrand` bundles via marketplace git (per §18.4.1 distribution; Ed25519 signature chain)
   - Brand publisher tier (community / verified / certified-by-DeskModal)
   - Search / preview / install / update / uninstall per F125 lifecycle
   - License field (Apache 2.0 / MIT / proprietary)
   - "Adopt this brand" one-click install + live swap

8. **Mandatory adherence — every plugin / window / app:**
   - ZERO hardcoded colors in CSS/TSX (already audit-gated `quality:design-tokens-complete`; F152 W6 promotes to BLOCKING workspace-wide)
   - All visual surfaces consume `--deskmodal-*` tokens via sdk-brand
   - Brand-update broadcast triggers re-render in every subscribed surface within 100ms (live swap)
   - Plugin manifest declares `[branding.surfaces]` listing visual surfaces exposed
   - Audit gate `quality:brand-adherence` (F152 W6 NEW) — rejects hardcoded literals + direct color access outside sdk-brand

9. **Live update propagation:**
   - Brand updated (in-place edit / install / uninstall) → broadcast `deskmodal.brand.changed` with manifest snapshot
   - Every subscriber re-reads tokens + re-renders
   - CSS variable swap is atomic (single `document.documentElement.style` change) — no flicker
   - Test gate: swap completes < 100ms p99 across all open windows

10. **Competitor research baseline (F152 W1; SOTA-target):**
    - TradingView (60+ community themes; chart-focused; weak app-frame)
    - Bloomberg Terminal (orange-on-black canonical; minimal user customisation; outdated aesthetic)
    - IB TWS (dense; dated)
    - NinjaTrader (chart-themable; app inconsistent)
    - OpenFin (white-label-strong; enterprise-only)
    - **DeskModal target: SOTA aesthetic + comprehensive token coverage + community-distributable + live-swap + OS-native conformance + zero hardcoded styling.** Beat each competitor on every axis.

11. **Forbidden patterns (BLOCKING audit gates per F152 W6):**
    - Hardcoded color literals in CSS/TSX (`#rgb` / `rgb()` / `rgba()` / `oklch()` / named CSS colors) outside generated/token registry
    - Direct `import './theme.css'` bypassing sdk-brand
    - Per-plugin hardcoded font-family / font-size / radius / spacing / motion
    - Plugin-authored Tauri-native window decoration overrides (per §17)

**Cascading specs queued for /loop:**
- **F152 master spec** (NEW; this directive) — 10-wave plan: W1 competitor research + schema design / W2 sdk-brand + brand-service cdylib / W3 brand editor expansion / W4 marketplace .dmbrand publishing / W5 OS conformance layer / W6 brand adherence audit gates + workspace-wide hardcoded-color rip / W7 settings UI brand selector / W8 plugin manifest `[branding.surfaces]` block authoring across all plugins / W9 live-swap perf bench + 100ms p99 / W10 docs portal + brand creator playbook
- **F138 brand editor amendment** — extended scope
- **F149 sdk-config amendment** — `deskmodal.brand.*` namespace + Settings UI brand selector
- **F148 architecture amendment** — brand-service as REQUIRED-tier + sdk-brand consumer tier
- **F147 OptiScript amendment** — `deskmodal.brand` read-only proxy in runtime
- **Every plugin spec** — declare `[branding.surfaces]` block

**Memory mirror:** `~/.claude/projects/-Users-adrian-deskmodal/memory/feedback_branding_single_capability.md` (durable per cross-session persistence pattern). NEVER FORGOTTEN.

**Pairs with:**
- §5 (no hardcoded colors — already audit-gated; promote to BLOCKING workspace-wide via F152 W6)
- §17 (Tauri-native window decorations + plugin SDK contracts)
- §18.4.1 (marketplace signed distribution)
- §20 (sdk-config Settings UI for brand selector)
- §21 (spec-hygiene per wave amendment)
- §23 (FDC3 Copilot Uniformity — copilot can suggest brand tweaks via `deskmodal.Copilot.Suggest`)
- `feedback_workspace_ux_sota_bar` (Jony-Ive cleanliness preserved across brand-swap)
- F130-W22 precedent (all apps subscribe to brand channel — landed)
- F138 brand editor (extended scope per §25 #5)

## 16. Service & I/O discipline — non-blocking, service-owns-data

The DeskModal agent is a single Tauri process hosting N in-process cdylib services + N webview-hosted apps. The agent main thread, the Tauri event loop, and the React render loop must never block waiting on I/O. Services own canonical state; apps subscribe.

**Invariants:**

1. **Every long-lived service loop runs in its own `tokio::spawn` task.** Stream readers, poll loops, persistence flushers, hydration restorers — one task per concern. Never co-host a stream loop and a UI handler on the same task.

2. **Per-cdylib runtime is `tokio::runtime::Builder::new_current_thread`** (not multi_thread). Workspace `panic="abort"` would otherwise abort the agent when a worker panics; current_thread keeps the panic on the caller thread where `catch_unwind` traps it. Enforced by `deskmodal_service_main!` macro at platform/crates/deskmodal-service-sdk/src/macros.rs.

3. **Bounded channels everywhere with drop-on-overflow** (mirror price-feed's 4096-capacity ctx channel). Never `mpsc::unbounded_channel` on a hot path. When the consumer is slow, drop oldest — never block the producer. `flume` + `try_send` is the preferred pattern.

4. **No `Mutex` / `RwLock` across `.await` boundaries on hot paths.** Use `ArcSwap`, `DashMap`, atomics, or actor channels (per §5). Cold-path caches (e.g. `next_scheduled_event` background lookup) may use `RwLock` only if the lock is never held across an `await`.

5. **Storage is debounced + non-blocking.** `deskmodal_service_sdk::spawn_persistence` (dirty-flag debounce, default 60s) handles all sdk-storage writes — never write synchronously per-message. `spawn_hydration` handles startup restoration with a merge-closure to absorb schema evolution.

6. **No `std::thread::sleep` / `std::sync::Mutex::lock()` blocking-on-poison** inside tokio tasks. Use `tokio::time::sleep` and `tokio::sync::Mutex` (when a lock is truly needed). `block_on` inside a cdylib service is a deadlock vector — forbidden.

7. **No synchronous HTTP / synchronous WebSocket** in service code. `reqwest` async + `tokio_tungstenite::connect_async` only. Apps never make their own HTTP requests for data the service owns.

**Service-owns-data architecture:**

- Service connects to upstream sources (HTTP poll OR WSS stream) on instantiation, regardless of whether any app tile is mounted.
- Service maintains an in-memory ring (`HeadlineHistory`, `EventHistory`, etc.) — bounded, indexed, dedup'd.
- Service persists the ring to sdk-storage via `spawn_persistence` (dirty-debounced).
- Service rehydrates the ring on startup via `spawn_hydration` (schema-merge closure).
- Service broadcasts new items to all connected apps via FDC3 channels.
- Service exposes history-bootstrap intents (`GetRecentHeadlines`, `GetRecentEarningsEvents`, etc.) for apps mounting after the service is already running.

**App-side discipline:**

- Apps NEVER make their own HTTP fetches for service-owned data. The only fetch a tile makes on mount is the history-bootstrap FDC3 intent.
- Apps subscribe via `useChannel.addContextListener` for live broadcasts.
- App-local state (Zustand store) is a UI projection of service state, not a source of truth.
- App tiles use React state batching; never block the render loop on FDC3 message handling.

**No fallbacks (durable rule, was memory-only):**

- Never ship "or X if Y" alternate paths. If a precondition is unmet, hard-fail with `rc ≠ 0` (Rust) / throw (TS) and surface the failure. Runtime status surfaces ("Reconnecting…", "Source unavailable") are not fallbacks — they're user-visible state, which is fine.
- A fallback hides the actual failure mode and prevents diagnosis. Hard-fail forces the operator to fix the root cause.

**Scalable, non-blocking, ultra-low-latency (durable, 2026-05-16 directive):**

DeskModal is a trading-terminal platform. Every fix must demonstrably preserve or improve three properties simultaneously: SCALABLE (handles N tiles + N services + N user sources without quadratic cost), NON-BLOCKING (no `.await` on a hot path holds a lock; no main-thread I/O; no synchronous syscalls on a tokio worker for blocking primitives), ULTRA-LOW-LATENCY (sub-100ms perceptible UI response; sub-10ms FDC3 intent dispatch; sub-1ms broadcast fan-out per subscriber).

Concrete checklist for every Rust impl wave:
- Hot-path channel: bounded mpsc/flume with `try_send` (drop-on-overflow), capacity ≥ 4096 (price-feed precedent). NEVER `unbounded_channel`.
- Hot-path data structure: `ArcSwap` for read-mostly, `DashMap` for many-writer, `AtomicU64`/`AtomicBool` for flags. NEVER `Mutex<T>` if reads dominate. NEVER `RwLock` across `.await`.
- Blocking syscalls (file I/O, dlopen, blocking sockets) ALWAYS through `tokio::task::spawn_blocking` (delegates to the blocking thread pool, never a tokio worker). For OS-level resources with single-thread requirements (dlopen on macOS, GPU contexts), use a dedicated `std::thread` with a flume channel actor — not a tokio task.
- App-side: virtualisation for any list > 100 rows (no N² re-render). React 19 transitions / Suspense for any state-update-driven fetch. Zustand stores split per concern so unrelated updates don't re-render the world.
- FDC3 channel broadcast: O(N subscribers) maximum per publish; never per-subscriber lock acquisition. ACL check is a single dashmap lookup.
- Service startup: parallel where safe, serialised only when the OS demands it (dlopen on macOS). Document any serialisation point + measure cost.

For every fix wave: state which of the three properties the fix preserves or improves, and cite the measurement (test, bench, or trace). "It works" is insufficient; "it serves N concurrent ___ at < Yms p99 with rc=0" is the standard.

**No hardcoded data-source URLs (durable rule, was memory-only):**

- All service-plugin URLs (news, earnings, price, all exchanges) live in `plugin.toml` `[default_config]` and may be overridden by user-configurable sdk-storage keys.
- Settings UI surfaces the keys only when the corresponding service is installed + enabled.
- A URL string in a `.rs` / `.ts` source file outside `_test.rs` / `*.test.ts` / fixtures is a defect.


## 17. Plugin architecture invariants — ServiceSDK + PluginSDK only

**Cardinal rule (durable, was memory-only): every plugin (app + service) consumes platform capabilities via `@deskmodal/sdk-*` + `@deskmodal/fdc3` hooks; NEVER roll bespoke FDC3 bridges or custom `init*Service()` modules.**

**The 9 SDKs (TS — `@deskmodal/*` scope):**

| # | Package | Concern | Audit gate |
|---|---|---|---|
| 1 | `@deskmodal/sdk-storage` (`plugin-tools/typescript/packages/sdk-storage/`) | kv_store namespaced `service:<id>` / `app:<id>`, SQLite-backed | `sdk:discipline` (`no-localstorage` rule) — `scripts/audit-sdk-discipline.sh` |
| 2 | `@deskmodal/sdk-notifications` (`plugin-tools/typescript/packages/sdk-notifications/`) | toasts + history + intent routing; thread / form / deep-link primitives | `sdk:discipline` |
| 3 | `@deskmodal/fdc3` (`plugins/tradesurface/packages/fdc3/`) | FDC3 2.2 desktop-agent hooks (`useChannel`, `useIntent`, `useContext`, `useCommandPalette`, `useServiceStatus`) — the platform-side desktop-agent client; spec-mandated bare package name `@deskmodal/fdc3` (not `sdk-fdc3`) | `sdk:discipline` (`no-raw-window-fdc3` rule) — BLOCKING |
| 4 | `@deskmodal/sdk-services` (`plugins/tradesurface/packages/sdk-services/`) | service lifecycle (`startService` / `stopService` / `drainService` / `reloadService` / `useService` / `useServiceLifecycle` / `useServiceList`) — apps subscribe, never spawn | `sdk:discipline` |
| 5 | `@deskmodal/sdk-window` (`plugins/tradesurface/packages/sdk-window/`) | Tauri window orchestration — ALL Tauri window APIs flow through this SDK; plugin code never imports `@tauri-apps/api/window` directly | `quality:window-sdk` — `scripts/audit-window-sdk.sh` |
| 6 | `@deskmodal/sdk-observability` (`plugin-tools/typescript/packages/sdk-observability/`) | structured logging + perf marks via `getLogger()`; replaces ad-hoc `console.log` | `sdk:discipline` (`no-console` rule — formerly proposed `sdk-telemetry`; observability is the realised package) |
| 7 | `@deskmodal/sdk-update` (`plugins/tradesurface/packages/sdk-update/`) | plugin self-update via marketplace (`checkForUpdates`, `installUpdate`, `getReleaseNotes`, `subscribeToUpdateChannel`, `listInstalledPlugins`, `useUpdateStatus`, `usePluginUpdates`) | `sdk:discipline` |
| 8 | `@deskmodal/sdk-lifecycle` (`plugin-tools/typescript/packages/sdk-lifecycle/`) | install / update / uninstall / start / stop / drain / reload lifecycle protocol — F125 SOTA reference | `sdk:discipline` |
| 9 | `@deskmodal/sdk-symbology` (`plugins/tradesurface/packages/sdk-symbology/`) — added F132 W14-D 2026-05-17 | OpenFIGI ticker → canonical metadata (FIGI / asset class / exchange) lookup + `useSymbology` hook | `quality:sdk-package-coverage` (full publishable-package shape) |

There is no standalone `sdk-theme` package on disk — design-token consumption flows through `@deskmodal/design-system` (`plugin-tools/typescript/packages/design-system/`) plus per-app token CSS layers; theming is a CSS-token contract, not an SDK module. Future ratification: either lift `design-system` into the `sdk-*` cohort or extract a thin `sdk-theme` runtime; tracked separately.

**Workspace-wide audit gates that cross-reference the SDK contract** (every gate's exit-1 message cites this section):

| Audit gate | Scope | Path |
|---|---|---|
| `sdk:discipline` (BLOCKING) | no-localstorage, no-console, no-raw-window-fdc3 | `scripts/audit-sdk-discipline.sh` |
| `quality:sdk-package-coverage` (BLOCKING) | every `plugins/tradesurface/packages/sdk-*` ships `package.json` + `src/index.ts` + `vite.config.lib.ts` + `tsconfig.json` + `vitest.config.ts` + ≥1 `*.test.ts` | `scripts/audit-sdk-package-coverage.sh` |
| `quality:window-sdk` (BLOCKING) | plugin/app code never imports `@tauri-apps/api/window` directly — sdk-window is the only consumer | `scripts/audit-window-sdk.sh` |
| `quality:dist-signed` (BLOCKING) | every `dist/plugins/<id>/` carries `publisher.pub` + signed `.sig` | `scripts/audit-dist-signed.sh` |
| `quality:broadcast-grants` (BLOCKING) | every channel broadcast cites an explicit grant in plugin manifest | `scripts/audit-broadcast-grants.sh` |
| `quality:app-token-imports` (BLOCKING) | apps import `--ts-*` tokens via design-system; no hardcoded hex | `scripts/audit-app-token-imports.sh` |
| `quality:brand-subscription` (BLOCKING) | brand pulls flow via `@deskmodal/fdc3` brand channel | `scripts/audit-brand-subscription.sh` |
| `quality:fdc3-targetapp-shape` (BLOCKING) | `targetApp` payloads conform to FDC3 2.2 spec shape | `scripts/audit-fdc3-targetapp-shape.sh` |

Service side: `deskmodal_service_sdk` (Rust) — `deskmodal_service_main!` macro emits the byte-stable `deskmodal_service_entry` FFI symbol; `spawn_hydration` / `spawn_persistence` handle storage; `ServiceClient` exposes channel broadcast + intent raise + storage I/O.

**Expanded SDK surfaces (landed waves cited):**

`@deskmodal/sdk-window` (tradesurface commit `61f8ef4` W22, `bafd359` F134-W11b, `d67c7c1` F134-W6b — verified via `plugins/tradesurface/packages/sdk-window/src/index.ts`):
- `useWindowTitle(title)` — sets OS native title bar via `getCurrentWindow().setTitle` in a useEffect.
- `useWindowState() → { isMaximized, isFullscreen, isMinimized }` — observation for app logic.
- `useWindowControls()` / `useWindowGroup()` — programmatic action / group access.
- `usePlatform() → { os, arch }` — Tauri plugin-os wrapper.
- `closeWindow()`, `minimizeWindow()`, `toggleMaximize()`, `toggleFullscreen()` — action functions for programmatic flows.
- `<TitleBar>`, `<WindowFrame>`, `<AppTitleBar>`, `<TileChannelSlot>` — pass-through components (NO custom controls; Tauri-native decorations handle min/max/close).
- Forward declarations (planned, not yet exported on origin/main): `useCloseConfirm`, `useWindowResized`, `useWindowFocused` — referenced in `window-frame.tsx` comments as the target port-rule surface for any future custom-decoration migration. Tracked separately; not yet a contract.

`@deskmodal/sdk-notifications` (plugin-tools commit `8049769` wave-6 + earlier W21-B work — verified via `plugin-tools/typescript/packages/sdk-notifications/src/index.ts`):
- Core: `notifications` SDK + `useNotifications` hook.
- Thread / form / deep-link primitives (W21-B): `useThreadedNotifications`, `useDeepLink`, `<NotificationForm>` component, `NotificationFormSpec` / `NotificationFormField` / `Thread` / `DeepLink` / `DeepLinkContext` envelopes, `resolveFormIntent` / `submitNotificationForm` helpers.
- Three new intents (W21-B): `deskmodal.AppendToThread` / `deskmodal.GetThread` / `deskmodal.OpenDeepLink`.

`@deskmodal/fdc3` (tradesurface commit `0a8cfa5` W15-C + `627883e` W21-D — verified via `plugins/tradesurface/packages/fdc3/src/hooks/use-command-palette.ts` and `use-service-status.ts`):
- Command-palette registration (W15-C): `useCommandPalette(appId, commands[])` hook; two CUSTOM_INTENTS — `deskmodal.RegisterCommands` and `deskmodal.UnregisterCommands` — broadcast on mount / unmount.
- Service-state degraded-pill (W21-D): `useServiceStatus(serviceId) → { status: 'healthy'|'degraded'|'unhealthy'|'unknown', reason?, since? }`; 30s polling fallback gated by `lastBroadcastAtRef`; raises `deskmodal.GetStatus` intent on retry. Consumed by `<DegradedStatePill>` in `@deskmodal/ui-components`.
- Full hook inventory (50+): `useChannel`, `useIntent`, `useContext`, `useChannelStatus`, `useAuditTrail`, `useAutoJoinFirstUserChannel`, `useBroadcast`, `useCrossAppDragSource`, `useCrossAppDropTarget`, `useDeskExtensions`, `useDeskmodalA11y`, `useDeskmodalNotifications`, `useDeskmodalShortcuts`, `useDeskmodalSound`, `useDeskmodalStateSync`, `useDeskmodalStorage`, `useDlp`, `useFdc3`, `useFindIntent`, `useFindIntentsByContext`, `useFindService`, `useInstrument`, `useInstrumentBroadcast`, `useIntentAvailability`, `useIntentListener`, `usePreloadedContext`, `usePriceFeed`, `usePrivateChannel`, `useRaiseIntent`, `useStreamingBroadcast`, `useStreamingContext`, `useViewIntent` — full listing in `plugins/tradesurface/packages/fdc3/src/hooks/`.

`@deskmodal/sdk-update` (tradesurface commit `bafd359` F132-W2 wave-3 + W19-C — verified via `plugins/tradesurface/packages/sdk-update/src/index.ts`):
- Consumer hooks: `useUpdateStatus`, `usePluginUpdates`.
- Delivery surface: `checkForUpdates(pluginId)`, `installUpdate(pluginId)`, `getReleaseNotes(pluginId, version)`, `subscribeToUpdateChannel(callback)`, `listInstalledPlugins()`.

`@deskmodal/sdk-symbology` (tradesurface commit `4b3e435` W14-D — verified via `plugins/tradesurface/packages/sdk-symbology/src/index.ts`):
- Hook: `useSymbology(ticker)` — async OpenFIGI lookup with cache.
- Error: `SymbologyError` class.
- Types: canonical metadata shape (FIGI, asset class, exchange).

**App `main.tsx` shape (minimum, maximum):**

```tsx
checkAppVersion();
initTheme();
createRoot(document.getElementById('root')!).render(<App />);
```

That's it. No `initFdc3Bridge()`, no `initPriceService()`, no `initStorageBackend()`. Those are SDK responsibilities, initialised lazily on hook usage.

**Dist plugin directory shape (enforced):**

```
dist/plugins/<id>/
├── plugin.toml
├── app/             (TS/TSX apps only — React bundle output)
├── icons/           (PNG/SVG icons referenced from manifest)
├── services/        (Rust cdylib only — present when plugin has service)
├── publisher.pub    (Ed25519 verify key)
└── *.sig            (signature manifest)
```

Anything else under `dist/plugins/<id>/` is a defect — file the deviation as a HIGH finding.

**User-authored data-source handlers (durable, F127-introduced):**

End-users may extend data-feed services (news-feed, earnings-feed, etc.) without authoring a signed L2 plugin via *declarative* `UserSourceDescriptor` entries persisted to sdk-storage under the target service's namespace (`news-feed.user-sources`, `earnings-feed.user-sources`). Descriptors carry `base_url`, `mode = "poll"|"stream"`, response-shape (`json_field_map` JSONPath / `rss` XPath / `stream.text_field_path`), and a `provenance` block. They run inside the *existing* service crate's source loop — NO foreign code execution, NO new sandbox, NO new runtime. AI-assisted authoring lives in a dedicated platform service (`discovery-feed`) that synthesises candidate descriptors via the Anthropic API; candidates broadcast on `deskmodal.discovery` and install ONLY on explicit user click via `deskmodal.InstallUserSource`. Defence-in-depth: TLS-only (`https://` / `wss://`), private-CIDR rejection, response-size cap, poll-cadence floor, user-added sources clamped to `SourceTierConfig::Community`. Manifest-shipped source ids cannot be overridden. The AI never auto-installs. Full plugin authoring (L2) remains the path for adapters needing bespoke logic — those declare `intents_raise = ["deskmodal.PublishNewsHeadline" | "deskmodal.PublishEarningsRealtime"]` and broadcast through the canonical FDC3 channels.

**Tauri-native window decorations (durable, 2026-05-16 directive):**

DeskModal uses Tauri's NATIVE window decorations on every WebviewWindowBuilder: `decorations(true)` (default). macOS draws native traffic lights; Windows draws native min/max/close; Linux draws native GTK window controls. We do NOT render custom React-side traffic-light controls. Custom controls (DarwinControls / StandardControls in any package) create the "two sets of buttons" defect — observed on Market window 2026-05-16.

**Vocabulary rule (user clarification 2026-05-16, verbatim quote — preserved per §1 honesty rule):** <!-- audit:allow-naming-tauri-not-decoration: quoting user directive verbatim per core.md §1 honesty rule --> "we are not using chrome it is all tauri". Do NOT use the browser-derived decoration term in commit messages, docs, file names, variable names, or conversation. The runtime is Tauri; the layer being named is the native OS window decoration. Use "Tauri-native window decorations", "OS-native title bar", "native traffic lights" (macOS), or "native min/max/close buttons" (Windows). The deprecated term is overloaded with Chromium-browser connotation and conceals the architectural decision. Legacy carry-overs in source (`AppShellChrome.tsx`, `audit-no-custom-chrome.sh`) are tracked for rename in a follow-up wave and were already renamed to `AppShellFrame.tsx` / `audit-no-custom-window-decorations.sh` in the F-rename-tauri-decoration wave; see `scripts/audit-naming-tauri-not-decoration.sh` for the canonical detector.

What `@deskmodal/sdk-window`'s `<TitleBar>` is allowed to do:
- Set the OS window title via `getCurrentWindow().setTitle(title)` in a single useEffect — the native title bar renders this string.
- Render `data-tauri-drag-region` over the title-bar area so Tauri's native drag works.
- Render an in-content subtitle / right-slot for app-specific actions BELOW the native title bar.

What `<TitleBar>` MUST NOT do:
- Render close / minimize / maximize / fullscreen buttons in React. Tauri's native decorations already provide them. Two sets = defect.
- Set `decorations(false)` on its WebviewWindowBuilder. The only exceptions are presets `Toast` and `NotificationCenter` where no decoration is intentional.

Uniformity rule: every DeskModal window — agent shell, Spaces, Market, Settings, About, Copilot, Tearout, every TradeSurface tile pop-out, every plugin window — uses the same Tauri-native decoration treatment (native window decorations + optional in-content header below). One source of truth, no exceptions.

This reverses parts of F128's W1/W2 custom-controls design. The historical justification (cross-platform consistency) is achieved instead through `decorations(true)` everywhere — macOS / Windows / Linux each show their own native conventions, which is the correct cross-platform behaviour for a desktop app.

**Sharper restatement (user clarification 2026-05-16, verbatim quote — preserved per §1 honesty rule):** <!-- audit:allow-naming-tauri-not-decoration: quoting user directive verbatim per core.md §1 honesty rule --> "the apps use tauri, we should not use chrome anywhere, it's all tauri".

ZERO custom window-decoration rendering anywhere in DeskModal. No DarwinControls. No StandardControls. No traffic-light SVGs. No CSS `app-region: drag` regions (Tauri's native title bar handles drag). Every window relies on Tauri-native decorations end-to-end. `@deskmodal/sdk-window`'s `<TitleBar>` and `<WindowFrame>` are either deleted or become no-op pass-throughs; the only legitimate API is `useWindowTitle(title)` (a hook that sets the OS title via `getCurrentWindow().setTitle`). `useWindowControls()` is allowed to provide `.close()`/`.minimize()` for programmatic flows (e.g. "are you sure?" dialogs) but is never used to render controls in React.

Forbidden patterns (would fail review):
- Any `<DarwinControls>` / `<StandardControls>` / `<WindowControls>` / `<TrafficLights>` JSX element.
- Any CSS rule containing `app-region: drag` (custom-decoration drag-region declarations).
- Any `setDecorations(false)` outside the explicit Toast / NotificationCenter exception list.
- Any imported close/min/max SVG icon used as a window control.

**SDK boundary (architectural clarification 2026-05-16):**

`@deskmodal/sdk-window` IS the abstraction boundary that owns ALL Tauri window APIs. Plugin/app developers consume sdk-window hooks; they never import `@tauri-apps/api/window` directly. Enforced by `scripts/audit-window-sdk.sh`.

Required SDK surface:
- `useWindowTitle(title: string)` — sets OS native title bar via `getCurrentWindow().setTitle` in a useEffect.
- `useWindowState() → { isMaximized, isFullscreen, isMinimized }` — observation for app logic.
- `closeWindow()`, `minimizeWindow()`, `toggleMaximize()`, `toggleFullscreen()` — action functions for programmatic flows ("are you sure?" close, app-driven window state).
- `usePlatform() → { os, arch }` — Tauri plugin-os wrapper.
- `<WindowFrame>` — opaque layout pass-through; renders nothing decoration-related (Tauri-native decorations handle controls).

User directive 2026-05-16 (verbatim quote — preserved per §1 honesty rule): <!-- audit:allow-naming-tauri-not-decoration: quoting user directive verbatim per core.md §1 honesty rule --> "we should not uniform to chrome, we must ensure we're only ever using tauri, which the SDKs should be applying, so the app/plugin developers only worry about functionality and all window handling is done by the sdks." The SDK is the contract; Tauri is the runtime; custom React decorations don't exist.

User directive 2026-05-16 (port rule, verbatim quote — preserved per §1 honesty rule): <!-- audit:allow-naming-tauri-not-decoration: quoting user directive verbatim per core.md §1 honesty rule --> "we must ensure we port any functionalities onto tauri if currently on any other window style." When deleting any custom-decoration code, FIRST inventory the BEHAVIORS that code implements (close handlers, close-confirm dialogs, isMaximized state tracking, focus listeners, etc.) and PORT each behavior to a Tauri-native equivalent via sdk-window hooks (`useCloseConfirm`, `useWindowResized`, `useWindowFocused`, etc.). NO functional regression. Document the port-map in the migration commit body.

**Instrumentation discipline (durable, was memory-only):**

When N silent chain points + 1 observable failure point exist (e.g. "service started, app mounted, no data appears"), add tracing at EVERY point BEFORE attempting any fix. Speculative fixes burn cycles. Per-cdylib `tracing_appender::non_blocking` writer to `{install_root}/data/logs/svc.<service-id>.log` (wired by `deskmodal_service_main!`) is the canonical instrumentation point for services. Programmatic spawn (AppleScript / WebDriver / Tauri-cmd / DB-seed) is REQUIRED to reproduce — never ask the user to click and report.


## 19. OptiScript-everywhere — scripts are the universal authoring layer

**The cardinal directive (user 2026-05-17 verbatim — preserved per §1 honesty rule):** "algos should be optiscript, whereby users can edit any script, so the experience would be to show a tab with script to be viewed/edited, then the users can modify, so the optiscript service can then invoke back into apps, services via FDC3 Research and critique to define the optimal solution, this is the way all scripting should work, in an integrated way across DeskModal."

**The rule:** every algorithm (TWAP / VWAP / Iceberg / Sniper / Peg / multi-leg), indicator (RSI / MACD / Bollinger / VPVR / TPO / footprint / custom), alert condition, screener filter, drawing-tool extension, AI-copilot tool, and bot workflow is authored in **OptiScript**. Rust services are the **execution host** layer (sandbox + capability gate + perf-critical primitives); OptiScript is the **authoring** layer. **Forbidden** (would fail review): hardcoded-in-Rust algorithm/indicator/alert logic when a script-authored equivalent is possible. Existing Rust impls (F143-D W4/W5/W6/W7 TWAP/VWAP/Iceberg/Sniper) become reference-script targets, not the canonical authoring surface.

**Architecture invariants:**

1. **Universal Execution Host** — `plugins/optiscript/crates/optiscript-runtime` (existing) is the canonical host. Accepts `(script_source, capability_grants, runtime_context)`; produces a JIT-or-AOT-transpiled-to-Rust executable; wires FDC3 + sdk-* SDK proxies into the script's `deskmodal` namespace; enforces ACL + rate-limit + resource caps per the script's manifest grants. No second execution host. No plugin authors a script runtime of its own.

2. **Native FDC3 primitives in OptiScript** (existing `optiscript-fdc3` crate is the source of truth for the surface; extend as needed):
   - `fdc3.broadcast(channel, context)` — capability-gated by script manifest `[broadcasts]`.
   - `fdc3.raise(intent, context, target?)` — gated by `[intents.raise]`.
   - `fdc3.listen(channel, handler)` — gated by `[subscribes]`.
   - `intent <Name>(context) { ... }` export syntax — declares an FDC3 intent handler; runtime auto-registers on script load.
   - `subscribe <Channel> (context) { ... }` export syntax — auto-registers a channel listener on script load.
   - `deskmodal.storage` / `deskmodal.notifications` / `deskmodal.observability` / `deskmodal.symbology` — proxy each `@deskmodal/sdk-*` capability into the script namespace; same ACL model.

3. **Tab-based editable experience.** Every algo / indicator / alert / screener opens as a tab in the OptiScript editor app (`plugins/optiscript/apps/optiscript-editor/`). Tab = script source (`.opti` file). Save → sdk-storage (`scripts:<id>:source`). Compile → optiscript-transpiler → cached binary at `scripts:<id>:compiled`. Run → execution host. Order-engine's "place TWAP algo" intent invokes the runtime with the **TWAP reference script**; user can fork → produces `scripts:custom:my-twap` with the modified source.

4. **Reference-script library.** Every standard algorithm / indicator / alert ships as a `.opti` source file inside its owning plugin (e.g. `plugins/order-engine/scripts/reference/twap.opti`, `plugins/tradesurface/scripts/reference/rsi.opti`). The plugin manifest declares these as **standard scripts**; users fork to customise.

5. **Performance.** OptiScript transpiles to Rust at compile-time (`optiscript-transpiler` already does this). Compiled scripts run at native speed (bench gate: ≤ 2× hand-Rust latency at p99). Hot-iteration paths (per-tick depth-l3 ingestion, per-bar indicator recompute) stay in Rust primitives; the SCRIPT calls into Rust via FFI (e.g. `book.bestAsk()`, `series.ema(period)`).

6. **Security model.** Every script declares its capability surface in a manifest header (channels broadcast/subscribe, intents raise/handle, storage namespaces, notification surfaces, max-broadcast-rate, max-memory-MB). Execution host enforces; manifest grants gate every primitive call. Sandboxing via existing `optiscript-fdc3/security` module.

7. **Audit chain.** Every script execution logs `script_source_hash` (SHA-256 of source) + `compiled_binary_hash` + `capability_grants_hash` + `invocation_context_hash` to the existing F143-D audit chain (Ed25519-signed lamport-ordered append-only log). Tamper-evident; replay-reproducible from source.

**Universal consumption pattern (replaces algo-specific Rust executors):**

Before (F143-D W4-W7 pattern — banned for new work):
```rust
// plugins/.../order-engine/src/algos/twap.rs — hardcoded executor
pub struct TwapExecutor { policy: ArcSwap<TwapPolicy>, ... }
impl AlgoExecutor for TwapExecutor { async fn run(&self, ctx, spec) { ... } }
```

After (canonical pattern):
```rust
// plugins/.../order-engine/src/algos/host.rs — ONE generic execution host
pub struct ScriptAlgoHost { runtime: Arc<OptiScriptRuntime>, ... }
impl AlgoExecutor for ScriptAlgoHost {
    async fn run(&self, ctx, spec) {
        let script = self.load_script(spec.algo_id).await?; // sdk-storage
        self.runtime.execute(script, ctx.capability_grants, ctx).await
    }
}
```

```opti
// plugins/order-engine/scripts/reference/twap.opti — user-editable source
manifest {
  intents.raise = ["deskmodal.RouteVenue", "deskmodal.RiskGate"]
  broadcasts    = ["deskmodal.order.child"]
  storage       = ["algo:twap:state"]
  max_broadcast_rate = "10/s"
}

intent deskmodal.AlgoTwap(parent) {
  let slices = sliceQuantity(parent.totalQty, parent.numSlices);
  for slice in slices {
    let venue = fdc3.raise(deskmodal.RouteVenue, slice);
    let ok    = fdc3.raise(deskmodal.RiskGate, slice);
    if !ok { return halt("risk_gate"); }
    fdc3.broadcast(deskmodal.order.child, { ...slice, venue });
    await sleep(parent.sliceCadenceMs);
  }
}
```

**Migration of in-flight + landed waves:**

| Wave | Status | Migration |
|---|---|---|
| F143-D W4 TWAP (landed) | Rust executor | Becomes AOT-transpilation target of `scripts/reference/twap.opti`; cleanup wave authors the .opti source + verifies bytecode equivalence via bench |
| F143-D W5 VWAP (landed) | Rust executor | Same — `scripts/reference/vwap.opti` |
| F143-D W6 Iceberg (landed) | Rust executor | Same — `scripts/reference/iceberg.opti` |
| F143-D W7 Sniper (in flight as of 2026-05-17 19:15) | Rust executor | Lands as Rust; cleanup wave authors `scripts/reference/sniper.opti` |
| F143-D W8+ Peg / multi-leg / KillSwitch | Not yet dispatched | Author OptiScript-FIRST per this rule; the Rust crate provides ONLY the generic ScriptAlgoHost + Rust primitives the scripts call |
| F141 AI copilot (planned codegen) | Spec-pending | codegen-output-scope question RESOLVES = OptiScript. Closes 1 of 6 F141 blockers |
| F138 alerts | Currently rule-engine | Alert conditions authored in OptiScript with FDC3 primitives |
| F133 indicators (Pine v5 transpiler landed) | Already script-based | Pine v5 transpiler feeds OptiScript runtime; user can edit indicator source in tab |
| F114 chart drawing tools | Hardcoded Rust + TSX | Extension drawing logic authored in OptiScript with `optiscript-drawing` crate primitives |

**Cascading spec amendments (next /loop wake):**
- F147 master spec (new) — "OptiScript-everywhere SOTA" — governs the rollout.
- F143-D amend: rescope W7-W10 + add cleanup wave for reference-script authoring + ScriptAlgoHost.
- F141 amend: codegen-output-scope = OptiScript (resolves 1 of 6 blockers).
- F138 amend: alert conditions as OptiScript.
- F134 amend: screener filters as OptiScript.
- F114 amend: drawing tool extensions via OptiScript.

**Audit gates (new, BLOCKING):**
- `quality:no-hardcoded-algo-logic` — scans `plugins/*/services/*/src/algos/` for hardcoded algorithm logic outside the `host.rs` / `mod.rs` shell + the AOT-transpilation reference targets. Reject any new algo `.rs` file that isn't a transpiler output or the generic ScriptAlgoHost.
- `quality:script-manifest-grants` — every `.opti` reference script under `plugins/*/scripts/` declares a manifest header with capability grants. Reject scripts that broadcast/raise/listen without a declared grant.
- `quality:script-audit-chain` — every ScriptAlgoHost invocation appends to the F143-D audit chain with source_hash + binary_hash + grants_hash.

**Pairs with:** §16 (non-blocking — script execution host respects channel discipline) + §17 (plugin architecture — scripts use sdk-* SDKs only) + §5 (no V1/V2 — scripts evolve in place; AI-generated forks live at `scripts:custom:<id>` separate from `scripts:reference:<id>`) + `feedback_no_versioned_interfaces_pre_public` + `feedback_per_capability_plugin_granularity` + `feedback_service_first_for_shared_state_perf`.

**Why this is right:** the existing optiscript codebase has 19 crates including fdc3, broker, datafeed, drawing, genetic, profiler, transpiler. The directive is a **rollout + cleanup of duplication**, not new construction. Every architectural piece needed (sandbox, ACL, capability manifest, FDC3 bridge, transpile-to-Rust, editor app) exists today. The directive crystallises what was previously fragmented into a workspace-wide invariant.


## 20. Unified configuration + architecture documentation

**Cardinal directive (user 2026-05-17 verbatim — preserved per §1):** "Have we determined the optimal way to manage config across services, and with a unified and extensible configuration experience where services and plugs can registed their config settings in the deskmodal settings window if the service is enable and removed if not enabled. Have we considered reuse an packaging of complimentary services if the requirements optimally overlap.. Resarch and critique all, determine he most beautiful, and intuitive, design and experience to update config across serivces, mitigating replication and verbosity, ensuring settings are peristed and restored, and available via the SDKs via a single intuitive SDK library for config."

**The rules:**

1. **Single unified config SDK — `@deskmodal/sdk-config`** (NEW; supersedes ad-hoc storage_get/intent dispatch for settings). React hook + Rust service-side handle + typed getters + live subscription. NO plugin authors its own settings IPC; ALL config flows through sdk-config. Forbidden patterns (would fail review): per-service `Get<Foo>Setting` / `Set<Foo>Setting` intent dispatches; raw `sdk-storage.get/set` for any user-facing setting (sdk-storage is for service-internal state only).

2. **Config schema declared in plugin.toml.** Every service's `[services.<svc>.config]` block lists every user-facing setting with: `key` (snake_case) / `kind` (enum/string/number/bool/secret/url) / `default` / `label` / `description` / `category` / `validation?` / `secret?` (true → OS keychain via deskmodal_ai::key_store::OsKeychainStore, NEVER sdk-storage) / `restart_required?` (true → service drain+restart on change via lifecycle protocol) / `depends_on?` (conditional visibility).

3. **Auto-registering Settings UI in `plugins/deskmodal-settings/`** (REQUIRED tier; ships with binary). On boot, queries every enabled service's config schema; renders categorised UI; settings panels appear/disappear as services enable/disable; stored values preserved on disable for re-enable. Categories: General / Data Sources / Trading / Collab / AI / Notifications / Privacy / Advanced. Cmd+K search across ALL settings. Diff-from-defaults view. Export/Import workspace settings as signed JSON.

4. **Cross-service shared settings under `deskmodal.*` namespace** — theme, accent, hotkey-prefix, DND-mode, locale, timezone. Services SUBSCRIBE, don't own. Replication forbidden.

5. **Capability-bundle packaging** — `plugin.toml [bundle] optional_partners = [...]` + `[bundle.unlocks]` declares cross-service edges. Marketplace search by capability, not service name. Install bundle = install N services + auto-enable cross-service config edges.

6. **Unified architecture documentation at `specs/148-architecture-sota/`.** Mermaid source diagrams (render in MD + on docs portal) — component tiers (Tauri host → cdylib services → @deskmodal/sdk-* → FDC3 bridge → apps), data flow per capability (price-feed → chart, order-engine → blotter), control flow (lifecycle protocol), capability registry matrix (FDC3 channels + intents × services). Auto-regenerated by `scripts/wiki-gen-architecture.sh` from plugin.toml registry + cohesion graph. Updated per wave landing.

7. **Audit-chain on every config change.** Per F143-D + F141 W2.6 BLOCKING fix landing today: every setValue logs `{who, when, old, new, signed: Ed25519}` to the platform audit chain. Tamper-evident; regulator-replayable; opt-in privacy redaction for `secret = true` values (logs hash, not plaintext).

8. **Service-vs-app boundary discipline (closes today's collab leak):** state-holding + broadcast/listen + decay-sweep responsibilities belong to a cdylib service. SDK hooks (useCursorSync etc.) are thin clients of the service. `@deskmodal/sdk-collab` hooks WILL refactor to consume a `collab-engine` cdylib (next F140-A wave) — current state where hooks own state is a known migration target, not a permanent pattern.

**Forbidden patterns (BLOCKING audit gates):**

- `quality:no-bespoke-settings-ipc` — scan `plugins/*/services/*/src/intents.rs` + `*.ts` intent helpers for `Get<X>Setting` / `Set<X>Setting` / `Update<X>Config` patterns. Reject all — must use sdk-config.
- `quality:secrets-not-in-storage` — scan plugin source for `storage_get_typed::<.*key.*>` / `storage_set::<.*key.*>` / `storage_get::<.*secret.*>`. Reject — secrets MUST go through OsKeychainStore.
- `quality:config-schema-coverage` — every service's `plugin.toml` declares `[services.<svc>.config]` block (even if empty) so Settings UI knows what to render (or knows there's nothing).
- `quality:architecture-diagram-current` — `specs/148-architecture-sota/diagrams/` regenerated within last 168h OR last 10 commits affecting plugin.toml/SDK surface, whichever is sooner. Stale diagram = drift.

**Pairs with:**
- F148 — Unified architecture documentation master spec
- F149 — sdk-config + auto-registering Settings UI master spec
- core.md §5 (no V1/V2 — config schema evolves in place)
- core.md §17 (sdk-* only — sdk-config is the canonical surface)
- security review BLOCKING-1 (secrets → OS keychain) — closed by §20 #2's `secret = true` routing
- feedback_per_capability_plugin_granularity — bundles ARE plugin-granularity; just declared optional partners
- feedback_workspace_ux_sota_bar — Settings UI follows Jony-Ive cleanliness (disclosure-over-presence, ≤8 visible primary controls per category, tabular-nums for numeric settings, no V2 toggles)

**Cascading amendments (queued waves):**
- F141 privacy_mode + API key → sdk-config (closes security HIGH-1 boot hydration + BLOCKING-1 keychain)
- F142-C venue URLs + replay caps → sdk-config (closes hardcoded-URLs audit + capacity constants per data-pipeline review)
- F143-D risk policies + algo params → sdk-config (user-tunable risk limits + per-algo defaults)
- F140-A collab colors + presence options → sdk-config
- F127 user-source schema → sdk-config (declarative replaces ad-hoc intents)
- F114 chart preferences (timeframes, indicators, themes) → sdk-config
- F133 indicator parameters → sdk-config
- F138 alert delivery preferences → sdk-config
- F134 screener preset filters → sdk-config

When DeskModal goes public: this rule remains; pre-public freedom to break (§5) means we can evolve sdk-config in place during the migration; post-launch the surface stabilises naturally.


## 21. Spec hygiene — every wave updates its spec atomically

**Cardinal directive (user 2026-05-17 verbatim — preserved per §1):** "ensure we're always updating specs with changes, optimally as per our directive for optimal and clean docs."

**The rule:** every wave commit that lands implementation, audit-gate authoring, refactor, OR architectural decision MUST atomically update the parent spec's `§6 wave plan` row + `benchmark.md` acceptance row + any affected `§Open concerns` dispositions IN THE SAME COMMIT. Specs that lag behind code are stale documentation — banned per `feedback_continuous_hygiene_across_all_axes` axis 3.

**Required per-wave spec touches:**

1. **§6 wave plan row** — flip "QUEUED" → "LANDED-<sha>-<date>". Cite the actual commit SHA (post-commit hook updates this on follow-up if necessary).
2. **`benchmark.md` row** — mark acceptance status (GREEN / IN-FLIGHT / SCOPE-TRANSFERRED-TO-<wave> / ESCALATED). Cite the verification evidence path (test count, audit-gate rc, CDP screenshot path, bench artifact).
3. **`§Open concerns` dispositions** — every `open_concern` returned by the wave's impl agent + every reviewer finding closed/transferred/escalated is reflected in the spec's `§Open concerns` table. Spec is the durable record; handoff is the in-flight record.
4. **`§Implementation status` block** (NEW expected in every active spec) — running tally of which surfaces are GREEN / IN-FLIGHT / NOT-STARTED. Updated per wave landing.
5. **Cross-references** — when wave A affects spec B (e.g. F143-D's OrderAuditLog primitive is also relevant to F141 audit-chain), spec B gets a one-line cross-ref entry citing wave A's commit. Avoids replication of architectural reasoning across specs.

**Forbidden patterns (would fail review):**

- Wave landing without `git log <spec.md>` showing the same wave's commit — spec is now stale.
- "We'll update the spec in the next wave" — banned (deferral per §8 + §18.1).
- Reviewer findings that closed in-wave NOT reflected in spec's `§Open concerns` table — invisible compliance.
- Multiple specs reproducing the same architectural primitive's design — replication; cross-ref instead.

**Audit gate (BLOCKING; F21-spec-hygiene-gate, queued):**

- `scripts/audit-spec-currency.sh` — for every spec dir under `specs/`, check that `spec.md` + `benchmark.md` have a commit within the last 7 days OR no implementation code matching the spec's `§Parallelism` write-set has changed within 7 days. Stale spec with current code = reject.
- Wire as BLOCKING in `local-ci.sh --fast` after the F21 spec-hygiene wave lands.

**Workspace-wide spec amendment sweep cadence:**

- Every 5-7 wave-batches: dispatch a `documentation-engineer` agent to amend ALL specs whose linked code has landed without spec updates. Same cleanup cadence as `feedback_continuous_hygiene_across_all_axes` axis 4.
- The agent's deliverable: spec.md + benchmark.md per affected spec, brought current with file:line citations to the landed commits.

**Pairs with:**

- §8 no-deferrals — spec staleness IS a deferral
- §18.1 zero-tolerance — every open_concern dispositioned in spec, not just handoff
- §18.4 continuous hygiene (axis 3 specs)
- §20 #6 architecture documentation auto-regen pipeline (`scripts/wiki-gen-architecture.sh`)
- F148 master spec — unified architecture documentation
- `feedback_cutting_edge_scope_rich_specs` — specs ≥ 1200 LOC; per-wave amendments keep them current

This rule lands today (2026-05-17) and applies retroactively: today's landed waves (F140-A W4/W6/W7/W8, F141 W2.5/W2.6, F142-C W3/W4, F143-D W6/W7 + OrderAuditLog, F144 W1/W2/W3/W3.5-spec, F146 W1/W2, F147 spec, F148 spec in flight, F149 spec in flight) trigger a workspace-wide spec-amendment sweep in the next /loop iteration.


## 23. FDC3 Copilot Uniformity Pattern — every plugin can request + serve AI

**Cardinal directive (user 2026-05-17 verbatim — preserved per §1):** "we need to evaluate the FDC3 way of leveraging and implementing co-pilots to be uniform across hosting any fdc3 compliant plugin."

**The rule:** DeskModal defines a canonical FDC3 intent suite for AI copilots (`deskmodal.Copilot.*`) so that (a) any FDC3-compliant plugin can RAISE these intents to receive AI assistance, and (b) any plugin can REGISTER itself as a copilot provider. This creates a federated AI ecosystem where copilots are first-class FDC3 citizens, not bespoke per-plugin integrations.

**Canonical intent suite (FDC3 2.2 App Directory v2 shape):**

| Intent | Context input | Result | Purpose |
|---|---|---|---|
| `deskmodal.Copilot.Ask` | `deskmodal.copilot.askRequest { prompt, conversationId?, attachments?[], serviceContext? }` | `deskmodal.copilot.askResponse { stream: ChannelId, conversationId, finishReason }` | Free-form question; streams response on returned channel |
| `deskmodal.Copilot.CompleteCode` | `deskmodal.copilot.completeRequest { language, partial, cursor, context }` | `deskmodal.copilot.completeResponse { suggestions[], confidence[] }` | Code completion — OptiScript, plugin.toml, etc. |
| `deskmodal.Copilot.Explain` | `deskmodal.copilot.explainRequest { kind: code|trade|order|audit|chart, payload }` | `deskmodal.copilot.explainResponse { explanation, citations[] }` | Human-readable explanation of a code block, trade, order, audit entry, chart pattern |
| `deskmodal.Copilot.Suggest` | `deskmodal.copilot.suggestRequest { context, count? }` | `deskmodal.copilot.suggestResponse { suggestions[], reasoning[] }` | Proactive suggestions from app-side context (e.g. chart-engine: "consider adding RSI") |
| `deskmodal.Copilot.RegisterTool` | `deskmodal.copilot.toolSpec { name, description, parameters_schema, handler_intent }` | `deskmodal.copilot.toolRegistered { tool_id }` | Plugin exposes a tool the AI can invoke (e.g. order-engine registers `place_order` tool) |
| `deskmodal.Copilot.UnregisterTool` | `deskmodal.copilot.toolId { id }` | `deskmodal.copilot.toolUnregistered { id }` | Plugin removes a previously registered tool |
| `deskmodal.Copilot.QueryCapabilities` | `void` | `deskmodal.copilot.capabilities { provider, models, tools, deployment, eval_score }` | Introspection — which copilot is active, what can it do |

**Channel suite:**
- `deskmodal.copilot.events` — copilot lifecycle (provider-switched, model-upgraded, eval-floor-passed)
- `deskmodal.copilot.tools` — tool registry updates
- `deskmodal.copilot.streams.<conversation_id>` — per-conversation token stream
- `deskmodal.copilot.suggestions` — proactive suggestion broadcasts (apps subscribe)

**Provider registration:**
- Multiple plugins MAY register as copilot providers (e.g. default `plugins/copilot/` + a third-party `plugins/financial-analyst-copilot/` specialised on macro analysis).
- FDC3 intent resolver picks per `findIntentsByContext` + user preference (sdk-config `copilot.default_provider`).
- Specialised providers can declare context filters: e.g. financial-analyst-copilot only handles `deskmodal.Copilot.Explain` when `kind = trade | order | audit`.
- Default copilot is the universal fallback.

**Tool federation (the AI gets DeskModal-native tools via FDC3):**

When the active copilot needs to invoke an action on behalf of the user (e.g. "place a TWAP order for 100 shares of AAPL"), it dispatches the FDC3 intent registered by the order-engine plugin. Example flow:

```
user: "TWAP 100 AAPL over 30 minutes"
copilot.Ask → 
  copilot reasons → calls registered tool `place_twap_order`
    → which is backed by deskmodal.Order.PlaceAlgo intent on order-engine
      → user confirmation dialog (per F143-D risk-gate)
        → order placed → audit chain → result back to copilot
          → copilot streams natural-language confirmation to user
```

This is the same primitive that lets a third-party "audit-explainer" plugin register a tool the copilot calls to summarise F143-D OrderAuditLog entries.

**Forbidden patterns:**
- Plugins implementing their own bespoke `Ask<X>` intent (e.g. `deskmodal.chart.AskAi`) — must use `deskmodal.Copilot.Ask` with `serviceContext = "chart"`.
- Copilot providers that bypass the FDC3 intent surface (direct sdk-fdc3 calls only).
- Hard-coded copilot endpoints in plugin source (must go via sdk-config `copilot.endpoint`).
- Plugins that bundle their own LLM (must consume the registered copilot provider).

**Required patterns:**
- Every plugin that interacts with AI uses `@deskmodal/sdk-copilot` hooks: `useCopilotAsk()`, `useCopilotComplete()`, `useCopilotExplain()`, `useCopilotSuggest()`, `useCopilotCapabilities()`.
- Plugin manifest declares: `[services.<svc>.copilot] tools_registered = [...] / intents_consumed = ["deskmodal.Copilot.*"]`.
- Audit-chain logs every copilot dispatch with `{plugin_id, intent, context_hash, provider, latency, finish_reason}`.

**New BLOCKING audit gates (queued for F151 W4):**
- `quality:copilot-fdc3-uniformity` — scans every plugin source for bespoke `Ask<X>Ai` / `AskCopilot<X>` / `<X>Suggest` intents; reject. Must use `deskmodal.Copilot.*`.
- `quality:copilot-tool-registration` — every plugin claiming AI integration registers ≥ 1 tool via `deskmodal.Copilot.RegisterTool`.
- `quality:copilot-endpoint-via-sdk-config` — no hardcoded copilot endpoints; must read from sdk-config.

**Cascading:**
- **F151 master spec** (NEW; this directive) — FDC3 copilot intent specification + provider/tool federation + sdk-copilot hooks + 4 audit gates
- **F141 amendments** — copilot becomes OPTIONAL tier; expose canonical FDC3 intents; expose RegisterTool surface
- **F150 amendments** — eval golden set covers ALL canonical intents (not just Ask); per-intent scorecard
- **F148 amendments** — architecture diagram includes federated-copilot topology (default + specialised + third-party providers; tool registry; deployment topology)
- **F149 amendments** — sdk-config schema for `copilot.endpoint` + `copilot.default_provider` + `copilot.router_policy` + `copilot.model.*`
- **F147 amendments** — OptiScript editor consumes `deskmodal.Copilot.CompleteCode` for autocomplete + `deskmodal.Copilot.Explain` for hover-explain

**Pairs with:**
- §16 (non-blocking — copilot streams via FDC3 channels; never blocks)
- §17 (sdk-* only — sdk-copilot is the canonical consumer surface)
- §19 (OptiScript scripts can raise `deskmodal.Copilot.*` intents like any other plugin)
- §20 (sdk-config for endpoint + provider + model preferences)
- §22 (eval + RAG + model strategy — F151 builds on F150)
- feedback_per_capability_plugin_granularity (copilot is OPTIONAL marketplace tier)


## 24. File size + decomposition discipline — split, NEVER cut

**Cardinal directive (user 2026-05-17 verbatim — preserved per §1; "ensure this directive is never forgotten"):** "we had a directive for optimal file size and splitting full implementations across files, never cutting down capabilities, ensure this directive is never forgotten"

**The rule:**

1. **Per-file ceiling: ≤ 300 LOC** for production source files (`.rs`, `.ts`, `.tsx`). Tests + fixtures + generated files exempt.
2. **When a file approaches the ceiling: SPLIT into cohesive sibling modules. NEVER cut capability/features/error-handling/edge-cases to fit.**
3. **Decomposition is by CONCERN, not by line-count slicing.** Each sibling owns a coherent responsibility (one impl per file; one test category per file; one wire-shape per file). Naming + module structure surface the split's intent.
4. **Examples of correct decomposition (already-landed precedent):**
   - F134-W13: `connection_manager.rs` 1791 LOC → split into per-concern modules (auth / lifecycle / retry / health / metrics / ...).
   - F134-W13: `fdc3.rs` 1762 LOC → split into per-channel-type + per-intent-type modules.
   - Sniper/Iceberg/TWAP/VWAP: separate `algos/<name>.rs` per algorithm.
   - sdk-collab hooks: one hook per file (`use-cursor-sync.ts`, `use-viewport-sync.ts`, `use-selection-echo.ts`, `use-voice-huddle.ts`).
5. **Forbidden patterns (would fail review):**
   - Pleading "monolithic by design" / "tightly coupled" to bypass the split.
   - Cutting error-handling branches or edge-case logic to hit the ceiling.
   - Reducing test coverage to keep test files small (tests are exempt; split tests by category instead).
   - Pasting placeholder `// TODO: split later` comments — per §5 production-code rules.
6. **Decomposition checklist when a file approaches 300 LOC:**
   - Identify cohesive concerns within the file.
   - Move each concern to a sibling `mod.rs` + `<concern>.rs` (Rust) or `index.ts` + `<concern>.ts` (TS).
   - Re-export public symbols at the module root so consumers' import paths remain stable.
   - Per §17 SDK contracts: SDK packages re-export from `src/index.ts`; consumers never reach into internal subdirs.
   - Per §5 no-V1/V2: the split happens IN PLACE in the current commit; no `legacy/` / `old/` co-existence.
7. **Audit gate `quality:per-file-loc-ceiling`** — currently ADVISORY (warning-only) per `local-ci.sh --fast`; user directive 2026-05-17 promotes to **BLOCKING** in the next /loop iteration. Receiver wave: a dedicated decomposition sweep across any remaining file > 300 LOC, then flip the gate to BLOCKING.
8. **Exemption surface (documented, narrow):**
   - Generated files (`*-types.ts` from JSON Schema, `*.pb.rs` from protobuf, etc.) — annotated `// @generated` at top.
   - Test files — exempt (split if convenient; not required).
   - Migration / data-fixture files.
   - `Cargo.lock` / `pnpm-lock.yaml`.
   - Any source file with explicit `// audit:allow per-file-loc-ceiling: <reason>` annotation at column 0; per `audit-verify-discipline.sh` escape-hatch pattern — every honoured bypass logged.

**Why split-not-cut:**
- DeskModal is a trading-terminal platform; cut capability = real-money risk.
- AI-driven development thrives on small, focused files (smaller agent context per dispatch; clearer mental model; better git-blame; finer review surface).
- Per `feedback_workspace_ux_sota_bar` Jony-Ive cleanliness — small focused units mirror the disclosure-over-presence principle at the code level.
- Compounds with §21 spec-hygiene (one wave's commit touches focused files; cleaner diff).

**Pairs with:**
- §5 production-code rules (no V1/V2 + no placeholder dead-code + workspace-wide drift fixed in-wave)
- §17 SDK boundary discipline (SDK packages re-export from src/index.ts)
- §18.4 continuous hygiene axis 4 (legacy assets — including overlarge files)
- §21 spec-hygiene (wave commits update specs; clean diffs from clean file sizes)
- F134 W13 connection_manager + fdc3 decomp precedent
- feedback_decomp_redistributes_not_reduces — decomp is concern-redistribution, not LOC-reduction

**Memory mirror:** `~/.claude/projects/-Users-adrian-deskmodal/memory/feedback_file_size_split_never_cut.md` (durable per `feedback_no_versioned_interfaces_pre_public` cross-session persistence pattern).

**Pre-impl-pod decomp wave (user clarification 2026-05-17):** when a single file holds > 50% of a planned pod's accumulated write-set, the orchestrator MUST dispatch a precondition decomp wave (per §24 module split) FIRST — then the impl pod fans out across the resulting sub-modules with disjoint write-sets per §4 pod-discipline. Concrete pattern:
- **Step 1 (1 agent, decomp wave):** split the bottleneck file into N sub-modules by concern. No behavioural change; tests retained; re-exports preserve public surface.
- **Step 2 (parallel pod-of-N):** N agents each close BLOCKING/HIGH findings in their disjoint sub-module.
- **Wall-clock improvement** typically ~30-40% vs monolithic single-agent closure (5 parallel agents @ 6min ≈ 10min + decomp ≈ 16min vs monolithic 26min).
- **Triggers**: pod plan shows ≥ 3 BLOCKING/HIGH findings against the same file AND file LOC > 300 (already-§24-violating).
- **Anti-pattern**: dispatching N agents all writing to the same > 300 LOC file → violates §4 pod-disjointness + §24 file-size rule simultaneously; wave fails the audit gate when promoted to BLOCKING.

Example missed (today's Sniper trading-sme closure): sniper.rs at ~660 LOC held 4 BLOCKING + 6 HIGH findings; monolithic single-agent closure took ~26 min. Correct shape would have been: decomp wave splitting sniper.rs into `algos/sniper/{observation,fire,fill,policy,audit}.rs` (~10 min) + parallel pod-of-5 closing findings per sub-module (~6 min) = ~16 min total. Logged for /loop planner reference.

---

## 31. Cloud-lane operational rules — monitoring + aggregator + visual critique

**Cardinal directive (user 2026-05-18 verbatim — preserved per `core.md §1` honesty rule):** "how can we monitor the cloud lanes too? How will the lanes consider their value in aggregate with the other apps, consistent design, integration with deskmodal capabilities such as notifications, ai, fdc3 and all other capabilities you will research and ensure is available in the SDKS is considered, how will the lanes visually critique and determine optimal intuitivity as a single app in DeskModal, in multi tabs in deskmodal or as separate apps, but integrating optimally"

F154's cloud-lane charter ([specs/154-per-app-sota-evolution/cloud-lane-charter.md](../../specs/154-per-app-sota-evolution/cloud-lane-charter.md)) defines per-app research lanes. This §31 codifies the operational rules for the THREE lane types running concurrently: per-app research, cohesion-aggregator, visual-critique.

### 31.1 Lane creation contract (per F154 cloud-lane-charter)

Every cloud lane MUST satisfy:

- **Fresh-clone start** — no CBM cache continuity (per `discipline.md §26` 4-tier persistence — cloud sessions only get tier-1 git, never tier-2 auto-memory).
- **Bounded write-set** — declared in the brief; audited at orchestrator-pull-time via `scripts/audit-cloud-lane-pulls.sh` (rejects commits exceeding the bound).
- **Self-contained brief** — every fact the lane needs (file paths / SDK manifest / cohesion contract / competitor URLs) inlined; lane never depends on CBM queries.
- **No source-file edits** — `.rs` / `.tsx` / `.ts` / `.py` / `.toml` strictly forbidden; impl waves dispatch LOCAL with CBM context.
- **No canonical-file edits** — `.claude/rules/**`, `CLAUDE.md`, `.mcp.json`, `specs/personas/**`, `.specify/memory/**` strictly orchestrator-only (per `parallel-sessions.md`).
- **Push to main** — direct push via `git pull --rebase` race protection (3 retries); no PR shape.

Audit gate `audit-cloud-brief-shape.sh` (queued F154 W0) rejects briefs missing any of these clauses.

### 31.2 Cohesion-aggregator lane authority

The cohesion-aggregator lane (see `specs/154-per-app-sota-evolution/cohesion-aggregator-charter.md`) is the ONLY lane authorised to propose CROSS-app contracts:

- Per-app lanes have bounded scope — they read + write ONLY their own app's research files. Proposing cross-app contracts from a per-app lane VIOLATES the write-set bound.
- The aggregator reads ALL 22 per-app spec-suggests + SDK manifest + cohesion contract → produces `research/cohesion-aggregate-<date>.md` + `research/cohesion-spec-suggest-<date>.md`.
- Cadence: 6-hourly, offset +3h from per-app lanes (so aggregator reads the freshest per-app outputs).
- Cohesion checklist (10 dimensions × 22 apps = 220 evaluation cells per cycle): FDC3 integration / Cmd+K integration / brand-token consumption / notifications integration / copilot integration / drag-drop integration / OptiScript integration / settings integration / config persistence / lifecycle integration.
- Aggregator surfaces gaps → orchestrator dispatches local impl pods + queues audit gates if pattern is broad.

Forbidden: per-app brief containing cross-app suggestions → rejected by `audit-cloud-brief-shape.sh`.

### 31.3 Visual-critique lane authority

The visual-critique lane (see `specs/154-per-app-sota-evolution/visual-critique-charter.md`) is the ONLY lane authorised to produce USER-PERSPECTIVE visual evaluation:

- Per-app lanes evaluate functionality; aggregator evaluates cross-app contracts; visual-critique evaluates how the suite RENDERS to the user.
- Three display modes evaluated per app: **Single-app** (tearout / full-screen 1280×800+) / **Multi-tab** (4-up grid 600×400 effective) / **Suite** (chart-primary + 4-7 sibling apps).
- Cadence: WEEKLY (Monday 06:00 UTC); orchestrator pre-captures playwright-mcp artifacts (198 screenshots + 22 axe-core + 22 lighthouse) Sunday 23:00 UTC.
- Critique checklist: 10 MacOS-school criteria × 3 modes × 22 apps = 660 evaluation cells per cycle.
- Output: 22 `research/visual-critique-<app>-<date>.md` deliverables per cycle (~15-20K LOC critique total).
- Surfaces remediation queue → orchestrator dispatches local impl pods (frontend-architect + ux-design-lead).

Forbidden: any lane calling `mcp__playwright__browser_*` directly (cloud lacks live DeskModal binary); pre-captured artifacts read-only.

### 31.4 Monitoring command + cadence

**Daily monitoring** via `scripts/monitor-cloud-lanes.sh`:

- One-shot report: `scripts/monitor-cloud-lanes.sh` (rc=0 healthy; rc=1 STALE/disabled).
- Continuous watch: `scripts/monitor-cloud-lanes.sh --watch` (5-min refresh).
- JSON output: `scripts/monitor-cloud-lanes.sh --json` (machine-readable).
- Companion: `.session-state/cloud-lane-health.json` auto-regenerated each run.

Per-lane fields tracked: name / cadence_hours / last_run / next_run / enabled / latest commit SHA on origin/main / status (ok | STALE | disabled | never_run).

Staleness threshold: last_run > 2× cadence_hours (e.g. 6h lane stale at 12h; weekly lane stale at 14 days).

Orchestrator runs `monitor-cloud-lanes.sh` daily as part of `/loop` wake protocol — STALE / disabled lanes investigated immediately. The script gracefully skips if `RemoteTrigger` CLI is unavailable (cloud-lane infra may be MCP-tool-only) — emits placeholder health file + rc=2.

### 31.5 Anti-pattern — cross-app spec-suggests in per-app lane

**Forbidden:** per-app brief proposing cross-app behaviour. The per-app lane has bounded scope per §31.1; cross-app proposals violate the write-set bound at orchestrator-pull-time.

**Required path** for cross-app proposals:
1. Per-app lane surfaces an observation in its own research file ("watchlist would benefit from accepting depth-price-hint drag payload").
2. Cohesion-aggregator reads that observation across multiple per-app spec-suggests + matches against SDK manifest + cohesion contract.
3. Cohesion-aggregator produces concrete cross-app amendment in `cohesion-spec-suggest-<date>.md`.
4. Orchestrator dispatches local impl pod (per `parallelism.md §4` + `architecture.md §21` spec-hygiene).

Routing every cross-app proposal through the aggregator preserves the per-app lane's bounded scope + creates a single auditable channel for suite-level changes.

### 31.6 Cascading amendments queued

- **F154 cohesion-aggregator-charter.md** (NEW; landed W0.5) — full operating contract.
- **F154 visual-critique-charter.md** (NEW; landed W0.5) — full operating contract.
- **scripts/monitor-cloud-lanes.sh** (NEW; landed W0.5) — daily monitoring.
- **scripts/audit-cloud-brief-shape.sh** (queued F154 W0 deliverable) — enforces §31.1 brief contract; rejects per-app briefs with cross-app proposals.
- **scripts/audit-cloud-lane-pulls.sh** (queued F154 W0 deliverable) — write-set audit at `git pull --rebase` time.
- **scripts/wiki-gen-sdks.sh** (already exists) — orchestrator pre-fire regen for aggregator's SDK manifest input.
- **F154 spec.md §6 + §28 + §29** (queued W0.5 amendment) — cite cohesion-aggregator + visual-critique lanes.
- **F154 verification-matrix.md §3** — extended by cohesion-aggregator findings each cycle.
- **F154 app-inventory.md** — every app row gains cohesion + visual-critique columns.

**Pairs with:**
- `core.md §1` (honesty — every lane firing review cites evidence per §28 spec lane post-firing review)
- `core.md §4` (parallelism — cloud lanes run in parallel with local pods; speculative N+1 unchanged)
- `discipline.md §26` (context management — cloud lacks tier-2 auto-memory; brief is the self-contained context primitive)
- `parallelism.md §4` (audit-by-path — briefs pass file paths, not inline excerpts)
- `parallel-sessions.md` (canonical-file ownership — only orchestrator edits .claude/rules/**)
- `quality.md §18.7` (always-parallel + always-verify — cloud lanes are the parallel research engine)
- `architecture.md §17` (sdk-* discipline — aggregator's SDK manifest is the canonical surface)
- `architecture.md §21` (spec-hygiene — orchestrator-side impl wave amends spec atomically per finding)
- `architecture.md §23` (FDC3 Copilot uniformity — aggregator cross-checks every app's copilot adoption)
- `architecture.md §25` (branding single capability — visual-critique cross-checks brand-token consumption per mode)

**Memory mirror:** `~/.claude/projects/-Users-adrian-deskmodal/memory/feedback_cloud_lane_cohesion_monitoring.md` (durable; cross-session per `feedback_no_versioned_interfaces_pre_public` persistence pattern).

---

## 33. Session Mesh — multi-session coordination (F157 Layer 11)

**Cardinal directive (user 2026-05-18 verbatim):** "evolve this so we can run multiple parallel claude sessions across deskmodal so they do not create loss, interrupt, or ideally they somehow learn and collaborate, it's critical we're not creating too much expense, unnecessary replication, and we want to deliver code and outcomes fast"

The **Session Mesh** at `.session-state/mesh/` is the filesystem-backed coordination layer for parallel Claude sessions on the same machine. Sessions don't directly message each other (that's `agent-teams` and it's high-cost); instead they **share a ledger** of claims + findings + heartbeats.

**8 mesh scripts** at `scripts/session-mesh/`:
- `claim-write-set.sh <feature> <program> <write-set-csv>` — declare bounds + check conflicts
- `release-write-set.sh` — release this session's claim
- `heartbeat.sh` — touch last_seen + extend claim expiry (called per Stop hook)
- `share-finding.sh <topic> <summary> [<evidence>]` — write to findings bus
- `list-findings.sh [--since N] [--from-others]` — read findings from other sessions
- `find-conflicts.sh` — pairwise overlap check
- `check-concurrency.sh` — report active sessions vs cap

**Discipline:**
- SessionStart hook calls `claim-write-set.sh` + `list-findings.sh --since 24` and injects into context
- Stop hook calls `heartbeat.sh` (renews claim every turn)
- PreCompact hook releases claim; PostCompact re-claims
- SessionEnd hook releases claim
- Other sessions' SessionStart sees yours via heartbeat; respects your write-set

**This is the SESSION-scoped twin of §32 cross-session continuous-lane orchestration.** §32 owns cross-session work coordination (cloud lanes, audit gates); §33 owns local-session coordination (work-claim, findings bus, heartbeat).

**Pairs with §32 + F157 spec at `specs/157-autonomous-delivery-operating-model/spec.md` + `feedback_api_load_concurrent_agents` + `feedback_f157_autonomous_delivery`.**

## 32. Continuous lane orchestration — zero-idle invariant + conflict-free dispatch + sync-to-targets

**Cardinal directive (user 2026-05-18 verbatim — preserved per `core.md §1` honesty rule):** "we should ensure all lanes are used at all times, so we must have an orchestrator planning optimally ahead, so the lanes don't conflict and we have full synchronisation with our targets, and then building and testing all" + "we should be using our local lanes and agents too optimally for tasks which suit running on the desktop" + "we should only allocate tasks to the cloud in which it can be useful and high quality, otherwise we should continuously ensure our local lanes are utilised, with /loop".

F155 (`specs/155-continuous-lane-orchestrator-sota/spec.md`) codifies the continuous lane orchestrator. §32 here is the CANONICAL operational rule the orchestrator follows on every /loop wake + every event.

### 32.1 Zero-idle invariant

The orchestrator MUST NOT leave LOCAL lane capacity idle while dispatchable backlog items exist. At every event (agent return / git push / cron fire / failed gate / human directive / timeout) the orchestrator runs `scripts/orchestrator-replan.sh` + dispatches to fill empty local lanes per priority.

Cloud lane idleness is ACCEPTABLE (per F155 spec §4.8.8) — cloud lanes have cron cadence, not zero-idle invariant. Local lane idleness is the only banned state.

Verified by `scripts/audit-no-idle-with-dispatchable.sh` (BLOCKING in `local-ci --fast` post-F155 W6).

### 32.2 Conflict-free dispatch contract

No agent dispatch happens without passing through the replan algorithm's conflict-matrix gate (per F155 conflict-matrix.md). Pairwise-disjoint write-set requirement from `parallelism.md §4` enforced PRE-DISPATCH, not post-failure.

Verified by `scripts/audit-conflict-matrix-checked.sh` (BLOCKING post-F155 W6).

### 32.3 Auto-replan on every event

Six trigger events (per F155 spec §5):
1. Agent return.
2. Git push (local OR cloud lane).
3. Cron fire (cloud lane scheduled firing).
4. Failed gate (Tier-A/B/C verification rc != 0).
5. Human directive (user message changes priority).
6. Timeout (in-flight item exceeds estimated wall-clock × 2).

Each event triggers `bash scripts/orchestrator-replan.sh` → dispatchable set recomputed → next dispatches issued.

Verified by `scripts/audit-replan-on-event.sh` (ADVISORY post-F155 W6).

### 32.4 Sync-to-targets ledger

Every dispatch advances ≥ 1 F-spec milestone. The orchestrator maintains `.session-state/sync-to-targets-ledger.json` per F155 sync-to-targets-ledger.md.

Daily roll-up at 06:00 UTC + on demand. Surfaces target stalls (>24h) + trajectory deviations (>5%).

Verified by `scripts/audit-sync-targets-current.sh` (BLOCKING post-F155 W6).

### 32.5 Anti-patterns banned

Per F155 spec §11:
- "I'll plan when this returns" (when capacity > 1 + dispatchable items exist).
- "Let me wait and see" (when zero-idle invariant violated).
- Single-lane-blocking on user-confirmation when ≥ 2 lanes could fire in parallel on disjoint work.
- Dispatching without conflict-matrix check.
- SCOPE-TRANSFER to non-existent receiver (per `quality.md §18.1`; F155 spec §10).
- Ignoring failed Tier-A/B/C gates (per `quality.md §18.1`).
- Cloud lane impl-tasking (cloud is RESEARCH only per §31.1; impl is LOCAL per F155 §4.5).
- Workspace-wide verification per wave (per `quality.md §18.7.1` + F155 §21).
- Dispatching Rust impl to cloud (no CBM/rust-analyzer/cargo; F155 §11.9).
- Dispatching `launch.sh --verify` to cloud (no Tauri runtime; F155 §11.10).
- Local lane sitting idle while cloud runs research that could parallelise.
- "Use cloud because lane is idle" (per F155 §4.8.8).

### 32.6 Cascading amendments (queued F155 waves)

- `scripts/orchestrator-replan.sh` (W0 skeleton; W2 full algorithm; W3 conflict-matrix verifier; W5 monitor integration).
- `scripts/sync-to-targets-update.sh` (W4).
- `scripts/check-repo-states.sh` (W5).
- `scripts/audit-no-orphan-scope-transfers.sh` (W6).
- `scripts/audit-no-idle-with-dispatchable.sh` (W6).
- `scripts/audit-conflict-matrix-checked.sh` (W6).
- `scripts/audit-sync-targets-current.sh` (W6).
- `scripts/audit-backlog-current.sh` (W6).
- `scripts/audit-replan-on-event.sh` (W6).
- `wiki/playbooks/continuous-lane-orchestration.md` (W7).
- `wiki/inventory/orchestration.md` (W7).
- `discipline.md §13` amendment (W2 — autonomy protocol wake-step 3 + 4 codifying replan reads).

### 32.7 Local-lane /loop saturation (FIRST-priority operational rule)

Local lane utilisation is the FIRST priority. Cloud lanes are SECOND priority and only when value-quality gate (F155 spec §4.8) passes all 5 tests.

`/loop` self-pacing pattern per `discipline.md §13` autonomy protocol — on every wake (every harness notification + every ScheduleWakeup):

1. **Check local lane utilisation FIRST.** Count in-flight local agents.
2. **If < 3 local in-flight and dispatchable backlog exists:** dispatch up to 4 more (cap 7 per §28.3) per replan algorithm (F155 spec §6).
3. **Only after local lanes are saturated to ≥ 5/7:** consider firing additional cloud lanes manually (the existing 22-24 cloud lanes already run on cron per §31; no need to manually fire each cycle).
4. **If local cap reached + no more dispatchable local backlog:** schedule next ScheduleWakeup 1200-1800s per §28.9 cache-aware delay; do NOT idle-wait.

Backlog refill discipline: every wave that completes spawns potential follow-up waves into the backlog (closure pods for SCOPE-TRANSFERRED concerns, cleanup waves, decomp pre-impl per §24, audit-gate authoring per §27.13/§28.11). The orchestrator's job: KEEP THE BACKLOG OVERFULL so local lanes never go idle.

Anti-pattern banned: waiting on user-confirmation for ONE non-blocking question while N ≥ 2 local lanes sit idle on independent work. Dispatch the parallel work first; ask the question concurrently.

**Pairs with:**
- `core.md §1` (honesty — every replan decision cites evidence)
- `core.md §4` (parallelism — F155 is the META layer above)
- `parallelism.md §4` (pods + speculation + audit-by-path + warm-agent reuse — F155 selects per-event)
- `parallelism.md §15` (wave discipline — F155 honours evolve-and-fix-forward)
- `parallel-sessions.md` (canonical-file ownership — F155 backlog written by orchestrator only)
- `quality.md §7` (reviewer matrix — F155 backlog declares reviewer pod shape)
- `quality.md §18.1` (zero tolerance — F155 materialises SCOPE-TRANSFERRED receivers)
- `quality.md §18.7` + `§18.7.1` + `§18.7.2` + `§18.7.3` + `§18.8` (always-parallel-always-verify + tier-cadence + never-block + scoped-tests + world-class-verification)
- `discipline.md §9` (handoff protocol — F155 supersedes free-form handoff for active backlog state)
- `discipline.md §13` (autonomy protocol — F155 IS the autonomy mechanism between /loop wakes)
- `discipline.md §26` (context discipline — backlog is tier-1 CANONICAL git via daily snapshots)
- `architecture.md §16` (non-blocking — replan runs in main agent loop; never daemon)
- `architecture.md §21` (spec hygiene — backlog items cite spec receivers)
- `architecture.md §27` (per-capability repo — backlog declares target repo per item)
- `architecture.md §28` (deterministic+accelerated — F155 IS the planning layer)
- `architecture.md §29` (incremental verification — F155 budgets per logical impact batch)
- `architecture.md §30` (aggregate MCP capabilities — replan reads CBM + wiki-mcp)
- `architecture.md §31` (cloud-lane operational rules — F155 schedules lanes per §31 catalogue alongside local)

**Memory mirror:** `~/.claude/projects/-Users-adrian-deskmodal/memory/feedback_continuous_lane_orchestrator.md` (durable; cross-session per `feedback_no_versioned_interfaces_pre_public` persistence pattern).
