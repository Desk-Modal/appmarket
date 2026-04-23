---
name: DeskModal scope boundary — 3-tier architecture
description: DeskModal is ONLY an FDC3 desktop agent — no trading, no finance, no FDC3 spec ownership. Capabilities live in shared frameworks that plugins and services leverage.
type: feedback
originSessionId: 52daa5a6-91e7-4fa7-990b-26a30d0b15b5
---
**DeskModal is ONLY an FDC3 desktop agent.** Nothing more. No trading logic. No financial knowledge. No market data types. Not even FDC3 spec constants.

**3-tier architecture:**

```
+-------------------------------------------------------+
|  DeskModal (bare FDC3 desktop agent)                  |
|  Knows: how to route FDC3 contexts, regex-validate    |
|         type names, manage windows, install plugins   |
|  Doesn't know: what fdc3.instrument means, what       |
|         trading is, what a price tick looks like      |
+---------------------------+---------------------------+
                            ↓ depends on
+---------------------------+---------------------------+
|  Shared frameworks (standalone repos, all reusable)   |
|  - DeskModal-FDC3       : FDC3 2.2 spec types         |
|                           (22 context constants,      |
|                           Context struct, regex,      |
|                           intent/channel conventions) |
|  - deskmodal-service-sdk: generic service-plugin SDK  |
|                           (identity, storage, IPC,    |
|                           intents, channels)          |
|  - tradesurface-contracts: trading/market-data types  |
|                           (Quote, Order, Position,    |
|                           Fill, etc.)                 |
|  - future: healthcare-contracts, logistics-contracts  |
+---------------------------+---------------------------+
                            ↓ leveraged by
+---------------------------+---------------------------+
|  Plugins (apps) + Services (backgrounds)              |
|  - TradeSurface Paper-trading (service)               |
|  - Price Feed (service)                               |
|  - TradeSurface Chart / Watchlist / Depth (apps)      |
|  - (future) healthcare charting app                   |
|  - (future) logistics tracker service                 |
+-------------------------------------------------------+
```

**Why:**
- DeskModal can ship to any vertical (finance, healthcare, logistics, collab). Baking any one domain into it creates wrong abstractions + limits reuse.
- FDC3 is a standard DeskModal implements, not a standard DeskModal owns. The spec types belong in a standalone repo all products can share.
- A shared framework layer lets multiple product families (TradeSurface, future healthcare suite, etc.) depend on the same FDC3 layer without pulling DeskModal's whole monorepo.
- Plugins/services must never re-implement what a shared framework already provides — no private copies of `PriceTick` or FDC3 Context.

**How to apply:**
- Any code that names a trading concept (bid/ask/OHLCV/fill/position/order) belongs in `tradesurface-contracts` or a downstream plugin, NEVER in DeskModal crates.
- Any code that names an FDC3 2.2 spec concept (context type constant, Context struct, intent name, channel type) belongs in `DeskModal-FDC3`, NEVER in DeskModal itself.
- DeskModal Rust crates see context types as opaque strings matching `^[a-z]+(\.[A-Za-z]+)*$`.
- Plugins/services depend on shared framework crates via git-rev or versioned release, NEVER on DeskModal's internal crate graph.
- When reviewing a proposed new crate or module inside DeskModal, ask: "could a healthcare agent ship without this?" If no, it's in the wrong tier.
- Shared UI components must be domain-free (Button, Dialog, Panel) — never financial display components (WatchlistRow, PriceDisplay).
- The `usePreloadedContext` hook stays generic `<T>` — tradesurface defines its own shape.

**Repo layout (target state):**
- `D:\celer\desk\` — DeskModal FDC3 desktop agent (Rust/Tauri)
- `D:\code\repo-extraction\DeskModal-FDC3\` — FDC3 2.2 spec types + validators + conventions
- `D:\code\repo-extraction\service-sdk\` — generic service plugin SDK (identity, IPC, storage, channels)
- `D:\code\repo-extraction\tradesurface-contracts\` — trading + market data context types, intent payloads, channel constants
- `D:\code\repo-extraction\paper-trading\` — "TradeSurface Paper-trading" service (rebrand the display name)
- `D:\code\repo-extraction\price-feed-service\` — market data producer
- `D:\code\tradesurface\` — TradeSurface monorepo (React/TypeScript FDC3 apps)

**Historical:**
- Until 2026-04-11, DeskModal carried a built-in `deskmodal-paper-trading` crate + `deskmodal-ems` crate + `commands/paper_trading.rs` Tauri wrapper + `Toolbar.tsx` paper indicator + `App.tsx` BUILTIN_APPS injection. Agent #78 removed all of it in commits 41b2a95/81ff39d/ead5c27. `deskmodal-ems` was correctly removed as trading-specific alongside paper-trading — it hard-depended on OrderType/TimeInForce/PriceTick/Currency from paper-trading.
- `deskmodal-types::context.rs` still holds 22 FDC3 2.2 standard context type name constants (fdc3.instrument, fdc3.position, fdc3.portfolio, fdc3.valuation, fdc3.currency, etc.). These are FDC3 spec names, not trading semantics. Per refined scope rule they should move to `DeskModal-FDC3` repo. Extraction queued as a task.
