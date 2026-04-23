---
name: Wave 2 Findings — App Audit (8 apps)
description: Deep code audit of all 8 tradesurface apps — 2 critical, 10 high, 26 medium, 3 low findings
type: project
---

## CRITICAL (2)

**CC1 — Entire FDC3 data pipeline broken:** `FeedManager.initFdc3(agent)` is defined but NEVER CALLED anywhere. FDC3Broadcaster never starts, IntentHandlers never registered. Zero data flows between apps. ALL consumer apps (chart, watchlist, depth, analytics, screener, alerts) receive nothing.

**C1 — FDC3 Broadcaster/IntentHandlers never initialized:** Root cause of CC1. The `initFdc3()` call is missing from feeds `App.tsx`.

## HIGH (10)

- **CH1:** No ErrorBoundary in ANY of the 8 apps — uncaught render error = blank screen
- **CH2:** Context type mismatches between broadcaster and consumers:
  - Broadcaster sends `tradesurface.orderbook`, depth listens for `tradesurface.aggregatedOrderbook`
  - Broadcaster sends `fdc3.trade`, depth listens for `tradesurface.trade`
  - Broadcaster sends `tradesurface.aggregatedPrice`, live candle listens for `fdc3.instrument`
- **H2:** Chart `onScreenshot` is a no-op
- **H3:** Chart `handleDeleteSelected` is a no-op
- **H5:** Watchlist 5 critical action handlers are no-ops (addAlert, viewDepth, removeSymbol, addSymbol, search)
- **H6:** Depth `useDepthIntent` hook defined but never called in App.tsx
- **H7:** Analytics ExchangeFlowPanel receives all hardcoded zeros
- **H8:** Editor has static scaffold/placeholder data (Phase 11 deferred, violates production-only rule)

## MEDIUM (26) — Key items:

- Feeds: `activeSymbols` always 0, `subscribedPairs` always empty, `circuitBreakerState` always 'closed'
- Chart: `visibleRange` hardcoded 24h, `currentTimeDisplay` frozen at mount, `activeToolValue` always 'crosshair'
- Watchlist: no `ViewChart` intent on double-click, missing `ViewFunding`/`ViewOnChain`
- Depth: wrong context types for orderbook/trades, no keyboard shortcuts, `handlePriceClick` is stub
- Analytics: `activePanel` from intents unused, `previousValue`/`changePercent` always 0
- Screener: `previousPrice` always 0, no keyboard row navigation
- Alerts: `handleAlertEdit` ignores alert data, `handleAcknowledge`/`handleViewAlert` no-ops, conditions hard-mapped to 'price-above'
- Editor: Save/Run/Backtest non-functional, plain textarea instead of code editor

## Cross-app:
- `deriveAssets()` duplicated in 3 files
- `AgentWithIntentListener` interface duplicated in 4 files

**How to apply:** Fix in priority order during Wave 3. CC1 is the single highest priority — without it, the entire plugin is non-functional for data distribution.
