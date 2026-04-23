---
name: tradesurface project status
description: Current phase and status — Phases 0-12 complete, Phases 13-20 planned with full spec docs, ready for implementation
type: project
---

Project "tradesurface" — Multi-asset charting platform targeting crypto first, deployed as 8 FDC3 apps on Desk (Rust/Tauri FDC3 2.2 Desktop Agent).

## Current State (2026-03-12)
Phases 0-12 complete (Phase 11 deferred). 1,885 tests passing. All apps running on mock data.
Next: Phase 13 (Production Exchange Adapters) — begins the real-data implementation arc.

## Codebase
- Nx monorepo: 17 projects at `packages/` and `apps/`
- 8 apps: feeds, chart, watchlist, depth, analytics, screener, alerts, editor
- All apps scaffolded with Jotai/Zustand + FDC3 integration stubs + mock data
- Last commit: `2aae6aa` (Phase 12)

## Remaining Phases (13-20)
- Phase 13: Production Exchange Adapters (Web Workers, circuit breakers)
- Phase 14: Data Normalization & Aggregation (VWAP, DQS, symbol mapping)
- Phase 15: FDC3 Data Distribution (channel broadcasting, MessagePack, private channels)
- Phase 16: Feeds App Production UI (progressive disclosure levels 0-3)
- Phase 17: DEX + DeFi + Derivatives Data (GeckoTerminal, Coinglass, DefiLlama, The Graph)
- Phase 18: App Production Wiring (all 8 apps on real data)
- Phase 19: Cross-App Data Availability (every metric everywhere — no silos)
- Phase 20: Production Hardening (performance, resilience, E2E, a11y audit)

## Spec Documents
| Spec | Path |
|---|---|
| Master Execution Plan | `specs/MASTER-EXECUTION-PLAN.md` |
| Data Layer Spec | `specs/SPEC-DATA-LAYER.md` |
| App Design Specs | `specs/SPEC-APP-DESIGNS.md` |
| FDC3 Integration Spec | `specs/SPEC-FDC3-INTEGRATION.md` |
| Quality & Performance Spec | `specs/SPEC-QUALITY-PERFORMANCE.md` |
| Market Data Strategy | `research/market-data-onboarding-strategy.md` |
| Multi-Asset Strategy | `research/multi-asset-expansion-strategy.md` |

## Key ADRs
- ADR 0001: Tech stack (React 19, Canvas2D/WebGL, Vite, pnpm+Nx, Jotai+Zustand)
- ADR 0002: Monorepo structure (10 packages + 8 apps + 1 WASM plugin)
- ADR 0003: FDC3 deployment (standalone windows + workspace templates)
- ADR 0004: Price feed architecture (centralized feeds app + FDC3 distribution)
