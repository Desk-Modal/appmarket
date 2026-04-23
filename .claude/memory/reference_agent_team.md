---
name: Agent team configuration
description: 11 agent personas, 21 skills, 83 anti-patterns, quality gates — 3 spec files define the full team
type: reference
---

## Agent Team Configuration

Full design specs:
- `specs/AGENT-TEAM-DESIGN.md` (1,622 lines) — 9 engineering personas
- `specs/TRADING-UX-DESIGNER-PERSONA.md` (1,006 lines) — Trading UX Architect
- `specs/TRADING-SME-PERSONA.md` (831 lines) — Trading Systems SME

### 11 Agent Personas
1. Rust Systems Architect — DeskModal core, 26 crates, Tauri, in-process services
2. Frontend Architect — React 19, 8 apps, design system, Canvas/WebGL
3. FDC3 Protocol Engineer — FDC3 2.2, context/intents/channels, cross-repo
4. Security Engineer — ACL, DLP, audit chain, P0 fixes, WASM scoping
5. Build & Deploy Engineer — Nx, Cargo, incremental builds, plugin deployment
6. Quality Assurance Architect — wave audits, dead code, standards enforcement
7. Integration Architect — cross-repo coordination, plugin API surface
8. Data Pipeline Engineer — exchange adapters, WebSocket, market data
9. Documentation Engineer — specs, memory, CLAUDE.md, staleness detection
10. Trading UX Architect — TradingView-standard design, trader workflows, component specs
11. Trading Systems SME — feature authority, competitive intel, data quality, workflow validation

### 21 Skills (slash commands)
Engineering: /audit, /build, /deploy, /test, /review, /sync-docs, /new-service, /new-app, /verify-fdc3, /research, /handoff
UX Design: /design, /design-review, /design-system, /competitive-review, /trader-workflow
Trading SME: /feature-spec, /feature-review, /competitive-intel, /data-quality-review, /workflow-validation

### Configuration Files
- Tradesurface: 9 rules in `.claude/rules/`, 21 skills in `.claude/skills/`
- DeskModal: 5 rules in `.claude/rules/`, 5 skills in `.claude/skills/`
- Settings: `~/.claude/settings.json` — rust-analyzer, typescript-lsp, frontend-design plugins
- Both CLAUDE.md files updated with agent team, workflow, anti-patterns sections

### 5-Layer Knowledge Architecture
1. CLAUDE.md (auto-loaded every session)
2. .claude/rules/*.md (auto-loaded by file path matching)
3. Memory files (~/.claude/projects/*/memory/)
4. Spec documents (specs/)
5. Coordination files (~/.claude/coordination/)
