---
name: Two-tier icon system for DeskModal AppMarket
description: Icon architecture decision — colored market tier vs glass translucent toolbar tier — and the end-to-end plumbing
type: project
originSessionId: 52daa5a6-91e7-4fa7-990b-26a30d0b15b5
---
DeskModal icons are delivered in two tiers, published on the public CDN at `https://raw.githubusercontent.com/Desk-Modal/appmarket/main/icons/`:

- **Market tier** (`<id>-market.svg`): fully colored product art with dark gradient base + radial inner glow + directional green/red where semantically earned + `tradesurface.*` family marker dot. Rendered on AppStore cards/hero at 48–128px.
- **Glass toolbar tier** (`<id>-toolbar.svg`): translucent tile with NO base fill, subtle `rgba(120,150,255,0.18)` border, monochrome `#60a5fa` marks at ~0.9 opacity. Designed to sit on top of DeskModal's frosted-glass (`backdrop-filter: blur(14px) saturate(180%)`) panels. Rendered on the DeskModal native LaunchBar at 16–24px.

**Why:** DeskModal's entire GUI uses glassmorphism. Opaque toolbar icons would fight the frosted surface. Translucent glass tiles blend in as part of the frame. Market cards are their own product surface (a store), so they keep the full color treatment.

**How to apply:**
- Catalog schema (aggregated by `appmarket/scripts/aggregate.py`): each entry carries `icon: { market, toolbar }` + a legacy flat `icon_url` alias pointing at the market variant.
- Rust runtime (`deskmodal_app_directory::market::upsert_catalog_app_definition`) maps `icon.toolbar` → `AppDefinition.icons[0].src`, so installed plugins get the glass icon on the LaunchBar automatically.
- Frontend LaunchBar (`apps/deskmodal-agent/src/components/LaunchBar.tsx`) renders `<img src={app.icon}>` — no code change needed to flip consumers.
- Marketplace UI (`AppStore.tsx`) renders from `appstore_search_unified` which must surface the market URL separately, via an `icon_market_url` field or equivalent.

**Design spec:** `appmarket/icons/_SYSTEM.md` — 10 principles, shared skeleton, color tokens, two-tier pattern, 16px legibility rules, 13-point review checklist. **Single source of truth — any icon deviating is a defect.**

**Known tech debt (P2):** `LaunchBar.tsx:62-68` has hardcoded `APP_ICONS` Record keyed by legacy `deskmodal.*` IDs (no hyphen). New catalog uses `desk-modal.*` (with hyphen). The fallback Record is dead code for all new catalog entries — can be removed once the catalog is verified to cover every app we care about.

**Review cadence:** every icon change goes through UX Design Lead + Trading UX Architect + Trading SME adversarial review before push. First round produced a NO-GO verdict; round-2 fixes are in progress (task #77) to address DOM-inversion on depth, pill-silhouette on chart glass, no-direction on trading glass, plus metaphor redesigns for paper-trading and price-feed-service.
