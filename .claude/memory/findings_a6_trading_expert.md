---
name: A6 Trading Expert Review Findings
description: Professional trader review of all 8 apps — P0/P1/P2 feature gaps for future phases, rated 5/10 for active trading use
type: project
---

## A6 Trading Expert Review (2026-03-13)

Platform rated **5/10 for professional trading use** — excellent for analysis/research, missing execution capabilities. All current features verified working correctly.

**Why:** Expert review during recursive GUI test/fix/verify cycle. Findings are future roadmap items, not defects in current implementation.

**How to apply:** Use these findings to prioritize future phases. P0 items block revenue/active trading use. P1 items cause major friction for daily traders.

---

### P0 — BLOCKS TRADING (future phases)

1. **No Order Entry Integration** (~200hrs)
   - `apps/depth/src/App.tsx:70` has placeholder comment
   - Cannot place limit/market orders from DOM or chart
   - Need: OrderEntry intent + UI + exchange adapter wiring

2. **No Multi-Chart Layout** (~150hrs)
   - `apps/chart/src/App.tsx` mounts single ChartSurface
   - Cannot compare BTC vs ETH or 1D vs 4H side-by-side
   - Need: SplitPane layout manager + symbol/timeframe sync

3. **No Position Management** (~250hrs)
   - Missing entirely — no P&L tracking, entry/exit markers on chart
   - Need: PositionManager store, P&L calculator, chart overlay

4. **Script Editor Non-Functional** (~200hrs)
   - `apps/editor/src/App.tsx:216-218` — Run/Backtest callbacks empty
   - SAMPLE_SCRIPT and BACKTEST_RESULTS are hardcoded mock data
   - Need: JavaScript interpreter/sandbox + indicator API

5. **Screener: No Technical Filters**
   - `apps/screener/src/screener-constants.ts` — only Volume + Change%
   - Need: RSI, MACD, volume MA filters

6. **Screener: No Watchlist Integration**
   - Cannot add screener results to watchlist
   - Need: Multi-select + "Add to Watchlist" action

7. **Watchlist: No Column Customization UI**
   - `App.tsx:113` has handler but no UI to add/remove columns
   - Need: ColumnCustomizer dialog

8. **Watchlist: No Per-Row Action Menu**
   - Has `onAddAlert`, `onViewDepth`, `onRemoveSymbol` but no visible buttons
   - Need: Three-dot menu or context menu

### P1 — MAJOR FRICTION

1. **No Alert Notifications Beyond In-App** (~120hrs)
   - Toast-only; no email/SMS/webhook/Discord
   - Need: NotificationChannel system

2. **No Alert Sound**
   - No audio option for triggered alerts
   - Critical for scalpers

3. **No Alert Frequency Control**
   - `frequency: 'once'` hardcoded; no repeat/continuous
   - Need: once, repeat-5m, repeat-1h, continuous

4. **No Commission/Fee Configuration** (~80hrs)
   - Nowhere to input per-exchange rates
   - Need: FeeConfig per exchange, apply to P&L

5. **No Order Book Impact Calculator** (~60hrs)
   - Cannot estimate "sell 10 BTC → avg exit price?"
   - Need: SizeImpactOverlay on depth

6. **No Crosshair Spread Indicator**
   - SpreadDisplay exists but not wired to chart crosshair

7. **Feeds: No Price Tick Display**
   - Health monitoring works but no actual price tickers in feeds app

8. **Analytics: No Funding Rate Historical Chart**
   - Table-only; need line chart over time

9. **Analytics: Liquidation Heatmap Not Real-Time**
   - Uses mock data; no live liquidation streaming

10. **Analytics: No Basis/Contango Indicator**
    - Cannot calculate perp-spot basis for carry trades

11. **Analytics: Long/Short Ratio Not Symbol-Specific**
    - Shows aggregate only; need per-symbol breakdown

12. **Depth: No Large Order Detection / Whale Alerts**
    - No threshold for "significant" orders in depth

13. **Depth: No Time-Weighted Spread Tracking**
    - Snapshot only; no historical spread sparkline

14. **Editor: No Script Language Specification**
    - No syntax highlighting, autocomplete, or defined language

15. **Editor: No Strategy Templates**
    - No Golden Cross, RSI Divergence, etc. starter scripts

### P2 — NICE TO HAVE

- Volume profile / market profile renderers (types exist, no impl)
- Alert creation from chart indicator pane (right-click → "Alert if RSI > 70")
- Cross-timeframe alert conditions
- Alert backtesting on historical data
- Screener: multi-period %change columns (1h, 4h, 1W, YTD)
- Screener: correlation/spread scanner
- Watchlist: multi-select + bulk actions
- Watchlist: market cap / dominance column
- Depth: order book imbalance meter (bid/ask ratio gauge)
- Depth: trade history exchange source indicator
- Editor: interactive backtest viewer (click trade → jump to chart)
- Editor: parameter sweep / optimization
- Editor: script versioning / save
- Analytics: liquidation cascade detector
- Analytics: exchange flow chart visualization

### Cross-Cutting Issues

- **Precision derivation scattered** — `derivePrecision()` in watchlist, depth, chart separately; should be in core utils
- **No persistence layer** — watchlist, alerts, charts don't persist to IndexedDB (lose config on refresh)
- **No rate limiting on FDC3 broadcasts** — chart broadcasts every tick, could spam other apps
- **Mock data in editor/analytics** — needs replacement with live data pipelines

### Estimated Total Effort for P0 Items
~800-1200 engineer-hours (3-4 person-months)
