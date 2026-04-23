---
name: Always package price-feed with tradesurface plugin
description: Price-feed runs out-of-process by default; binary built by default, skip via SKIP_PRICE_FEED_BINARY=1
type: feedback
---

Price-feed runs out-of-process by default. Binary built by default; skip via SKIP_PRICE_FEED_BINARY=1. In-process mode available when cdylib loader ships.

**Why:** The price-feed service is declared in plugin.toml as `tradesurface.price-feed` with `hosting = "outofprocess"` and `auto_start = true`. If the binary is missing from `services/tradesurface-price-feed[.exe]`, DeskModal will fail to launch the service at startup. The feeds app is a pure FDC3 client that depends entirely on the price-feed service for exchange connectivity.

**How to apply:** When building/deploying the tradesurface plugin (via `scripts/bundle-plugin.sh` or manually), always include:
1. `cargo build --release -p tradesurface-price-feed` (skip with `SKIP_PRICE_FEED_BINARY=1`)
2. Copy binary to `$DEPLOY_DIR/services/tradesurface-price-feed[.exe]`
3. The entry_point in plugin.toml must match: `services/tradesurface-price-feed`
4. Deploy path is `~/.deskmodal/plugins/tradesurface/` (NOT `~/.desk/plugins/`)
5. Validate bundle with `scripts/validate-manifest.sh`
