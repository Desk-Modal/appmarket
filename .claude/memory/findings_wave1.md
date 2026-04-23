---
name: Wave 1 Findings — Build & Manifest Gaps
description: Detailed findings from Wave 1 of recursive review — build failure and 18 manifest/deployment gaps
type: project
---

## Build Status
- Type-check: PASS (all 15 projects)
- Unit tests: PASS (all 15 projects, ~2000+ tests)
- Production build: FAIL — `ui-components` EPERM on `dist/analysis` mkdir (permission/file lock issue, not a code error)
- All 8 app builds blocked by ui-components failure

## Manifest Gaps (18 findings)

### Critical (breaks FDC3 routing):
1. Code manifests (`manifests.ts`) have empty `listensFor` for feeds, depth, alerts — intents won't route
2. `plugin.toml` severely stale — missing most Phase 17-20 intents/channels. **This is what DeskModal actually loads.**
3. `CreateAlert` context type mismatch — appd.json says `fdc3.instrument`, spec says `tradesurface.alert`

### High (limits functionality):
4. Chart missing raises: `ViewDepth`, `CreateAlert`, `CreateOrder`
5. Watchlist missing raises: `ViewDepth`, `ViewFunding`, `ViewOnChain`
6. Depth/Analytics/Alerts missing raises of `ViewChart`
7. Chart/Watchlist/Screener missing appChannel subscriptions
8. Analytics/Alerts missing user channel `fdc3.instrument` listensFor
9. Chart missing user channel broadcasts (`fdc3.chart`, `tradesurface.chartState`)

### Medium (inconsistencies):
10. Three URL bases: `{{BASE_URL}}`, `app.tradesurface.io`, `apps.tradesurface.com`
11. Editor: `tradesurface.indicator` vs spec's `tradesurface.indicatorResult`
12. Feeds defi: `defiProtocol` vs spec's `onChainMetric`
13. Feeds trades: `tradesurface.trade` vs spec's `fdc3.trade`
14. Tier/launchOrder values differ between appd.json and spec
15. Stale CHANNELS constant in spec

### Low (structural):
16. TOML workspaces use absolute pixels vs JSON's relative coordinates
17. Two workspace definition systems (TOML + JSON) need reconciliation
18. Missing trailing slashes in URLs

**How to apply:** Fix in priority order during Wave 3. Critical items first — plugin.toml and code manifests are the biggest blockers. The appd.json is the canonical manifest source; reconcile others to match it.
