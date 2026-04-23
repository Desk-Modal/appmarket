---
name: In-process service hosting
description: In-process infrastructure complete, deployment is out-of-process until cdylib loader ships
type: feedback
---

In-process service hosting infrastructure is complete (Phases 3-5). Deployment mode is out-of-process (`hosting = "outofprocess"` in plugin.toml). Switch to in-process when DeskModal cdylib loader ships.

**Why:** The cdylib dynamic loading mechanism in DeskModal is not yet implemented. Until it ships, services must run as separate binaries managed by DeskModal's service supervisor. The price-feed crate is already structured as a library (`rlib`) with a standalone binary at `src/bin/standalone.rs`, so switching to in-process requires only changing `hosting` and `entry_point` in plugin.toml.

**How to apply:** When the cdylib loader ships in DeskModal:
1. Change `hosting = "outofprocess"` to `hosting = "inprocess"` in plugin.toml
2. Change `entry_point` to `"tradesurface_price_feed"` (the library crate name)
3. Build price-feed as `cdylib` crate type (add to Cargo.toml `crate-type`)
4. The standalone binary can be removed or kept for debugging
