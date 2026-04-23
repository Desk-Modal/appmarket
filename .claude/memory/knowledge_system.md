---
name: knowledge management system architecture
description: How the Tradesurface knowledge system works across sessions, agents, and machines — read this on every session start
type: reference
---

## Knowledge Layers (auto-loaded per session)

1. **CLAUDE.md** (root) — Project overview, tech stack, FDC3 architecture, 8 apps, build commands, monorepo structure, code conventions, performance targets. Loaded FIRST on every session.

2. **.claude/rules/** — 8 domain-specific rule files, lazy-loaded by file path:
   - typescript.md, react.md, chart-engine.md, fdc3.md, testing.md, naming.md, production-code.md, monorepo.md

3. **.claude/settings.json** — Auto-permissions for dev commands, Prettier hook on file edits, context restoration hook on compaction.

4. **.claude/skills/** — Custom slash commands:
   - /verify — validate package against spec and standards
   - /scaffold-package — create new package/app with all required files
   - /new-indicator — create indicator following exact patterns
   - /new-exchange-adapter — create exchange adapter with full interface

5. **Memory files** (this directory) — Cross-session knowledge: project status, user preferences, engineering standards, framework decisions.

## Key Documents (read when needed, not every session)

- specs/SPEC-001-phased-implementation.md — 10-phase roadmap
- docs/decisions/0001-tech-stack.md — React 19, Canvas 2D/WebGL, Vite, Nx
- docs/decisions/0002-monorepo-structure.md — 10 packages + 8 apps + 1 WASM plugin
- docs/decisions/0003-fdc3-deployment.md — Hosting model, workspace templates, progressive UX
- docs/decisions/0004-price-feed-architecture.md — Centralized feeds app, FDC3 distribution
- research/desk-capability-evolution.md — Desk evolution proposals (for separate Desk session)
- research/desk-fdc3-integration-strategy.md — Full FDC3 integration design

## Multi-Agent Coordination

- Each agent scopes to one package at a time; Claude picks the per-dispatch execution-isolation strategy
- @tradesurface/core changes require checking all dependents
- Public API changes: update interface first, then implement
- Run `pnpm nx affected -t type-check` after core changes
- Nx dependency graph prevents invalid cross-package references

## Cross-Machine Portability

Everything in `.claude/` is committed to git. When the repo is cloned to another machine, all rules, settings, skills, and MCP config auto-load. Memory files are machine-local but project context is in CLAUDE.md and .claude/.
