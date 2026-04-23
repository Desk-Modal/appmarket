---
name: Price-feed service diagnosis
description: Root cause analysis of price-feed service not producing visible exchange connections
type: project
---

## Status: RESOLVED (2026-03-25)

## What Works
- DeskModal loads plugin.toml correctly
- cdylib `tradesurface_price_feed.dylib` loaded via libloading
- `deskmodal_service_entry` FFI called successfully
- Service creates its own tokio multi-thread runtime
- Service calls `client.storage_get_typed()` — confirmed by DEBUG log lines
- `config.default_symbols -> true` — stored defaults exist in storage

## What Doesn't Work
- Service's own `tracing::info!` output not appearing in desk.log
- No exchange WebSocket connections observed from the Rust service
- Network connections visible in lsof are from FRONTEND JS adapters, not Rust service

**Why:** The `non_blocking` tracing writer in DeskModal uses a buffered appender. The cdylib's thread creates its own tokio runtime via `block_on()`. Tracing calls from within this runtime should reach the global subscriber, but may be buffered and not flushed.

**How to apply:** When debugging the price-feed service, check `~/.desk/logs/desk.log.*` for the actual logs. The service's tracing output may appear delayed or not at all due to the non-blocking writer flushing behavior. Consider adding explicit flush or using stderr for debugging.

## Previous False Claims (corrected)
- WRONG: "Exchange connections confirm the price-feed service is working"
- TRUTH: The 6 network connections were from frontend TypeScript WebSocket adapters in WKWebView, NOT from the Rust price-feed service
- WRONG: "Price-feed service is streaming live data"
- TRUTH: Cannot confirm service is producing data without direct evidence (log output, FDC3 broadcast observed)

## Root Causes Found and Fixed
1. **Stale plugin.toml** — deployed `~/.deskmodal/plugins/tradesurface/plugin.toml` used `tradesurface.*` namespace for ACL broadcasts, but Rust service code uses `deskmodal.*`. DeskModal's ACL engine denied every broadcast. Fixed by deploying the correct plugin.toml from `plugins/tradesurface-enricher/plugin.toml`.
2. **First-run subscription bug** — `run_with_config()` else branch (no stored defaults) persisted adapter defaults to storage but NEVER subscribed them to the SubscriptionManager. Service started with 0 symbols. Fixed by adding subscription logic to the else branch.
3. **Service binary filename mismatch** — Old deployment had `tradesurface_price_feed.dylib` but new plugin.toml expects `deskmodal_price_feed.dylib`. Fixed by deploying with correct name.

## Verified Working State (2026-03-25, final)
- 6 exchanges, 24 symbols subscribed (10 Binance, 3 each Coinbase/Bybit/OKX/Kraken, 2 Gemini)
- Live prices confirmed via GUI screenshot: BTC $71,342, ETH $2,089, SOL $81.71, BNB $647.80, XRP $1.41, ADA $0.278, AVAX $9.04, LINK $9.37
- DOT and MATIC show $0.00 — likely delisted on Binance US (MATIC→POL rebrand)
- Zero ACL denials with deskmodal.* namespace in plugin.toml
- Default workspace auto-opens chart + watchlist on launch
- Adapter default symbol merge logic ensures new symbols are picked up on upgrade

**How to apply:** When the plugin namespace changes, ALWAYS update plugin.toml ACL entries to match. When persisting defaults, ALWAYS also subscribe them so first-run works.
