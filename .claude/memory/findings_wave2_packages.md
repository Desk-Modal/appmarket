---
name: Wave 2 Findings — Package Audit (7 packages)
description: Deep code audit of all 7 tradesurface packages — 2 critical, 9 high, 18 medium, 8 low findings
type: project
---

## CRITICAL (2)

**C1 — 12 of 16 FDC3 context interfaces do NOT extend `Context` base type.** Only `AggregatedPriceContext`, `StaleDataContext`, `OrderbookContext`, `DataSourceStatusContext` extend it. The other 12 are not assignable to `Context`, breaking `channel.broadcast()` type safety.

**C2 — `useDeskModalExtensions` only exposes 3 of 14 DeskModal API subsystems.** Only `streamingBroadcast`, `sharedStorage`, `statusBar` accessible. Missing: `notification`, `shortcuts`, `toolbar`, `appStorage`, `audit`, `sound`, `a11y`, `dlp`, `windowGroup`, `workspace`.

## HIGH (9)

- **H1:** `DeskModalAPI` type missing `analytics` subsystem used by `core/monitoring/deskmodal-telemetry.ts`
- **H2:** `DesktopAgent` interface missing `findIntent` method (standard FDC3 2.2)
- **H3:** `FEEDS_MANIFEST` has empty `listensFor` — intents won't route to feeds
- **H4:** `ALERTS_MANIFEST` has empty `listensFor` — CreateAlert won't route
- **H5:** `DEPTH_MANIFEST` has empty `listensFor` — ViewDepth won't route
- **H6:** `ExchangeWorkerHost` delivers ALL ticks to ALL subscribers regardless of symbol — no symbol filtering
- **H7:** `enrichment-worker.ts` uses untyped `response.json()` with no validation — silent data corruption risk
- **H8:** `aggregation-worker.ts` starts timers at module load, before `configure` message
- **H9:** `SeriesRenderer.render()` options is `Record<string, unknown>` — untyped

## MEDIUM (18) — Key items:

- **fdc3:** `desk/index.ts` missing re-exports, `EventHandler` type too weak
- **data-layer:** `console.error` in production, credential manager stores keys in plaintext localStorage fallback, no adapter-level tests, O(n) symbol scan on every tick, `StaleDataMonitor` mutates via `Object.assign`
- **chart-engine:** `DataStore(0)` created every frame, no integration tests, `getVisibleRange()` called twice per render
- **core:** Wildcard barrel exports risk namespace collisions
- **drawing-tools:** Wrong `DESK_APP_ID`, errors swallowed in `scheduleSave`, test coverage only for framework + trend tools
- **ui-components:** `fontWeight` double-cast, module-load side effects

**How to apply:** Fix in priority order during Wave 3. C1 (context types) and H6 (symbol filtering) are the most impactful. H3/H4/H5 (manifest listensFor) overlap with Wave 1 manifest findings.
