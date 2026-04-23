---
name: Marketplace Phase Status
description: Tracks marketplace, extraction, and GitHub distribution — ALL COMPLETE
type: project
originSessionId: 9c0cc298-5548-40c1-a81d-8f5d0c656762
---

## GitHub Distribution Migration: COMPLETE (2026-04-09)

All phases G0→G6 implemented. Master plan: `specs/PLAN-GITHUB-DISTRIBUTION.md`. ADR: `specs/ADR-GITHUB-DISTRIBUTION.md`.

| Phase | Status | Key Result |
|-------|--------|-----------|
| G0 | COMPLETE | deskmodal-plugin-tools crate (pack, checksums, sign), PlatformId — 52 tests |
| G1 | COMPLETE | GitHubPluginFetcher: auth, ETag, platform downloads, PluginReleaseInfo — 77 tests |
| G2 | COMPLETE | PluginInstaller: GitHub install pipeline, checksums, WASM fallback, trust levels — 99 tests |
| G3 | COMPLETE | Gateway: GitHubReleasePoller, platform endpoints, GitHub DB methods — typecheck clean |
| G4 | COMPLETE | CI: plugin-release.yml (native), plugin-release-web.yml, plugin-index.json |
| G5 | COMPLETE | AppStore: platform badges, installed platform, plugin sources, publisher info |
| G6 | COMPLETE | 15/15 adversarial review checks PASS, 228 total tests, npm deprecated |

### New Crate: deskmodal-plugin-tools
pack.rs (DmpkgBuilder), checksums.rs (SHA-256), commands/sign.rs (Ed25519), commands/pack.rs (CLI)

### Operational Next Steps
1. Create GitHub repos for extracted plugins (deskmodal/plugin-tradesurface-*)
2. Generate Ed25519 signing keypair, configure as repo secret
3. Push first tagged release to trigger CI
4. Verify Gateway polls and detects release
5. CDP verify AppStore shows GitHub-sourced plugins
## Monorepo Extraction: COMPLETE (2026-04-09)

All phases M0→M6 finished. Master plan: `specs/PLAN-MONOREPO-EXTRACTION.md`. Regression: `specs/M6-REGRESSION-REPORT.md`.

| Phase | Status | Key Result |
|-------|--------|-----------|
| M0 | COMPLETE | 4,180 tests baseline, dep graph, 2 missing deps fixed |
| M1 | COMPLETE | 7/7 shared libraries build standalone (3,846 tests) |
| M2 | COMPLETE | Feeds plugin pattern proven |
| M3 | COMPLETE | 7/7 plugins extracted (7 parallel agents) |
| M4 | COMPLETE | Meta-bundle + 4 workspace templates + WASM enricher |
| M5 | COMPLETE | Gateway seeded with 9 plugins, APIs verified |
| M6 | COMPLETE | 9/9 plugins deployed, DeskModal loads all, App Market shows 12 entries |

### Extracted Plugins (all at ~/.deskmodal/plugins/)
tradesurface-feeds, tradesurface-watchlist, tradesurface-screener, tradesurface-alerts, tradesurface-depth, tradesurface-analytics, tradesurface-chart, tradesurface-trading (3 apps), tradesurface-bundle (meta)

### Shared Libraries (all build standalone with npm pack)
@tradesurface/core (57kB), @deskmodal/fdc3 (63kB), @deskmodal/ui-components (990kB), @tradesurface/chart-engine (327kB), @tradesurface/indicators (270kB), @tradesurface/data-layer (397kB), @tradesurface/drawing-tools (254kB)

## Marketplace: COMPLETE (2026-04-08)
MP-1→MP-11 all done. Built-in App Market with Browse/Scripts/Installed/Settings tabs. Rust crate enhancements (NpmPluginFetcher, npm tarball installer, SIGNATURE verification, post-freeze registration, per-plugin consent). Agent bridge. Gateway at localhost:4100.

## Remaining Cleanup
- Remove legacy monolithic `deskmodal` plugin from `~/.deskmodal/plugins/`
- Register `@deskmodal-plugins` npm org for real publishing
- Wire CI/CD to actual GitHub repos
- Add plugin.toml to OptiScript plugin
