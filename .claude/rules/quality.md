---
title: Quality discipline
authority: derives from `core.md`; topic-file for §5 + §6 + §7 + §8 + §11 + §18
load_when: reviewing impl, dispatching reviewer pod, closing findings, hygiene-sanity per /loop wake, deciding test scope, world-class terminal-condition checks
---

# Quality discipline

Topic file — sections preserved by number for stable cross-references. §18.1–§18.8 are **stubs**: each anchor + its cardinal/user-quote directive (verbatim) + 2–3 invariants stay IN-FILE; verbose bodies live in `wiki/playbooks/quality/*.md` (NOT auto-loaded; queried on demand via `mcp__wiki-mcp__wiki_get_page playbooks/quality/<theme>`).

## Wiki playbook map

| § range | Playbook | Theme |
|---|---|---|
| §18.1 + §18.2 + §18.3 + §18.4 + §18.4.1 + §18.5 + §18.6 | `wiki/playbooks/quality/hygiene-discipline.md` | Zero-tolerance + 5-axis hygiene + cleanup + marketplace-distribution + wiki-sync + persistence |
| §18.7 + §18.7.1 + §18.7.2 + §18.7.3 | `wiki/playbooks/quality/parallel-verify-cadence.md` | Always-parallel + verification-cadence-batching + never-block-resumability + scoped-tests+test-currency |
| §18.8 | `wiki/playbooks/quality/world-class-verification.md` | World-class verification (10 terminal criteria) |

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

**Full §18.1–§18.6:** [wiki/playbooks/quality/hygiene-discipline.md](../../wiki/playbooks/quality/hygiene-discipline.md). **Full §18.7–§18.7.3:** [wiki/playbooks/quality/parallel-verify-cadence.md](../../wiki/playbooks/quality/parallel-verify-cadence.md). **Full §18.8:** [wiki/playbooks/quality/world-class-verification.md](../../wiki/playbooks/quality/world-class-verification.md).

### 18.1 Zero tolerance for suboptimal when optimal available

**Full:** [hygiene-discipline.md](../../wiki/playbooks/quality/hygiene-discipline.md) §18.1.

Every `open_concern` returned by every Agent dispatch closes as exactly one of three dispositions: **CLOSED-IN-WAVE** / **SCOPE-TRANSFERRED-TO-{NAMED-WAVE}** (receiver wave must already exist with a write-set covering the fill) / **ESCALATED-TO-USER** (declared question + impact + proposed default; halts the benchmark row). Banned phrases the orchestrator rejects in any commit/handoff/agent-return: "good enough for now" / "we'll get to it later" / "leave as-is for v2" / "stub for W1; W2 fills" (unless W2 exists) / "pre-existing on origin/main" / "outside my write-set" / "acceptable trade-off for now" without cited alternative / bare "DEFERRED". Strengthens §8 + §15.

### 18.2 Continuous hygiene across all 5 workspace axes

**Full:** [hygiene-discipline.md](../../wiki/playbooks/quality/hygiene-discipline.md) §18.2.

5 hygiene axes audited every wave; debt never accumulates: **Plugins** (per-capability `.dmpkg`, 3 tiers REQ/REC/OPT) / **MCPs** (5 live + latest; CBM-first) / **Specs** (≥1200 LOC carrying SOTA+target+gap+wave-plan) / **Legacy assets** (no `*V2*` / `legacyMode` / TODO-FIXME-HACK / stray `console.log`; stale docs DELETED) / **SOTA refactoring** (native async-fn-in-traits, UUIDv7, simd-json, cap-std, PGO+LTO+codegen-units=1, criterion 0.5, cargo-llvm-cov).

### 18.3 Per-wake hygiene sanity check (5 questions, ~5 seconds)

**Full:** [hygiene-discipline.md](../../wiki/playbooks/quality/hygiene-discipline.md) §18.3.

Orient-step of every `/loop` wake: (1) Plugins `ls plugins/*/services/`; (2) MCPs index freshness; (3) Specs `wc -l specs/*/spec.md | sort -n | head -5`; (4) Legacy `find . -name '*V2*'` + TODO/FIXME/HACK grep; (5) SOTA grep for `Mutex|unbounded_channel|thread::sleep|block_on`. Findings flow into Step 2 as SCOPE-TRANSFERS or CLOSED-IN-WAVE.

### 18.4 Per-iteration cleanup wave (every 5-7 wave-batches)

**Full:** [hygiene-discipline.md](../../wiki/playbooks/quality/hygiene-discipline.md) §18.4.

Dedicated cleanup wave sweeps all 5 axes workspace-wide; deletes stale files; converts production `console.log` → `getLogger()` (`@deskmodal/sdk-observability`); tightens over-permissive gates; refreshes deps (`cargo update` + `pnpm update`, security-engineer reviews); bumps wiki `last_canonical_sha`; regenerates `wiki/inventory/{apis,plugins,sdks,dependencies}.md`. Acceptance: every axis 0 findings.

### 18.4.1 Distribution target — DeskModal marketplace git, never npm/crates.io

**Full:** [hygiene-discipline.md](../../wiki/playbooks/quality/hygiene-discipline.md) §18.4.1.

User directive 2026-05-17 (verbatim — preserved per §1 honesty rule): "we do not publish to NPM. Remove any reference to NPM. plugins, services, crates etc are published to our market git. They need to be signed, manifested, icons, descriptions, etc. Our local CICD should handle this for now and we can evolve the experience for non-deskmodal employees later, but we want to build state of the art docs etc."

Every plugin/service/SDK/crate ships as a signed `.dmpkg` (Ed25519 + manifest + icon + description) via `scripts/build-dist.sh --sign` → marketplace git. `@deskmodal/*` names retained as identity but NEVER pushed to npmjs.org/crates.io. Cross-capability deps in `plugin.toml [dependencies]` (required/recommended/optional — the implemented §27.10 mechanism; R-SDKDEPS-POLICY 2026-06-12 retired the never-implemented `[sdk_dependencies]`/`[plugin_dependencies]` vocabulary in favour of this single block), not package.json. Docs target SOTA (TypeDoc + rustdoc + JSON Schema + llms.txt at `docs.deskmodal.io`).

### 18.5 Wiki + MCP synchronization

**Full:** [hygiene-discipline.md](../../wiki/playbooks/quality/hygiene-discipline.md) §18.5.

Every commit adding/removing/renaming a plugin/service/SDK/intent/channel MUST trigger a wiki regen (`wiki-gen-apis.sh` / `wiki-gen-plugins.sh` / `wiki-gen-sdks.sh` / `wiki-gen-dependencies.sh`) so `wiki-mcp` always knows where every implementation lives.

### 18.6 Cross-session persistence

**Full:** [hygiene-discipline.md](../../wiki/playbooks/quality/hygiene-discipline.md) §18.6.

This rule is canonical at `.claude/rules/core.md §18` (git-tracked + mirrored to all 7 sub-repos via `sync-specs.sh --apply`). Every dev on every machine gets the same contract via `git pull`. Per-user supplementary notes live in `~/.claude/projects/-Users-adrian-deskmodal/memory/feedback_*.md`.

### 18.7 Always-parallel + always-verify discipline (durable; never forget)

**Full:** [parallel-verify-cadence.md](../../wiki/playbooks/quality/parallel-verify-cadence.md) §18.7.

User directive 2026-05-17 (verbatim — preserved per §1 honesty rule): "you need to leverage cloud sessions, multiple agents etc, we should always be delivering and verifying optimally" + "never forget this, then /loop using this approach and our entire SDLC until all waves are 100% complete and verified."

**Per /loop wake:** never hold single-agent posture when ≥2 parallel-safe disjoint waves exist (dispatch a pod ≤7 per `core.md §4`); **LOCAL-ONLY delivery — cloud lanes DISABLED** (user directive 2026-05-23 verbatim: "deliver all with local agents and not cloud"); verify in parallel (`local-ci.sh --fast` in background while agents work); push opportunistically; capacity floor 3 / ceiling 7; disjointness audited via `scripts/audit-wave-write-sets.sh` when N>3; heartbeat ScheduleWakeup armed 1700s. **Terminal condition** = entire SOTA scope closed (every benchmark row green + every S-ID verified + every gap closed + every BLOCKING gate green + `local-ci.sh --full --sign` rc=0 + `launch.sh --verify` rc=0 + every open_concern dispositioned). Keep iterating; never stop "because we made progress".

### 18.7.1 Verification cadence — batch at logical impact, never per-wave (durable)

**Full:** [parallel-verify-cadence.md](../../wiki/playbooks/quality/parallel-verify-cadence.md) §18.7.1.

User directive 2026-05-17 (verbatim — preserved per §1 honesty rule): "we should do verification at logical batches of impact, not each wave if it slows us down, we need to organise optimally, and save time repeating tasks instead of optimally organising at peak."

3 tiers: **A. Agent-self** (own write-set; every wave; ~30s; `cargo check -p` / `pnpm --filter`) / **B. Phase-boundary** (`local-ci.sh --fast` ONCE per logical-impact-batch; ~2-5min) / **C. Pre-push** (`local-ci.sh --full --sign` + `launch.sh --verify`; once pre-push or per impact-batch; ~10-15min). Never repeat Tier-B between consecutive waves of one batch (defeats incremental cache); never run Tier-C per-wave.

### 18.7.2 Never block — cross-session + cross-dev resumability (durable)

**Full:** [parallel-verify-cadence.md](../../wiki/playbooks/quality/parallel-verify-cadence.md) §18.7.2.

User directive 2026-05-17 (verbatim — preserved per §1 honesty rule): "we should also make sure we're never blocking if possible, we should be optimally leveraging cloud, agent teams, local agents, etc. ... then ensure this is always applied across all sessions, memory contexts and resumed across our devs computers by pulling from the github and starting claude, or when restarting claude sessions for deskmodal locally."

Core invariant: never wait idle when parallel-safe forward-progress exists. Persistence layer: CANONICAL (git; survives `/clear` + restart + cross-dev `git pull` + compaction) / PER-USER auto-memory / LOCAL TRANSIENT handoff. **Canonical contracts NEVER depend on per-user memory** — git is the single source of truth.

### 18.7.3 Scoped test execution + test-currency discipline (durable)

**Full:** [parallel-verify-cadence.md](../../wiki/playbooks/quality/parallel-verify-cadence.md) §18.7.3.

User directive 2026-05-17 (verbatim — preserved per §1 honesty rule): "we should ensure our settings also include creating optimal and logical tests target towards the specific context, and ensuring tests are always updated, never out of date, and we run tests logically, whereby were only need to build and verify the changed scope, not run entire suites of unnecessary tests to verify a specific change."

Two principles: **scoped execution** (default scope = agent's declared write-set; `cargo test -p <crate>` not `--workspace`; workspace-wide only at phase boundary; hot-cache discipline) + **test currency** (tests evolve in lockstep — behavioural change updates assertion; rename updates imports; removed fn deletes test; new fn adds ≥1 test; coverage ≥80% per crate). Audit gate (BLOCKING; queued): `quality:test-currency`.

### 18.8 World-class verification — utterly-perfect terminal (durable; never forget)

**Full:** [world-class-verification.md](../../wiki/playbooks/quality/world-class-verification.md) §18.8.

User directive 2026-05-17 (verbatim — preserved per §1 honesty rule): "evolved further with the learnings so far, so we have the most beautiful fully implemented, stylish, intuitive mission critical products that are fully verified across all functionalities, gui components, apis, etc. Resolving and recurring in the loop until utterly perfect and world class, which will be based up review and critiques"

Every wave + commit + pillar held to the world-class bar via 10 numbered criteria: (1) adversarial reviewer pod every wave (converge to APPROVE unanimous); (2) functional verification batched per §18.7.1; (3) GUI/visual at impact-boundary (CDP + axe-core WCAG 2.2 AA + pixelmatch ≤0.1% + responsive @3 breakpoints + theme parity + Jony-Ive cleanliness + Tauri-native decorations); (4) API (JSON Schema + OpenAPI 3.1 + cargo-public-api + llms.txt + JSDoc/rustdoc); (5) cross-stack FDC3 conformance; (6) §16 non-blocking + latency budgets; (7) aesthetic SOTA; (8) iterate-until-perfect (max 3 rework cycles, cycle 4+ ESCALATES); (9) amended terminal condition; (10) banned postures (no "functional but visually rough").

**Pairs with §7 (reviewer matrix) + §18.1 (zero tolerance) + §18.7 (always-parallel always-verify) + §S-UX/S-SCREEN/S-PRESET (visual pillars) + `feedback_workspace_ux_sota_bar`.**
