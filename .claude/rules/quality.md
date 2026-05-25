---
title: Quality discipline
authority: derives from `core.md`; topic-file for §5 + §6 + §7 + §8 + §11 + §18
load_when: reviewing impl, dispatching reviewer pod, closing findings, hygiene-sanity per /loop wake, deciding test scope, world-class terminal-condition checks
---

# Quality discipline

Topic file — sections preserved by number for stable cross-references.

## 5. Production code

No TODO, FIXME, HACK, placeholder, demo mode, stub, commented-out dead code in shipped code.
No `console.log` or `println!` in library crates (use the structured logger).
**No versioned interfaces of any kind.** DeskModal is pre-public; zero users. **We can break and redesign anything that doesn't meet our targets** — no `FooV1` / `FooV2` / `FooV3` ladders, no `legacy` / `compat` / `shim` wrappers, no parallel-major coexistence, no version-prefixed directories (`v1/`, `v2/`), no version-named files (`*_v2.rs`, `interface_v3.ts`), no version-suffixed types/traits/functions/CSS-classes/intents/channels/manifest-IDs. Evolve in place. Delete the old surface in the same commit that introduces the new one. Independent semver per crate/SDK in marketplace manifests (`plugin.toml [plugin] version`, `package.json version`, `sdk.toml [sdk] version`) is for install/update tracking only — the API SURFACE itself never carries a Vx label. If a contract change would warrant a "v2" elsewhere, here it lands as an in-place redesign with the call-sites updated in the same wave. Forbidden patterns (would fail review): `FooV2`, `NewBar`, `legacyMode`, `enableLegacy`, `*compatShim*`, `*backwardCompat*`, `interface/*/v[0-9]*/`, files named `*-v2.*` / `*_v2.*` / `*V2*` outside `tests/fixtures/` + `_deprecated-*/`. Audit gate: `core.md §18` axis 4 (Legacy assets) scans for these patterns each wave.
No new locks — `ArcSwap`, `DashMap`, `flume`, atomics, or actors.
Error handling on every async op; loading state for every async UI.
Zero hardcoded absolute paths — use `${CLAUDE_PROJECT_DIR}` or computed relative.
Zero hardcoded colors in CSS/TSX — use `--deskmodal-*` / `--ts-*` tokens.

**No pre-existing drift survives a wave.** Every wave's verification covers the **whole workspace**, not just the declared write-set:
- `cargo fmt --all --check` rc=0 across every workspace member.
- `cargo clippy --workspace --all-targets -- -D warnings` rc=0.
- `pnpm nx run-many -t lint,typecheck` rc=0 across the affected Nx graph.
- Any workspace member with a compile error, fmt drift, or clippy warning at wave-integration time is fixed as part of the wave — even if the file is outside the declared write-set. "Pre-existing on origin/main" is not a valid handwave; if `local-ci.sh --fast` shows red, the wave is not done. The fix lands in the same wave commit (or a sibling cleanup commit with `chore:` prefix); never deferred.
- Exception: if a workspace-wide fix is genuinely too large to land in the current wave (>200 LOC unrelated to the wave's intent), scope-transfer to a named cleanup task per §8 and block integration until that task lands. Never carry a `[expected pre-existing failure]` note forward.


## 6. Naming

| Kind | Convention | Example |
|---|---|---|
| Components | PascalCase | `OrderBook.tsx` |
| Hooks | camelCase with `use` | `useTileKeyboard.ts` |
| Services | kebab | `feed-service.ts` |
| Types | PascalCase | `ExchangeAdapter` |
| Constants | SCREAMING_SNAKE | `MAX_RECONNECT_ATTEMPTS` |
| CSS tokens | `--ts-{category}-{property}` | `--ts-surface-primary` |
| FDC3 app IDs | `deskmodal.{name}` | `deskmodal.feeds` |
| **User-facing extension noun** | **"App"** (DeskModal-branded; matches App Market + appstore.html brand; OpenFin / Refinitiv Eikon / VS Code / Slack convergence) | "Install an App", "Apps panel", "Browse Apps" |
| **Engineering plugin manifest** | **"plugin"** (engineering vocabulary; never user-displayed) | `plugin.toml`, `plugins/<id>/`, `plugin_install` Tauri command, `PluginLifecycleManager`, `dmpkg` CLI |

**2-layer naming rule (canonical 2026-05-24 per F-naming-apps decision; pairs with F158 user-experience.md §22 Naming discipline):** Engineering layer = "plugin"; user-facing layer = "App". **NEVER introduce a 3rd layer ("Capability", "Extension", "Add-on", "Module") in user-visible copy.** "Capabilities" is permitted in ENGINEERING contexts only (architecture.md §27 "per-capability repo + tier + footprint + licensing" concept; `[bundle] tier` plugin.toml field; `audit-capability-*.sh` build gates; `CapabilityDescriptor` Rust/TS types; `lifecycle_capabilities_*` Tauri command IDs; `useCapabilities` React hook). User-visible surfaces (UI strings, toast text, dialog labels, README copy, button labels, story-table titles in user-experience docs) MUST use "Apps". Audit gate: `quality:apps-vocab-discipline` (queued; F158 §22.6). Forbidden user-visible patterns: "Capabilities panel" / "Install capabilities" / "Capability picker" / etc. — would fail review.


## 7. Reviewer matrix (conditional)

DeskModal is a domain-agnostic plugin platform. Reviewers are dispatched by capability, not domain:

| Signal | Mandatory reviewer |
|---|---|
| Universal (every task) | `qa-architect` |
| Rust / Tauri / platform core | `rust-systems-architect` |
| React / TSX / agent-shell surface | `frontend-architect` |
| Script runtime / editor / plugin SDK | `plugin-sdk-engineer` |
| Signing / ACL / auth / supply-chain / secrets | `security-engineer` |
| Plugin↔platform IPC / channels / loader | `integration-architect` |
| FDC3 channels / intents / bridge | `fdc3-protocol-engineer` |
| User-visible surface | `ux-design-lead` (review), `trading-ux-architect` (design, trading-only) |
| Plugin fixture manifest has `categories ⊇ {trading, market-data, finance, derivatives}` OR raises order/pnl/position intents | `trading-sme` **conditional** |
| Chart plugin fixture / chart engine | `charting-expert` |
| Marketplace aggregator / catalog / storefront | `marketplace-qa` |

`trading-sme` is never universal. Non-financial tasks (tile-container shell, FDC3 bridge, docs) do not dispatch it.

All reviewers for a task dispatch in **one parallel `Agent` batch** (one assistant message, N tool calls). Sequential reviewer dispatch is a defect.


## 8. No deferrals

Every reviewer finding exits as one of: **CLOSED** (fixed in rework this iteration), **SCOPE-TRANSFERRED** (ownership moves to a named sibling task whose Acceptance section is amended in the same commit), or **ESCALATED** (paused for user — halts the wave). "Handle later" / "follow-up task TBD" / "track in a future ADR" is rejected.


## 11. Escape hatch

`DESKMODAL_LAX=1` bypasses any non-safety gate. Every use is audit-logged via the honesty hook. Use only when the user has authorised in-session or when diagnosing a hook false-positive.


## 18. Quality discipline — zero tolerance + continuous hygiene

**The cardinal rule (user directive 2026-05-17, verbatim — preserved per §1 honesty rule):** "we should ensure there's never any exceptions where an optimal solution is available and resolve absolutely all weaknesses, incomplete implementations, or issues, adding them to subsequent waves or within the current wave if optimal, ensure you apply this for all deskmodal sessions, and remember across sessions, memory clearance etc"

### 18.1 Zero tolerance for suboptimal when optimal available

Every `open_concern` returned by every Agent dispatch closes as exactly one of three dispositions:

- **CLOSED-IN-WAVE** — fixed in this iteration's commit. No follow-up needed.
- **SCOPE-TRANSFERRED-TO-{NAMED-WAVE}** — receiver wave-id explicitly cited (e.g. `SCOPE-TRANSFERRED-TO-F143-W7`). The receiver wave MUST already exist in its spec's §6 wave plan with a write-set that covers the fill. Missing receiver = invalid transfer; close inline or escalate.
- **ESCALATED-TO-USER** — declared question + impact + proposed default; orchestrator surfaces immediately. Halts wave benchmark-row from going green until user resolves.

Banned phrases the orchestrator rejects in any commit message, handoff, or agent return:
- "good enough for now"
- "we'll get to it later"
- "leave as-is for v2"
- "stub for W1; W2 fills" *unless* W2 already exists with a declared write-set including the fill
- "pre-existing on origin/main" (per §5 no-pre-existing-drift-survives-wave)
- "outside my write-set" (per §15 evolve-and-fix-forward — fold or scope-transfer with ledger)
- "acceptable trade-off for now" without cited alternative
- bare "DEFERRED" without one of the 3 dispositions

The orchestrator's per-wake protocol (Step 2 "handle returns") verifies every agent's `open_concerns` carry valid dispositions BEFORE marking the wave's benchmark row green. Strengthens §8 no-deferrals + §15 evolve-and-fix-forward.

### 18.2 Continuous hygiene across all 5 workspace axes

DeskModal has 5 hygiene axes; every wave audits all 5; debt never accumulates:

| Axis | Authority | Cardinal heuristic |
|---|---|---|
| **Plugins** | §17 + per-capability-plugin-granularity | Every capability ships as standalone `.dmpkg` at `plugins/<id>/`. 3 tiers: REQUIRED / RECOMMENDED / OPTIONAL. Independent versioning + per-crate install/uninstall |
| **MCPs** | §3 + CBM-first-discovery | 5 MCPs (CBM, wiki-mcp, rust-analyzer, playwright, github) live + latest version. Every code-discovery question through CBM first. `auto_index_limit = 500000` with headroom for growth |
| **Specs** | cutting-edge-scope-rich-specs | Every spec ≥1200 LOC carrying §Current-state-of-art + §DeskModal-target + §Gap-analysis + §Wave-plan. Service-tier explicit for stateful/perf-critical features (§16 + §17) |
| **Legacy assets** | §5 + delete-not-coexist | No `*V2*` filenames. No `legacyMode` toggles. No TODO/FIXME/HACK in shipped code. No `console.log` outside benchmarks. Stale proposal docs DELETED — not archived in tree |
| **SOTA refactoring** | F144 May-2026-Rust-migration + §16 | Adopt current SOTA: native async fn in traits, UUIDv7, simd-json on hot paths, cap-std for sandboxed I/O, PGO + LTO + codegen-units=1, criterion 0.5, cargo-llvm-cov |

### 18.3 Per-wake hygiene sanity check (5 questions, ~5 seconds)

Add to the orient step of every `/loop` wake:

1. **Plugins** — `ls plugins/*/services/` — does any capability violate per-capability granularity?
2. **MCPs** — `tools/codebase-memory-mcp config list` — are all 8 indices fresh? `auto_index_limit` enough?
3. **Specs** — `wc -l specs/*/spec.md | sort -n | head -5` — any SKELETAL spec under 1000 LOC?
4. **Legacy** — `find . -name '*V2*' -not -path '*/_deprecated*' -not -path '*/node_modules/*' -not -path '*/test*'` + `grep -rE '\b(TODO|FIXME|HACK)\b' platform/crates/*/src plugins/*/services/*/src plugins/tradesurface/packages/*/src`.
5. **SOTA** — `grep -rn 'std::sync::Mutex\|unbounded_channel\|std::thread::sleep\|block_on' platform/crates plugins/tradesurface/services` — 0 outside documented cold-path exceptions.

Findings flow into Step 2 (handle returns) as new SCOPE-TRANSFERS or CLOSED-IN-WAVE fixes.

### 18.4 Per-iteration cleanup wave (every 5-7 wave-batches)

Schedule a dedicated cleanup wave that:
- Sweeps all 5 axes workspace-wide for findings.
- Deletes stale files (proposal docs > 30 days unimplemented; orphaned evidence dirs; abandoned `*_v2*` filenames).
- Renames any `legacyMode` toggles (currently 0).
- Converts production `console.log` → `getLogger()` from `@deskmodal/sdk-observability`.
- Tightens audit gates where they're too permissive (e.g. `rule_no_console_log` skip of `*/packages/*` is too broad).
- Re-runs `cargo +stable update` + `pnpm update` to refresh dependencies (security-engineer reviews).
- Bumps wiki `last_canonical_sha` after canonical edits.
- Regenerates `wiki/inventory/{apis,plugins,sdks,dependencies}.md` so MCPs always know where every implementation lives.

The cleanup wave's acceptance: every axis shows 0 findings.

### 18.4.1 Distribution target — DeskModal marketplace git, never npm/crates.io

User directive 2026-05-17 (verbatim — preserved per §1 honesty rule): "we do not publish to NPM. Remove any reference to NPM. plugins, services, crates etc are published to our market git. They need to be signed, manifested, icons, descriptions, etc. Our local CICD should handle this for now and we can evolve the experience for non-deskmodal employees later, but we want to build state of the art docs etc."

- Every plugin / service / SDK / Rust crate ships as a signed `.dmpkg` (or `.dmpkg-sdk`) bundle with Ed25519 signature + manifest + icon + description.
- Publish flow: local CI/CD (`scripts/build-dist.sh --sign`) → marketplace git (`marketplace/appmarket/` + `marketplace/plugin-index/`).
- Consumer install: `dmpkg install <name>@<version>` — signature-verified bundle extraction.
- Dependencies declared in `plugin.toml [sdk_dependencies]` or `[plugin_dependencies]`, NOT package.json npm refs.
- `@deskmodal/*` names retained as identity but bundles are NEVER pushed to npmjs.org / crates.io / any external registry.
- External non-DeskModal-employee publish flow is future scope; current state covers internal distribution.
- Docs target stays SOTA (TypeDoc + rustdoc + JSON Schema + llms.txt at `docs.deskmodal.io`) — docs are developer-facing AND AI-discoverable.

### 18.5 Wiki + MCP synchronization

Every commit that adds/removes/renames a plugin, service, SDK, intent, or channel MUST trigger a wiki regen:
- `scripts/wiki-gen-apis.sh` — FDC3 intents + Tauri commands inventory.
- `scripts/wiki-gen-plugins.sh` — plugin registry.
- `scripts/wiki-gen-sdks.sh` — SDK registry.
- `scripts/wiki-gen-dependencies.sh` — dependency graph.

So `wiki-mcp` always knows where every implementation lives; cross-cutting synthesis stays current; new sessions discover capabilities via MCP queries, never via stale grep.

### 18.6 Cross-session persistence

This rule is canonical at `.claude/rules/core.md §18` (git-tracked + mirrored to all 7 sub-repos via `scripts/_deprecated-2026-04-23/sync-specs.sh --apply`). Every dev on every machine gets the same contract via `git pull`. Per-user supplementary notes live in `~/.claude/projects/-Users-adrian-deskmodal/memory/feedback_*.md` files.

### 18.7 Always-parallel + always-verify discipline (durable; never forget)

User directive 2026-05-17 (verbatim — preserved per §1 honesty rule): "you need to leverage cloud sessions, multiple agents etc, we should always be delivering and verifying optimally" + "never forget this, then /loop using this approach and our entire SDLC until all waves are 100% complete and verified."

**The contract on every /loop wake:**

1. **NEVER hold a single-agent posture when parallel-safe work exists.** Inventory the DAG; if ≥ 2 waves have pairwise-disjoint write-sets and unmet dispatchable readiness, dispatch them as a parallel pod (≤ 7 concurrent agents per `core.md §4`).

2. **LOCAL-ONLY delivery — cloud lanes DISABLED (user directive 2026-05-23 verbatim; preserved per §1 honesty rule):** "deliver all with local agents and not cloud". All implementation / docs / audit / spec / research work runs via local `Agent` dispatches on this machine. `RemoteTrigger` (cloud Routines) is NOT used for any F156+ wave. Cloud lanes that previously fired (F141 open-questions / F143-D venue research / F142-C orderflow research) STAY disabled until user reverses. Rationale: cloud lanes (a) cannot see Session Mesh claims so they collide with local work, (b) cannot access uncommitted parallel-session state, (c) burn separate cloud credits with no offsetting throughput gain vs the 3-agent local cap, (d) integrate via git which serializes against local pushes anyway. Local 3-agent pods per `feedback_api_load_concurrent_agents` empirical cap remain the SOLE delivery mechanism.

3. **Always verify in parallel with dispatch.** `scripts/local-ci.sh --fast` runs in background (`run_in_background: true`) while impl agents work. Verifies workspace stays clean. Failures surface immediately, not at end-of-pod.

4. **Verification cadence per `core.md §15`:** `local-ci.sh --fast` once per phase boundary (not per wave); `launch.sh --verify` once per phase touching GUI/FDC3/dist. But the BACKGROUND `--fast` discipline can run more frequently for continuous-greenness signal.

5. **Push outer + sub-repos opportunistically.** Every committed wave triggers `git push origin main` (rebase + retry on race). Cloud workers fresh-clone on each firing; pushed commits land on their next clone.

6. **Continuous loop posture until "100% complete and verified":** the /loop terminates ONLY when **the entire SOTA scope** is closed — defined as ALL of:
   - Every benchmark.md row in EVERY spec under `specs/` (currently 27 feature dirs spanning F100 through F146+) marked green with evidence path cited.
   - Every SOTA pillar assertion in `specs/SOTA-MASTER/00-research/sota-bar.md` (212+ S-IDs across §2.1 through §2.17, plus any added F144 S-RUST + F146 S-SDK pillars) verified per its declared `cargo bench` / `cargo test` / `scripts/audit-*` / `python scripts/cdp-test-runner.py` command.
   - Every gap row in `specs/SOTA-MASTER/00-research/gap-analysis.md` closed.
   - Every BLOCKING audit gate in `local-ci.sh --fast` and `local-ci.sh --full --sign` green.
   - `scripts/local-ci.sh --full --sign` rc=0 (workspace-wide; not just incrementally clean).
   - `scripts/launch.sh --verify` rc=0 with CDP evidence captured for the full DeskModal app + every shipping plugin.
   - Every wave's `open_concerns` dispositioned per §18.1 (no orphan SCOPE-TRANSFER or undispositioned ESCALATION).
   - User-stated terminal condition matched verbatim ("all waves are 100% complete and verified" = the workspace-wide SOTA scope, not just a single feature's waves).
   
   Until ALL of the above hold, keep iterating; never stop "because we made progress". The /loop is the continuous-delivery engine; the SOTA-MASTER pillar set is the acceptance contract.

7. **Capacity heuristic:** if fewer than 3 agents are in flight AND the DAG has dispatchable waves, the orchestrator is under-utilizing and MUST plan the next pod immediately (not wait for current returns).

8. **Disjointness contract:** every pod dispatch verifies pairwise-disjoint write-sets via `scripts/audit-wave-write-sets.sh` when N > 3. Conflicts → serialize OR partition write-sets at the file level (different files in the same dir is acceptable if no semantic coupling).

9. **Disposition discipline (§18.1) applies to every wave's returned `open_concerns`** — orchestrator verifies CLOSED-IN-WAVE / SCOPE-TRANSFERRED / ESCALATED before marking the wave green. Never lets a wave land with un-dispositioned concerns.

10. **Heartbeat ScheduleWakeup always armed** to 1700s for the cache-miss-cost-bounded fallback. Harness wakes on each task-notification or wakeup tick — orchestrator never sleeps inactive.

**Banned posture:**
- Single agent in flight + heartbeat armed = under-utilization. Plan more dispatches before ScheduleWakeup.
- Sequential local impl when parallel-safe pod is possible.
- Skipping cloud lanes "because they don't return fast enough" — they integrate via git, latency is irrelevant.
- Waiting for current pod to fully return before planning next pod — speculative N+1 dispatch per `§4` runs the next wave against current HEAD while reviewers run.
- "Verification at the end" — verify in parallel, surface failures immediately.

**This rule pairs with §18.1 (zero tolerance) + §18.2 (5-axis hygiene) + §15 (evolve-and-fix-forward) + §4 (parallelism + speculation) + §16 (non-blocking) + §17 (plugin architecture) + §18.4.1 (marketplace distribution) + §18.8 (world-class verification).**

### 18.7.1 Verification cadence — batch at logical impact, never per-wave (durable)

User directive 2026-05-17 (verbatim — preserved per §1 honesty rule): "we should do verification at logical batches of impact, not each wave if it slows us down, we need to organise optimally, and save time repeating tasks instead of optimally organising at peak."

**The contract — three verification tiers:**

| Tier | Scope | Cadence | Cost |
|---|---|---|---|
| **A. Agent-self** | The agent's own write-set (one crate / one package / one feature) | EVERY wave (mandatory; agent declares rc=0 in return) | ~30s per agent (cargo check -p / pnpm --filter / fmt / clippy / tests on its scope) |
| **B. Phase-boundary** | The integrated wave-batch (set of waves that landed together) | ONCE per phase boundary — after the pod-of-N integrates + reviewer findings close | `scripts/local-ci.sh --fast` (~2-5 min workspace-wide) |
| **C. Pre-push / pre-release** | Workspace-wide full-fidelity + GUI/CDP | ONCE pre-push for `--full`; ONCE per logical-impact-batch for `launch.sh --verify` | `scripts/local-ci.sh --full --sign` (~10-15 min) + `scripts/launch.sh --verify` (~5-10 min with CDP) |

**"Logical impact batch" = a coherent capability surface that lands across N waves.** Examples:
- F140-A W1+W2+W3+W4 = "collab capability end-to-end" → ONE Tier-C `launch.sh --verify` after W4 lands, not after each W.
- F143-D W1+W2+W3+W2.5 = "order-engine + risk-gate + venue-router + types carve-out" → ONE Tier-C verify after the batch lands.
- F142-C W1+W2 = "orderflow channels + 4 cdylib services" → ONE Tier-C verify after W2 lands.
- F144 W1+W2+W3 = "toolchain + workspace standards + lints" → ONE Tier-C verify after W3 lands.

**Batching rules:**
1. **Never repeat Tier-B between consecutive landing waves of the same logical batch** — Cargo's incremental cache is wasted if --fast runs after every wave commit. Run --fast ONCE after the wave-batch fully integrates.
2. **Never run Tier-C per-wave** — Tier-C costs 10-15 min wall-clock; reserve for logical-impact-batch boundaries OR pre-push.
3. **Tier-A is mandatory per wave** because it's scoped + cheap (30s) AND the agent already does it as part of its return contract. Don't conflate Tier-A with Tier-B/C.
4. **Background `local-ci.sh --fast` (Tier-B)** runs in parallel with pod dispatch per §18.7 #3 — the same `--fast` run satisfies the phase-boundary requirement IF the pod was the phase-boundary. Don't re-run.

**Anti-pattern:**
- Running `cargo check --workspace` + `pnpm nx run-many -t test` after EVERY wave's commit → 5-10 min × N waves = 50+ min wasted per phase.
- Running `launch.sh --verify` after a docs-only commit → wasted GUI launch.
- Running Tier-B before all pod-mates' impl waves have landed → false RED on transient incomplete state.

**Pairs with §15 wave discipline + §18.7 always-parallel-always-verify + §18.8 world-class verification (which §18.7.1 BATCHES rather than per-wave-runs).**

### 18.7.2 Never block — cross-session + cross-dev resumability (durable)

User directive 2026-05-17 (verbatim — preserved per §1 honesty rule): "we should also make sure we're never blocking if possible, we should be optimally leveraging cloud, agent teams, local agents, etc. at this to our claude settings and all other optimisations, then ensure this is always applied across all sessions, memory contexts and resumed across our devs computers by pulling from the github and starting claude, or when restarting claude sessions for deskmodal locally."

**Core invariant: never wait idle when parallel-safe forward-progress exists.** Dispatch heuristics live in §18.7 (capacity floor 3 / ceiling 7, speculative N+1, cloud lanes, background verify, parallel reviewer batches). This section covers the **persistence layer** that makes those heuristics survive every restart path.

#### 18.7.2.1 Resumability across restart paths

| Layer | Path | Survives | Restart paths covered |
|---|---|---|---|
| CANONICAL | `.claude/rules/`, `.claude/agents/`, `.claude/skills/`, `.claude/hooks/`, `.claude/settings.json`, `.mcp.json`, `specs/`, `wiki/`, `scripts/` | git | `/clear`, same-machine restart, **different-dev's machine** (`git pull`), mid-session compaction |
| PER-USER (auto-memory) | `~/.claude/projects/-Users-adrian-deskmodal/memory/{MEMORY.md, feedback_*.md, project_*.md}` | per-user durable | `/clear`, same-machine restart, mid-session compaction (NOT cross-dev) |
| LOCAL TRANSIENT | `.session-state/{handoff.md, active-feature, launch-evidence/}` | per-machine ephemeral | Nothing (gitignored; intentional) |

Every new rule in core.md auto-propagates: ALL devs after `git pull` + ALL Claude sessions after SessionStart hook + ALL sub-repos after `sync-specs.sh --apply`. **Canonical contracts NEVER depend on per-user memory** — git is the single source of truth for newly-arrived devs.

#### 18.7.2.2 Banned postures (extends §18.7's never-block list)

- **Per-dev memory-file dependency for canonical contracts** — every contract surface lives in git.
- **"Wait for X to land before doing Y"** when Y has disjoint write-set from X — speculative N+1 OR parallel dispatch.

**Pairs with §4 parallelism + §18.7 always-parallel-always-verify + §18.7.1 verification-batching + §18.8 world-class-verification.**

### 18.7.3 Scoped test execution + test-currency discipline (durable)

User directive 2026-05-17 (verbatim — preserved per §1 honesty rule): "we should ensure our settings also include creating optimal and logical tests target towards the specific context, and ensuring tests are always updated, never out of date, and we run tests logically, whereby were only need to build and verify the changed scope, not run entire suites of unnecessary tests to verify a specific change."

**Two principles:** scoped test execution (run only what's affected) + test currency (tests evolve in lockstep with code).

#### 18.7.3.1 Scoped test execution

Use the right tool for the right scope:

| Goal | Command | Cost |
|---|---|---|
| One Rust crate | `cargo test -p <crate>` | ~5-30 s |
| Crates touched by current diff | `cargo test -p <crate1> -p <crate2> ...` (compute from `git diff --name-only`) | ~10-60 s |
| One TS package | `pnpm --filter @deskmodal/<pkg> test` | ~3-15 s |
| Affected TS projects (Nx) | `pnpm nx affected -t test` (uses git base for diff) | ~5-30 s |
| Workspace-wide Rust | `cargo test --workspace` | 2-10 min |
| Workspace-wide TS | `pnpm nx run-many -t test` | 2-10 min |
| Single test | `cargo test -p <crate> -- <test_name>` / `pnpm --filter <pkg> test -- <pattern>` | ~1-5 s |

**Default scope = the agent's declared write-set.** An agent that touched `plugins/tradesurface/services/order-engine/src/risk_gate.rs` runs `cargo test -p deskmodal-order-engine` (one crate), NOT `cargo test --workspace`. Tier-A per §18.7.1.

**Workspace-wide test run only at phase boundary** (Tier-B per §18.7.1) — once per logical-impact batch, never per-wave.

**Hot-cache discipline:** Cargo + Nx + Vite incremental caches survive across waves IF you run scoped commands. `cargo test -p X` keeps the cache for Y warm; `cargo test --workspace` defeats it. Same principle for `pnpm nx affected` vs `run-many`.

#### 18.7.3.2 Test currency — tests evolve in lockstep with code

Every wave's agent MUST update tests when the function they test changes:
- **Behavioural change** → update the assertion. Agent return must cite the test file:line updated + the new acceptance.
- **API surface rename** → update the test imports. `grep -rn "<old_name>" tests/` and fix.
- **Removed function** → delete the corresponding test (or repurpose if functionality moved).
- **New function in declared write-set** → add ≥ 1 test for it. Coverage budget per §18.8 #2 keeps line coverage ≥ 80% per crate.

**Out-of-date test detection:**
- `cargo test --no-run` should compile every test (catches API drift even when behaviour-tests aren't run).
- `pnpm tsc --noEmit` typechecks tests against current types.
- `cargo-llvm-cov --workspace --fail-under-lines 80` flags coverage regressions per S-RUST-05 (F144 spec).
- `pnpm nx affected -t test --skip-nx-cache` validates affected-test currency without cache.

**Audit gate (BLOCKING; queue for future wave):** `quality:test-currency` — fails if `cargo test --no-run --workspace` rc≠0 (test compilation drift) OR coverage drops below per-crate floor.

#### 18.7.3.3 Agent dispatch implications

Every `Agent` impl prompt MUST specify the test scope explicitly:
- "Run `cargo test -p <crate>` and assert rc=0" (NOT `cargo test --workspace`).
- "Add ≥ N tests for new functions in your write-set; update tests where behaviour changes."
- "Tier-A verification per §18.7.1 — agent-self-scope only."

The orchestrator runs Tier-B workspace tests ONCE per logical-impact batch (per §18.7.1) — agents never run workspace-wide tests as part of their wave.

#### 18.7.3.4 Banned postures

- Running `cargo test --workspace` after a single-crate change (Tier-B cost for Tier-A scope).
- Skipping test updates because "behaviour didn't change" — verify by re-reading the test against the new function signature.
- Adding new functions without ≥ 1 test (per S-RUST-05 + per-package vitest convention).
- Stale `*.test.ts.bak` / `*.test.rs.orig` files retained in tree (legacy per §5).
- Test files that don't compile but aren't run (out-of-date drift).

#### 18.7.3.5 Settings impact

`.claude/settings.json` permissions already permit scoped commands (`cargo test:*`, `pnpm test:*`, `pnpm nx:*`). No new env vars needed — the discipline is at the agent-dispatch + orchestrator-verify level, codified in this rule.

**Pairs with §15 wave discipline batching + §18.7.1 verification-batching + §18.8 world-class-verification (functional + coverage + benchmarks).**

### 18.8 World-class verification — utterly-perfect terminal (durable; never forget)

User directive 2026-05-17 (verbatim — preserved per §1 honesty rule): "evolved further with the learnings so far, so we have the most beautiful fully implemented, stylish, intuitive mission critical products that are fully verified across all functionalities, gui components, apis, etc. Resolving and recurring in the loop until utterly perfect and world class, which will be based up review and critiques"

Every wave + every commit + every pillar acceptance is held to the world-class bar. The /loop's terminal condition (§18.7 #6) is amended:

1. **Adversarial reviewer pod on every wave** — not optional, never deferred. Per §7 conditional reviewer matrix, every wave dispatches its mandatory reviewers in ONE parallel `Agent` batch immediately after impl returns. Reviewers MUST return APPROVE / APPROVE_WITH_COMMENTS to mark the wave green. REWORK loops back to impl with findings; BLOCK halts the wave. Re-review after rework re-runs the SAME parallel batch (no rubber-stamping).

2. **Functional verification — batched per §18.7.1 (Tier A per-wave; Tier B per logical-impact batch; Tier C pre-push or per impact-batch).** No "skipped" tests without explicit `#[ignore]` justification.

3. **GUI / visual verification — batched per §18.7.1 at impact-boundary, NOT per wave** (e.g. CDP captures after F140-A W4 closes the full collab capability, not after each W1/W2/W3/W4):
   - **CDP screenshots** + **axe-core WCAG 2.2 AA** (0 BLOCKING) + **pixelmatch** (≤ 0.1% pixel-diff) per evidence-row under `specs/<feature>/evidence/<row>/`.
   - **Responsive @ 3 breakpoints** (300×500, 1280×800, 1920×1080) per S-SCREEN-02.
   - **Theme parity** dark + light per S-UX-06.
   - **Jony-Ive cleanliness** per `feedback_workspace_ux_sota_bar` (disclosure over presence, ≤8 visible controls, tabular-nums, glassmorphism dual-blur, spring-easing, 4px grid, zero hardcoded colours).
   - **Tauri-native decorations** per §17 (zero custom-decoration rendering).

4. **API verification — every public surface:**
   - **JSON Schema** exported for every TS type via `tsc --declaration` + post-process to JSON Schema.
   - **OpenAPI 3.1** spec for every FDC3 intent + Tauri command surface.
   - **Rust public API** stability tracked via `cargo-public-api` snapshot diff in CI; intentional MAJOR bumps reviewed.
   - **`llms.txt` index** at every SDK root (per §18.4.1 docs target).
   - Every public function carries JSDoc/rustdoc citing the spec § where it's mandated.

5. **Cross-stack contract verification — every FDC3 intent end-to-end:**
   - FDC3 2.2 conformance test suite (`cargo test -p deskmodal-bridge -- fdc3_2_2_conformance`) rc=0.
   - `quality:fdc3-targetapp-shape` + `quality:broadcast-grants` + `quality:fdc3-intents` BLOCKING gates green.
   - Every channel in `wiki/inventory/apis.md` has ≥ 1 producer + ≥ 1 consumer; `scripts/audit-fdc3-cohesion-graph.sh` rc=0.

6. **Mission-critical reliability invariants — every service:**
   - §16 non-blocking discipline: zero `Mutex/RwLock` across `.await`; ArcSwap/DashMap/atomics; bounded channels; current_thread runtime; spawn_persistence + spawn_hydration.
   - Latency budgets per `specs/latency-budgets.yml` — every declared p99 met under load bench.
   - Panic-recovery: `catch_unwind` traps per cdylib; service restart per `restart_policy = permanent`.

7. **Aesthetic SOTA — "beautiful + stylish + intuitive" measurable:**
   - Every Screen passes the §S-SCREEN-* pillars + `audit-design-system-and-screens.md` parts A + B.
   - Glassmorphism dual-blur (S-UX-11) on every floating layer.
   - Cmd+K coverage (S-UX-03) ≥ 95% of commands.
   - No verbose-GUI anti-patterns (icon strips > 6, redundant labels, dupe-value displays, splash screens) per S-SCREEN-05.

8. **"Iterate until utterly perfect" termination:**
   - Re-review until ALL adversarial reviewers return APPROVE (no APPROVE_WITH_COMMENTS — those concerns close in this or named-sibling wave first).
   - No "good enough" close-outs (banned per §18.1).
   - Max rework cycles per wave = 3; cycle 4+ ESCALATES to user per §18.1.
   - Cycle through impl → review → rework → re-review until APPROVE unanimous OR ESCALATED.

9. **The amended terminal condition (extends §18.7 #6):**
   - ALL §18.7 #6 criteria (every benchmark row green / every S-ID verified / every gap closed / every BLOCKING gate green / local-ci --full --sign rc=0 / launch.sh --verify rc=0 / every open_concern dispositioned).
   - **PLUS** every wave's adversarial review batch returned APPROVE unanimous (no outstanding APPROVE_WITH_COMMENTS).
   - **PLUS** every GUI/visual change has CDP+axe-core+pixelmatch evidence captured in `specs/<feature>/evidence/`.
   - **PLUS** every API change has updated JSON Schema + OpenAPI + JSDoc/rustdoc + llms.txt.
   - **PLUS** every cdylib service passes the §16 non-blocking + S-P-* latency budgets under bench load.
   - **PLUS** every Screen passes Jony-Ive cleanliness + S-SCREEN-* pillars + WCAG 2.2 AA.

10. **Banned posture:**
    - Closing a wave without dispatching the adversarial reviewer batch.
    - Marking "APPROVE_WITH_COMMENTS" as terminal (must converge to APPROVE).
    - Skipping CDP visual evidence for any user-facing change.
    - Accepting "tests pass" without GUI/CDP/visual/API/perf cross-cuts.
    - "Functional but visually rough" — explicitly NOT world-class.

**This rule pairs with §7 (reviewer matrix) + §18.1 (zero tolerance) + §18.7 (always-parallel always-verify) + §S-UX/S-SCREEN/S-PRESET (visual pillars) + `feedback_workspace_ux_sota_bar` (Jony-Ive cleanliness everywhere).**

