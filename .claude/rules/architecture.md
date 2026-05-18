---
title: Architecture
authority: derives from `core.md`; topic-file for §16 + §17 + §19 + §20 + §21 + §23 + §24 + §25 + §27 + §28 + §29 + §30 + §31 + §32 + §33
load_when: authoring services / plugins / SDKs / OptiScripts / branding / new repos / multi-agent dispatch / verification; deciding what goes in platform vs plugins; choosing settings IPC; verifying spec currency; deciding file-split vs cut; deciding repo boundaries + tier metadata + graceful degradation + licensing; ensuring no-edit-loss + accelerated parallel coding; choosing verification scope (only-what-changed); choosing MCP for Rust diagnostics / visual design / library docs / cross-stack discovery; running multi-session work
optimized_at_sha: 52cf4da
size_strategy: lean stubs in this file; verbose content in wiki/playbooks/architecture/*.md (queryable via wiki-mcp)
---

# Architecture

Lean index. Each section below is a **stub** that preserves the §-anchor + cardinal directive + key invariants + cross-refs. Full content lives in `wiki/playbooks/architecture/*.md` (NOT auto-loaded; queried on demand via `mcp__wiki-mcp__wiki_get_page`).

**Why stubs:** the full architecture.md was 131K chars (~33K tokens) auto-loaded at every SessionStart. This split (2026-05-19) drops it to ~12K chars (~3K tokens) — 90%+ context reduction — while preserving every §-anchor, every cardinal directive (verbatim per `core.md §1` honesty), and every cross-reference.

## Wiki playbook map

| § range | Playbook | Theme |
|---|---|---|
| §16 + §17 | `wiki/playbooks/architecture/runtime-services.md` | Service & I/O discipline + plugin invariants |
| §19 + §20 | `wiki/playbooks/architecture/scripting-config.md` | OptiScript + unified config |
| §21 + §23 + §24 | `wiki/playbooks/architecture/spec-quality.md` | Spec hygiene + copilot uniformity + file size |
| §25 + §27 | `wiki/playbooks/architecture/distribution.md` | Branding + per-capability repo |
| §28 + §29 + §30 | `wiki/playbooks/architecture/performance.md` | Deterministic+accelerated + incremental + MCP aggregate |
| §31 + §32 + §33 | `wiki/playbooks/architecture/orchestration.md` | Cloud lanes + continuous orchestration + Session Mesh |

To pull a playbook into context: `mcp__wiki-mcp__wiki_get_page playbooks/architecture/<theme>` OR `Read wiki/playbooks/architecture/<theme>.md`.

---

## 16. Service & I/O discipline — non-blocking, service-owns-data

**Full:** [wiki/playbooks/architecture/runtime-services.md](../../wiki/playbooks/architecture/runtime-services.md) §16.

**Principle:** the DeskModal agent is a single Tauri process hosting N cdylib services + N webview apps; main thread + tokio loop + React render loop NEVER block on I/O. Services own canonical state; apps subscribe.

**7 invariants:** every long-lived service loop runs in its own `tokio::spawn`; per-cdylib runtime is `tokio::runtime::Builder::new_current_thread`; bounded channels everywhere with drop-on-overflow (≥4096 capacity; never `unbounded_channel`); no `Mutex`/`RwLock` across `.await` on hot paths (use ArcSwap/DashMap/atomics/actors); storage debounced + non-blocking via `spawn_persistence`/`spawn_hydration`; no `std::thread::sleep` / `block_on` inside tokio tasks; no synchronous HTTP/WebSocket in service code.

**No fallbacks (durable):** never ship "or X if Y" alternate paths; hard-fail with `rc ≠ 0` on unmet precondition. Runtime status surfaces are NOT fallbacks. Scalable + non-blocking + ultra-low-latency are 3 properties every fix must preserve simultaneously. No hardcoded data-source URLs — all in `plugin.toml [default_config]` + sdk-storage user keys.

**Pairs with:** §17, §28, parallelism.md §4.

## 17. Plugin architecture invariants — ServiceSDK + PluginSDK only

**Full:** [wiki/playbooks/architecture/runtime-services.md](../../wiki/playbooks/architecture/runtime-services.md) §17.

**Cardinal rule:** every plugin consumes platform capabilities via `@deskmodal/sdk-*` + `@deskmodal/fdc3` hooks; NEVER roll bespoke FDC3 bridges or custom `init*Service()` modules.

**9 SDKs (TS scope `@deskmodal/*`):** sdk-storage / sdk-notifications / fdc3 / sdk-services / sdk-window / sdk-observability / sdk-update / sdk-lifecycle / sdk-symbology. Plus `deskmodal-service-sdk` (Rust; `deskmodal_service_main!` macro + `spawn_persistence` + `ServiceClient`).

**8 BLOCKING audit gates:** sdk:discipline (no-localstorage/no-console/no-raw-window-fdc3) / sdk-package-coverage / window-sdk / dist-signed / broadcast-grants / app-token-imports / brand-subscription / fdc3-targetapp-shape.

**App `main.tsx` minimum:** `checkAppVersion(); initTheme(); createRoot(...).render(<App/>);` — that's it.

**Dist plugin shape:** `dist/plugins/<id>/{plugin.toml, app/, icons/, services/, publisher.pub, *.sig}`.

**User-authored data-sources (F127):** declarative `UserSourceDescriptor` entries in sdk-storage; AI-assisted authoring via `discovery-feed` service; clamped to `Community` tier.

**Tauri-native window decorations (durable):** every DeskModal window uses `decorations(true)` — native traffic lights (macOS) / native min/max/close (Windows + Linux GTK). ZERO custom React-side window-control rendering. Vocabulary: NEVER call this "chrome" (overloaded with browser); use "Tauri-native window decorations" / "OS-native title bar". `@deskmodal/sdk-window` IS the abstraction boundary — plugins NEVER import `@tauri-apps/api/window` directly. Forbidden patterns flagged by `quality:window-sdk` audit.

**Instrumentation discipline:** when N silent chain points + 1 observable failure exist, add tracing at EVERY point BEFORE any fix. Programmatic spawn (AppleScript / WebDriver / Tauri-cmd / DB-seed) REQUIRED to reproduce — never ask user to click + report.

**Pairs with:** §16, §25, §27, F125 lifecycle.

## 19. OptiScript-everywhere — scripts are the universal authoring layer

**Full:** [wiki/playbooks/architecture/scripting-config.md](../../wiki/playbooks/architecture/scripting-config.md) §19.

**Cardinal directive (user 2026-05-17 verbatim — durable per §1 honesty rule):** "algos should be optiscript, whereby users can edit any script... the optiscript service can then invoke back into apps, services via FDC3... this is the way all scripting should work, in an integrated way across DeskModal."

**Rule:** every algorithm (TWAP/VWAP/Iceberg/Sniper/Peg/multi-leg) + indicator (RSI/MACD/Bollinger/VPVR/TPO/footprint) + alert condition + screener filter + drawing-tool extension + AI-copilot tool + bot workflow is authored in **OptiScript**. Rust services are EXECUTION HOST layer; OptiScript is AUTHORING layer. Forbidden: hardcoded Rust algo logic when script-authored equivalent possible. Existing Rust impls become AOT-transpilation targets.

**7 architecture invariants:** Universal Execution Host (`optiscript-runtime`); native FDC3 primitives (`fdc3.broadcast/raise/listen`); tab-based editable UX (`.opti` sources → sdk-storage); reference-script library (e.g., `scripts/reference/twap.opti`); ≤ 2× hand-Rust perf via AOT transpile; capability manifest header per script; F143-D audit chain logs `script_source_hash + binary_hash + grants_hash + invocation_context_hash`.

**3 BLOCKING audit gates (queued):** quality:no-hardcoded-algo-logic / quality:script-manifest-grants / quality:script-audit-chain.

**Pairs with:** §16, §17, §5 (no V1/V2), F133 Pine v5 transpiler, F143-D, F141, F138, F134, F114.

## 20. Unified configuration + architecture documentation

**Full:** [wiki/playbooks/architecture/scripting-config.md](../../wiki/playbooks/architecture/scripting-config.md) §20.

**Cardinal directive:** unified extensible configuration experience where services + plugins register their config in DeskModal settings window if installed/enabled; persisted + restored; available via SDKs via a SINGLE intuitive library.

**8 rules:** Single unified `@deskmodal/sdk-config` SDK (no bespoke settings-IPC); config schema in `plugin.toml [services.<svc>.config]` (key/kind/default/label/description/category/validation?/secret?/restart_required?/depends_on?); auto-registering Settings UI in `plugins/deskmodal-settings/` (REQUIRED tier); cross-service shared settings under `deskmodal.*` namespace; capability-bundle packaging via `[bundle] optional_partners`; unified architecture docs at `specs/148-architecture-sota/`; audit-chain on every config change (F143-D + F141 W2.6); service-vs-app boundary discipline (state-holding + broadcast belong to cdylib).

**4 BLOCKING audit gates:** quality:no-bespoke-settings-ipc / quality:secrets-not-in-storage / quality:config-schema-coverage / quality:architecture-diagram-current.

**Pairs with:** F148, F149, core.md §5, §17 (sdk-* only).

## 21. Spec hygiene — every wave updates its spec atomically

**Full:** [wiki/playbooks/architecture/spec-quality.md](../../wiki/playbooks/architecture/spec-quality.md) §21.

**Cardinal directive:** every wave commit that lands impl/audit-gate/refactor/architectural-decision MUST atomically update the parent spec's §6 wave plan row + `benchmark.md` acceptance row + affected §Open concerns dispositions in the SAME commit.

**5 required per-wave spec touches:** flip §6 wave plan row QUEUED→LANDED-<sha>-<date>; mark benchmark acceptance status (GREEN/IN-FLIGHT/SCOPE-TRANSFERRED/ESCALATED) with evidence path; reflect §Open concerns dispositions; update §Implementation status block; cross-references (wave A affects spec B = one-line cross-ref in B citing A's commit).

**Forbidden:** wave landing without `git log <spec.md>` showing same wave's commit; "we'll update spec in next wave"; reviewer findings closed in-wave NOT in §Open concerns; replicated architectural primitives.

**BLOCKING audit gate (queued):** `scripts/audit-spec-currency.sh` (specs ≤ 7 days commit OR no impl-code in §Parallelism write-set changed).

**Pairs with:** §8 no-deferrals, §18.1 zero-tolerance, F148, `feedback_cutting_edge_scope_rich_specs`.

## 23. FDC3 Copilot Uniformity Pattern — every plugin can request + serve AI

**Full:** [wiki/playbooks/architecture/spec-quality.md](../../wiki/playbooks/architecture/spec-quality.md) §23.

**Cardinal directive:** DeskModal defines a canonical FDC3 intent suite for AI copilots (`deskmodal.Copilot.*`) so any FDC3-compliant plugin can RAISE these intents to receive AI assistance, AND any plugin can REGISTER itself as a copilot provider.

**7 canonical intents:** Ask / CompleteCode / Explain / Suggest / RegisterTool / UnregisterTool / QueryCapabilities. **Channels:** `deskmodal.copilot.{events, tools, streams.<conv_id>, suggestions}`.

**Provider model:** multiple plugins MAY register as copilot providers; FDC3 intent resolver picks per `findIntentsByContext` + sdk-config `copilot.default_provider`. Specialised providers declare context filters. Default copilot is universal fallback.

**Tool federation:** copilot dispatches FDC3 intents registered by plugins (e.g., order-engine `place_twap_order` tool backed by `deskmodal.Order.PlaceAlgo`). User-confirmation dialog per F143-D risk-gate → order placed → audit chain → result back to copilot.

**Forbidden:** plugin bespoke `Ask<X>Ai` / `<X>Suggest` intents; bypass sdk-fdc3; hardcoded copilot endpoints; bundled LLM in plugin.

**3 BLOCKING audit gates (queued F151 W4):** quality:copilot-fdc3-uniformity / quality:copilot-tool-registration / quality:copilot-endpoint-via-sdk-config.

**Pairs with:** F151, F141, F150, F148, F149, F147; copilot.md §22.

## 24. File size + decomposition discipline — split, NEVER cut

**Full:** [wiki/playbooks/architecture/spec-quality.md](../../wiki/playbooks/architecture/spec-quality.md) §24.

**Cardinal directive (user 2026-05-17 verbatim; NEVER FORGOTTEN):** "we had a directive for optimal file size and splitting full implementations across files, never cutting down capabilities, ensure this directive is never forgotten"

**The rule:** per-file ceiling ≤ 300 LOC for production source (`.rs` / `.ts` / `.tsx`). When approaching limit: SPLIT into cohesive sibling modules by CONCERN, NEVER cut capability/error-handling/edge-cases. Tests + fixtures + generated files exempt.

**8 decomposition checklist items:** identify cohesive concerns; move each to sibling `mod.rs + <concern>.rs` (Rust) or `index.ts + <concern>.ts` (TS); re-export public symbols at module root for stable import paths; SDK packages re-export from `src/index.ts`; per §5 no-V1/V2 — split in current commit; no `legacy/` co-existence.

**Forbidden:** "monolithic by design" pleading; cutting error-handling to fit; reducing test coverage to keep test files small; `// TODO: split later` comments.

**Pre-impl-pod decomp wave pattern:** when a single file holds > 50% of a planned pod's write-set, orchestrator dispatches a precondition decomp wave FIRST; impl pod then fans out across resulting sub-modules with disjoint write-sets. 30-40% wall-clock improvement vs monolithic.

**Audit gate `quality:per-file-loc-ceiling`** — currently ADVISORY; promote to BLOCKING in dedicated decomp sweep wave.

**Pairs with:** §5, §17, quality.md §18.4 axis 4, F134-W13 precedent (connection_manager.rs + fdc3.rs decomp).

## 25. Branding — single brand capability across every surface + OS conformance (NEVER FORGOTTEN)

**Full:** [wiki/playbooks/architecture/distribution.md](../../wiki/playbooks/architecture/distribution.md) §25.

**Cardinal directive (user 2026-05-17 verbatim; NEVER FORGOTTEN):** "single theming experience via the brands capability, optimally implemented across the editor, then in the settings to select brands, market to download published brands... fully configurable, brandable experience in the most intuitive way, then ensuring all plugins, all windows, fully adhere to the branding services, updating as brands are updated or installed... create the worlds most beautiful state of the art platform... bettering our competition in every way."

**11 rules:** `brand-service` cdylib (REQUIRED tier) is canonical broadcast source; `@deskmodal/sdk-brand` SDK (`useBrand` / `useBrandTokens` / `useBrandAssets` / `useBrandOsConformance` / `subscribeBrand`); comprehensive brand schema (palette OKLCH / typography / spacing 4px grid / radii / motion / glassmorphism / iconography / window-decorations / chart / trading-tokens / cursor+loading); dual-layer OS-native conformance + DeskModal evolution; brand editor (`plugins/brand-editor/`) with live preview + OKLCH picker + WCAG 2.2 AA contrast; Settings UI brand selector via sdk-config + live-swap < 100ms p99; marketplace `.dmbrand` signed bundles (Ed25519); mandatory adherence — every plugin/window/app subscribes; live update propagation; competitor SOTA target (beat TradingView + Bloomberg + IB TWS + NinjaTrader + OpenFin on every axis).

**Forbidden patterns:** hardcoded color literals in CSS/TSX; direct `import './theme.css'` bypassing sdk-brand; per-plugin hardcoded font/spacing/motion.

**F152 master spec** — 10-wave plan; W6 promotes `quality:design-tokens-complete` to BLOCKING workspace-wide.

**Pairs with:** §5, §17, §18.4.1, §20, §21, §23, F138, F130-W22, `feedback_workspace_ux_sota_bar`.

## 27. Per-capability repo + tier metadata + graceful degradation + footprint + licensing

**Full:** [wiki/playbooks/architecture/distribution.md](../../wiki/playbooks/architecture/distribution.md) §27.

**Cardinal directives (user 2026-05-17 verbatim):** "we should create repos optimally and through best practice with our plans to evolve individual components with AI Coding, but then considering which capabilities are optional/required/etc" + "nothing breaks if capabilities are not installed... making sure deskmodal an optimal on memory usage and installation size so users can step up and down capabilities... enabling deskmodal to license capabilities seperately"

**6 rules:** one repo per capability at `github.com/Desk-Modal/<id>`; 3-tier metadata in `plugin.toml [bundle]` (REQUIRED / RECOMMENDED / OPTIONAL); AI-driven evolution invariants (one AI agent = one repo per dispatch); cross-capability via FDC3 + `@deskmodal/*` SDKs; F153 migration of plugins/tradesurface legacy monorepo (6 waves); repo creation checklist (8 items: GitHub remote / plugin.toml `[plugin]+[bundle]+[license]+[resources]+[dependencies]` / own Cargo.toml or package.json / per-repo CI / README + llms.txt).

**Graceful degradation (§27.10):** FDC3 `findIntent()` BEFORE `raise()` for OPTIONAL/RECOMMENDED deps; sentinel UI patterns (`<CapabilityRequired>` + `<CapabilityOptional fallback={}>`); service-side `ServiceClient::has_grant()` before broadcast; cross-capability deps declared in `plugin.toml [dependencies] required/recommended/optional`; hot-swap install/uninstall via F125 lifecycle broadcast.

**Footprint targets (§27.11):** REQUIRED only ≤ 80MB disk + ≤ 250MB RAM idle; RECOMMENDED default ≤ 220MB + ≤ 450MB; ALL OPTIONAL ≤ 1.5GB + ≤ 1.2GB. Per-capability `[resources]` block declares `disk_mb / ram_mb_idle / ram_mb_peak / cpu_pct_steady`. Lazy-load + asset on-demand + step-down/step-up UX in Settings.

**Per-capability licensing (§27.12):** `[license] spdx + notice + terms_url` + optional `[license.commercial] model (subscription/per-seat/per-api-call/one-time/trial) + price + trial_days + license_check_endpoint + required_grants`. Ed25519-signed token cached at `dist/data/licenses/<id>.token`; re-verify on boot + every 24h. Expired = `license_expired` FDC3 response + CTA. Marketplace Verification Gateway enforces `[license]` presence. Enterprise = site-wide tokens.

**7 BLOCKING audit gates (queued F153 W6):** per-capability-repo / capability-tier-declared / no-cross-capability-shared-root / graceful-degradation / resources-declared / license-declared / dependencies-declared.

**Pairs with:** §17, §18.4.1, §20, §25, §16 (no-fallbacks — graceful degradation is USER-VISIBLE STATE), F125, F141, F143-D, `feedback_per_capability_repo`, `feedback_graceful_degradation_footprint_licensing`.

## 28. Deterministic + accelerated + perfect coding for mission-critical multi-agent (NEVER FORGOTTEN)

**Full:** [wiki/playbooks/architecture/performance.md](../../wiki/playbooks/architecture/performance.md) §28.

**Cardinal directive (user 2026-05-17 verbatim; NEVER FORGOTTEN):** "we do not want to lose updates, but we don't want to waste time, repeating slow processes.. we want the optimal deterministic, accelerated and perfect coding experience for massive mission critical products like DeskModal"

**Core insight:** git is the ONLY durable state; working tree is ephemeral. **13 invariants compound** to give perfect determinism + max acceleration + zero update loss:

1. Auto-commit-per-edit on canonical surfaces (`scripts/wave-commit.sh`)
2. Forbid `git stash` of orchestrator state (root cause of 2026-05-17 edit-loss incident)
3. Per-agent worktrees for parallel pods N≥3 (FS-level isolation)
4. Incremental cache discipline (NEVER `cargo clean`/`nx reset` mid-loop)
5. Audit-by-path dispatch + warm-agent SendMessage (token acceleration)
6. Tier A/B/C verification batching (`quality.md §18.7.1`)
7. Stale-agent recovery via SendMessage abort
8. Edit-verification triple-check (`discipline.md §26`)
9. Cache-aware ScheduleWakeup (60-270s in-cache; 1200-1800s post-cache; never 300s)
10. `scripts/wave-commit.sh` helper (atomic stage + commit canonical)
11. 3 BLOCKING audit gates queued (no-canonical-uncommitted / no-cargo-clean / agent-no-stash)
12. Cascading rule amendments (discipline.md / parallelism.md / agents.md / quality.md / settings.json deny-git-stash)
13. Session-coherent invariant (first 3 actions per wake: Read handoff / git status / nudge stalled agents; last 3 actions: dispatch / push / ScheduleWakeup)

**Pairs with:** §1 honesty, §3 CBM-first, §29, §30, parallelism.md §4 + §15, quality.md §18.7, discipline.md §26.

## 29. Incremental-only verification — never rebuild what hasn't changed

**Full:** [wiki/playbooks/architecture/performance.md](../../wiki/playbooks/architecture/performance.md) §29.

**Cardinal directive (user 2026-05-17 verbatim):** "deskmodal was built to allow incremental builds, and we should only rebuild something if it's actually changed... Update our processes so they're optimal" + "ensure we're not waiting to determine issues slowly"

**The principle:** every verification command MUST be scoped to what actually changed since the last green run. Workspace-wide rebuilds serve only as confirmation at logical-impact-batch boundaries (per §28.6 Tier C).

**3 verification modes:** Affected (DEFAULT, `--fast`, 5-30s); Workspace (`--fast --full-rebuild`, 2-5min, phase boundary); Pre-push (`--full --sign`, 10-15min, pre-push only).

**Per-gate change-gating rules:** every gate skips if scope unaffected (e.g., `platform:rust:fmt` skips if no `*.rs` under `platform/`; `quality:bundle-coherence` skips if no `plugin.toml` changed). Skips print `SKIP: <gate> (no changes since last-green)` — explicit not silent.

**Last-green checkpoint:** `.session-state/last-green.sha` records SHA of last `--fast --full-rebuild` rc=0. Subsequent runs use it as diff base. gitignored per-machine.

**Per-app incremental commands:** `cargo check -p <crate>` / `pnpm nx run @deskmodal/app-<name>:build` / `pnpm --filter <pkg> test` / `pnpm nx affected -t build --base=HEAD~5`.

**Cache-warming discipline:** target/`/`.nx`/`buildcache`/`.tsbuildinfo` MUST survive across waves. Forbidden mid-loop: `cargo clean` / `nx reset` / `rm -rf target/` / `rm -rf node_modules/` / `pnpm install --force`. Permitted reset points: `scripts/setup.sh --reset` OR `scripts/cleanup-build-assets.sh --apply` (F157 L13) OR pre-release `build-dist.sh --release`.

**Pairs with:** core.md §2, §28, quality.md §18.7.1, parallelism.md §15.

## 30. Aggregate MCP capabilities — deterministic Rust + visual-design SOTA (May 2026)

**Full:** [wiki/playbooks/architecture/performance.md](../../wiki/playbooks/architecture/performance.md) §30.

**Cardinal directives (user 2026-05-18 verbatim):** "how can we avoid clippy issues up front... ultimate deterministic claude code rust experience" + "optimal aggregate capabilities with rust-analyzer with our other plugins and mcps... optimal mcps and plugins for visual design" + "we need to ensure we do not slow things down too much... best mix of results and speed."

**The principle:** every code-discovery / diagnostic / library-docs / visual-verification question dispatches to the MCP whose latency × correctness × scope is optimal for that question shape. Per-question-shape routing, NOT one-MCP-rules-all.

**7 registered MCP servers:** codebase-memory-mcp (50-500ms; symbol graph) / wiki-mcp (100-300ms; synthesis) / rust-analyzer (100-500ms; LSP) / playwright (1-3s; browser) / github (200-800ms; PR/CI) / context7 (500ms-2s; library docs) / chrome-devtools-mcp (5-15s; Lighthouse/perf/memory at Tier C only).

**Extended MCP discovery matrix (§30.2):** type/coercion/borrow-check → rust-analyzer; symbol/calls/impact → CBM; cross-cutting synthesis → wiki-mcp; library docs → context7; visual+a11y → playwright; Lighthouse/heap/perf → chrome-devtools-mcp; PR/CI → github; plain markdown/TOML/YAML → Grep/Read.

**3-tier Rust prevention discipline (§30.3):** Tier 1 pre-write `rust_analyzer_hover` (OPT-IN); Tier 2 `rust_analyzer_workspace_diagnostics` (MANDATORY in Rust agent return); Tier 3 `cargo check -p <crate>` (MANDATORY). Combined budget 5-30s per agent; saves minutes of compile retry.

**Per-persona MCP routing requirement (§30.6):** Rust agents MUST cite `rust_analyzer_diagnostics + cargo_check_per_crate` in return JSON; UI agents MUST cite playwright snapshot path + axe-core score.

**Speed budgets:** Rust impl ~6-32s prevention; UI impl ~4-6s visual; logical-impact-batch ~15-20s Lighthouse.

**3 BLOCKING audit gates queued:** rust-agent-return-contract / mcp-routing-discipline / ui-agent-visual-evidence.

**Anti-patterns banned:** Grep on `.rs/.ts/.tsx/.py` before CBM; Grep/Read on `wiki/**` before wiki-mcp; manual `cargo check` parse loop when `rust_analyzer_workspace_diagnostics` answers in ~500ms; manual screenshot when `browser_take_screenshot` is 2 tool calls.

**Pairs with:** core.md §1 + §2 + §3, §28, §29, agents.md return contract, quality.md §18.7.1, parallelism.md §4.

## 31. Cloud-lane operational rules — monitoring + aggregator + visual critique

**Full:** [wiki/playbooks/architecture/orchestration.md](../../wiki/playbooks/architecture/orchestration.md) §31.

**Cardinal directive (user 2026-05-18 verbatim):** "how can we monitor the cloud lanes too? How will the lanes consider their value in aggregate with the other apps, consistent design, integration with deskmodal capabilities such as notifications, ai, fdc3 and all other capabilities... how will the lanes visually critique and determine optimal intuitivity..."

**Operational rules for 3 lane types:** per-app research / cohesion-aggregator / visual-critique.

**Lane creation contract (§31.1):** fresh-clone start (no CBM continuity) / bounded write-set / self-contained brief / NO source-file edits (`.rs/.tsx/.ts/.py/.toml` forbidden) / NO canonical-file edits / push to main via `git pull --rebase` (3 retries).

**Cohesion-aggregator authority (§31.2):** ONLY lane authorised to propose CROSS-app contracts; reads ALL per-app spec-suggests + SDK manifest + cohesion contract; cadence 6-hourly +3h offset; 10 cohesion dimensions × N apps per cycle.

**Visual-critique authority (§31.3):** ONLY lane authorised for user-perspective visual evaluation; 3 modes (single-app/multi-tab/suite); weekly Mon 06:00 UTC; 10 MacOS-school criteria × 3 modes × N apps.

**Monitoring command (§31.4):** `scripts/monitor-cloud-lanes.sh` — daily; `--watch` continuous; `--json` machine-readable; per-lane fields (name/cadence/last_run/next_run/enabled/SHA/status). Staleness threshold = 2× cadence_hours.

**Anti-pattern banned (§31.5):** per-app brief proposing cross-app behaviour. Required path: per-app surfaces observation → aggregator matches across multiple → produces cross-app amendment → orchestrator dispatches local impl pod.

**Pairs with:** core.md §1 + §4, discipline.md §26, parallelism.md §4, parallel-sessions.md, quality.md §18.7, §17, §21, §23, §25, F154 cloud-lane charter.

## 32. Continuous lane orchestration — zero-idle invariant + conflict-free dispatch + sync-to-targets

**Full:** [wiki/playbooks/architecture/orchestration.md](../../wiki/playbooks/architecture/orchestration.md) §32.

**Cardinal directive (user 2026-05-18 verbatim):** "we should ensure all lanes are used at all times, so we must have an orchestrator planning optimally ahead, so the lanes don't conflict and we have full synchronisation with our targets, and then building and testing all" + "we should be using our local lanes and agents too optimally for tasks which suit running on the desktop" + "we should only allocate tasks to the cloud in which it can be useful and high quality, otherwise we should continuously ensure our local lanes are utilised, with /loop".

**7 invariants:** zero-idle invariant (orchestrator MUST NOT leave LOCAL lane capacity idle when dispatchable backlog exists); conflict-free dispatch contract (no agent dispatch without conflict-matrix gate; pairwise-disjoint write-set requirement pre-dispatch); auto-replan on every event (agent return / git push / cron fire / failed gate / human directive / timeout); sync-to-targets ledger advances ≥ 1 F-spec milestone per dispatch; banned anti-patterns (`I'll plan when this returns`; cloud-impl-tasking; workspace-wide verification per wave; cloud Rust dispatch; cloud `launch.sh --verify`; idle local lane while cloud research blocks);

**Local-lane /loop saturation (§32.7 FIRST-priority operational rule):** local lane utilisation is FIRST priority; cloud lanes are SECOND priority and only when value-quality gate (F155 spec §4.8) passes all 5 tests. Per /loop wake: check local utilisation FIRST; dispatch up to 4 more if < 3 local in-flight (cap 7); only after local saturated to ≥ 5/7: consider firing cloud manually; backlog overfull is orchestrator's job.

**Banned posture:** waiting on user-confirmation for ONE non-blocking question while ≥ 2 local lanes sit idle. Dispatch parallel work first; ask question concurrently.

**Pairs with:** F155 master spec, parallelism.md §4 + §15, quality.md §7 + §18.1 + §18.7, parallel-sessions.md, discipline.md §9 + §13 + §26, §16 + §21 + §27 + §28 + §29 + §30 + §31.

## 33. Session Mesh — multi-session coordination (F157 Layer 11)

**Full:** [wiki/playbooks/architecture/orchestration.md](../../wiki/playbooks/architecture/orchestration.md) §33.

**Cardinal directive (user 2026-05-18 verbatim):** "evolve this so we can run multiple parallel claude sessions across deskmodal so they do not create loss, interrupt, or ideally they somehow learn and collaborate, it's critical we're not creating too much expense, unnecessary replication, and we want to deliver code and outcomes fast"

**The Session Mesh at `.session-state/mesh/`** is the filesystem-backed coordination layer for parallel Claude sessions on the same machine. Sessions don't directly message each other (agent-teams' role, high cost); they SHARE a ledger of claims + findings + heartbeats.

**8 mesh scripts at `scripts/session-mesh/`:** `claim-write-set.sh` (declare bounds + check conflicts) / `release-write-set.sh` / `heartbeat.sh` (called per Stop hook) / `share-finding.sh` (write to findings bus) / `list-findings.sh` (read from other sessions) / `find-conflicts.sh` (pairwise overlap check) / `check-concurrency.sh` (report active sessions vs cap).

**Discipline:** SessionStart hook calls claim + list-findings 24h; Stop hook calls heartbeat (renews claim); PreCompact releases claim; PostCompact re-claims; SessionEnd releases. Other sessions see this session via heartbeat; respect write-set.

**Session-scoped twin of §32 cross-session continuous-lane orchestration.** §32 owns cross-session coordination (cloud lanes, audit gates); §33 owns local-session coordination (work-claim, findings bus, heartbeat).

**Pairs with:** §32, F157 spec at `specs/157-autonomous-delivery-operating-model/spec.md`, `feedback_api_load_concurrent_agents`, `feedback_f157_autonomous_delivery`.
