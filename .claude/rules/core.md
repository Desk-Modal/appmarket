# Core rules

One file. Read this before touching the codebase. Referenced by every persona; they inherit it.

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

Specs and rules are *cited from*, not *discovered through*. Use the active feature spec for current intent; use rules/agents for workflow contract; use CBM for code; use wiki-mcp for synthesis.

## 4. Parallelism — single-agent default; pods reserved

**Default: ONE impl agent per wave.** Opus 4.7 with 1M ctx handles cross-stack work (Rust + Tauri command + TS bridge + React + CSS) better in one agent than three coordinated ones. Contract-edge violations become impossible because the agent owns both sides. Token cost drops ~50%.

**Pods (parallel impl agents) reserved for narrow cases only:**
- Pure CSS/token sweep (style-bot) — disjoint from any impl work.
- Perf benches (own bench files, no impl).
- Independent docs wave (no code writes).

Not a pod case: anything with Rust↔TS crossing, anything touching a Tauri command + its TS caller, anything where one persona's output is another's input.

**Reviewers are ALWAYS parallel** — dispatched in one `Agent` batch per §7. They're read-only; no race risk; the parallelism is pure wall-clock win.

**Speculative next-wave dispatch (default ON, 2026-05-16):** while reviewers run on wave N, dispatch wave N+1's impl agent against the CURRENT HEAD (post-impl, pre-review). If wave N reviewer returns APPROVE/APPROVE_WITH_COMMENTS, rebase N+1's diff onto post-integration tip and keep. If REWORK with overlapping write-set, discard N+1 (log to `.session-state/speculation-log.md`) and re-dispatch after integration. If BLOCK/ESCALATED, discard unconditionally. Saves 10–20 min per wave; reviewer-cost-only when N+1 is discarded. Opt-out: `DESKMODAL_SPECULATIVE=0`.

**Pod ceiling (2026-05-16):** when write-sets are PROVEN pairwise-disjoint (audited via `scripts/audit-wave-write-sets.sh`), dispatch up to `N = min(7, count_of_disjoint_tasks)` impl agents in parallel. Hard cost ceiling: 7 concurrent. Default (no audit): conservative 3-cap. The 7-cap unlocks linear wall-clock scaling on mechanical sweeps; correctness preserved by disjointness audit.

**Dispatch hygiene — audit by path, never by quote (2026-05-16):** when an agent's prompt references an audit/spec/finding, pass the **file path** for it to read once at start. Inline-quoting full audit excerpts in every parallel dispatch burns ~30–80K tokens per agent. The agent reads the source once; you save token cost linearly with N agents.

**Warm-agent reuse via SendMessage (2026-05-16):** when wave N+1 is a follow-up that depends on wave N's loaded context (e.g. plugin-sdk-engineer already has the SDK contract in conversation), continue it via `SendMessage(to: <agent-id>)` instead of `Agent()`. Saves the ~30–50K cold-start re-read. Only valid when wave N+1 is genuinely a continuation, not a fresh task.

Every task spec declares:

```markdown
## Parallelism
- Reads: <paths or globs>
- Writes: <paths or globs>
- Contract produces: <named symbols this wave creates>
- Contract consumes: <named symbols this wave calls from existing code>
- Dispatch shape: single-agent | pod | pipeline
```

Invariants:
- Single-agent waves use ONE `Agent()` call. The agent edits in-place and returns a unified diff via JSON (never commits).
- Pod waves (rare): write-sets MUST be pairwise disjoint. `scripts/pod-apply.sh` applies all patches atomically or rolls all back.
- Single-writer files (never written by sub-agents): `.session-state/**`, `.prod-check/**`, `specs/compat-ladder.yml`, `.specify/memory/constitution.md`, `.claude/rules/**`, `.claude/settings.json`.

No worktree mandate. Claude picks per-dispatch execution isolation.

Determinism preserved by: declared write-sets per task, task-number-ascending merge-train, mandatory parallel reviewer batch, single-writer state files. None of the above amendments touch these invariants.

## 5. Production code

No TODO, FIXME, HACK, placeholder, demo mode, stub, commented-out dead code in shipped code.
No `console.log` or `println!` in library crates (use the structured logger).
No versioned interfaces (`FooV2`, `NewBar`) — evolve in place.
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

## 9. Handoff protocol

Commit-driven. When a commit moves task state, the post-commit hook appends to the active handoff (`.session-state/handoff.md` by default, or a per-feature handoff under `.session-state/handoffs/<id>.md`). You edit free-form context on the next turn if needed.

Session pressure checkpoint: at ≥ 70% of context window, write a fresh handoff before `/clear`. Below that, commits are the durable state; no preemptive handoffs required.

## 10. Stop signals

Stop when: the task converges, the user says stop, or a blocker requires human input. Never stop because "I can't verify visually" — find another path (logs, DOM inspection, source read). Never stop without stating what verified vs what didn't.

## 11. Escape hatch

`DESKMODAL_LAX=1` bypasses any non-safety gate. Every use is audit-logged via the honesty hook. Use only when the user has authorised in-session or when diagnosing a hook false-positive.

## 12. Tool discipline

- No `--no-verify` on commits unless you've proven the hook is producing a false positive and document the diagnosis in the commit body.
- No `--force` push.
- No deleting branches, files, or data without confirming the state is recoverable.
- No invoking `sync-specs.sh --apply` while another session is actively editing sub-repo canonical files — canonical file ownership is split, see `.claude/rules/parallel-sessions.md`.
- One terminal + one cloud + one `/launch --verify` in flight at a time per machine (launch-lockfile at `/tmp/deskmodal-launch.lock`).

## 13. Autonomy protocol

Goal: user never re-pastes prompts or re-explains context. State lives in git + `.session-state/`.

On session start, the `context-load` SessionStart hook prints: active feature, branch + ahead/behind, gate state, latest handoff entry. Read that before asking the user anything.

When resuming a task:
1. Read `.session-state/handoff.md` (workspace) or `.session-state/handoffs/<feature>.md` (per-feature). Skip any hypothesis in the "Dead-ends" section.
2. Read the active feature's `spec.md` + `benchmark.md` (if applicable).
3. Re-verify live state — gates, branch, dirty files — don't trust the handoff as ground truth. Handoff is a SNAPSHOT; the gate file is LIVE.
4. Continue. Do not ask the user to re-state the goal unless you have hit a BLOCK.

Between sessions:
- A commit is the durable checkpoint. Post-commit hook appends to the handoff automatically.
- `.session-state/active-feature` (optional) holds one feature-id string; the statusline surfaces it.
- Never claim "I don't have context" — write a handoff and continue.

## 14. Output style

Claude Code default output style for this workspace is `concise`. Prefer:
- Short, dense sentences. Commands over descriptions.
- State changes and decisions directly. Cite file:line, exit codes, SHAs.
- No teaching tone. No motivational framing. No "let me explain."
- End-of-turn summary = 1-2 sentences MAX. What changed + what's next.
- Working update = 1 sentence per key moment (finding, direction change, blocker).

## 15. Wave discipline — evolve-and-fix-forward (NEVER ROLL BACK)

**Cardinal rule: every wave moves forward.** Reviewer REWORK / BLOCK / HIGH findings close via a **subsequent commit on top of the current HEAD**, never via `git reset --hard`, `git revert`, or any destructive rewind. Rollback is banned as a wave-mechanic because it discards partial-value work the next wave would otherwise build on.

**The four invariants (replace the old rollback-based ITER-02 mitigations):**

1. **Impl Agents NEVER commit or push.** Agent instructions explicit: "edit files in-place. Do NOT `git commit`. Do NOT `git push`. Return your work as a unified diff via JSON field `patch`." If an agent returns `commit_sha` (committed behind the orchestrator): the orchestrator reconciles by adding a follow-up commit that completes the contract (never resets). The violation is logged to the handoff for persona-prompt tuning.

2. **Pre-wave snapshot is ADVISORY, not enforced.** `scripts/wave-sandbox.sh init` still captures `WAVE_BASE=$(git rev-parse HEAD)` so reviewers have a stable reference for their diffs. `assert-clean` still runs — if HEAD moved, that becomes a persona-tuning signal, **NOT** a rollback trigger. The orchestrator's response to HEAD-moved is: inspect, accept if the change is consistent with wave scope, fix-forward if not.

3. **Reviewer REWORK = one or more follow-up commits on the same branch.** Findings close in the order they reduce risk (BLOCKING → HIGH → MEDIUM → LOW). Each close is a separate small commit whose message cites the finding ID. Re-review runs against the final HEAD after all follow-ups land. Max 2 rework cycles; cycle 3 = ESCALATE to user, not reset.

4. **Pod integration is evolution-safe.** `scripts/pod-apply.sh` applies patches in declared order; if verification fails after apply, the fix is **another commit on top** (usually a reviewer-finding closure), not a reset. The pod's atomic guarantee is about patch application, not about undoing committed work.

**Agent-rejection handling (replaces wave-abort):**
- Rejected / errored Agent → inspect the partial state. If files are untouched, re-dispatch with sharpened prompt. If files were edited and the partial patch is usable, accept + close reviewer findings via follow-up commits. No reset.
- Non-APPROVE self-assessment → still integrate the patch, then dispatch a scoped follow-up to close the `open_concerns`.

**What's still prescribed (unchanged):**

5. **Wave ceiling.** Max 3 rows per wave when truly independent. Max 1 row when contract edges exist between personas in the wave. Smaller waves = smaller rework surface.

6. **Shift-left scope review.** Before impl dispatch, a single `qa-architect` review pass validates the wave's `## Parallelism` section and Acceptance clauses. Catches contract holes at spec-time (cheap).

7. **Contract-edge serialization.** When the wave has persona-to-persona contract edges, serialise — never dispatch in parallel. Each step commits before the next Agent dispatches.

**Verification cadence (batching discipline, tightened 2026-05-16):**
- `scripts/local-ci.sh --fast` runs ONCE PER PHASE (at impl-wave integration gate; after all wave-rework follow-ups land — not per agent, not per row, not per intermediate commit).
- `scripts/launch.sh --verify` runs ONCE PER PHASE (only when the phase touches GUI/FDC3/dist), after all reviewer findings close.
- `scripts/local-ci.sh --full` runs ONLY pre-push (or pre-PR), never per-wave.
- Never per-row. Never per-persona. Never per-agent. Per-agent verification adds 2–5 min per dispatch × N agents per phase = 10–30 min wasted wall-clock; the agent's own type-check + the integration `--fast` cover correctness.

**What this rule forbids:**
- `git reset --hard <any-prior-sha>` as a wave-mechanic response to reviewer findings.
- `git revert` of an in-wave commit unless a reviewer finding specifically requests reversion as the fix-forward (rare; typically the fix is amend-on-top).
- `wave-sandbox.sh rollback` as the default response to REWORK. The script's `rollback` subcommand is deprecated; use `wave-sandbox.sh fix-forward` (no-op stub that logs the finding for handoff) instead.
- "Throw away the Agent's work and re-dispatch fresh" as a first response. Re-dispatch only when the partial state is fundamentally unsalvageable (rare).

**What this rule requires:**
- Every reviewer BLOCKING / HIGH finding has a named close-out commit (or scope-transfer / escalation ledger entry) BEFORE the benchmark row is marked green.
- The post-commit-handoff hook records each close-out commit with its finding ID so future sessions see the fix-forward trail.

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
