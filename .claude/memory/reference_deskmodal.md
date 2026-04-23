---
name: DeskModal codebase reference
description: Location, structure, and coordination protocol for the DeskModal FDC3 desktop agent repo
type: reference
---

**DeskModal repo**: `D:\celer\desk`

**Tech**: Rust 2021 + Tauri 2 + React 18 + TypeScript 5. 25 crates in `crates/`, Tauri app in `apps/deskmodal-agent/`.

**Key crates for tradesurface integration**:
- `deskmodal-core` — FDC3 engine (DeskModalAgent, channels, intents, listeners)
- `deskmodal-ipc` — 3-tier IPC (Hot/Warm/Cold)
- `deskmodal-bridge` — DAB server, WCP server
- `deskmodal-app-directory` — FDC3 App Directory with remote sync
- `deskmodal-app-lifecycle` — Supervisor tree, restart policies
- `deskmodal-types` — FDC3 type definitions

**Cross-session coordination**: `~/.claude/coordination/` with PROTOCOL.md. Requests go in `tradesurface-to-deskmodal/`, responses come back in `deskmodal-to-tradesurface/`.

**DeskModal CLAUDE.md**: Has its own memory system at `D:\celer\desk\.claude\memory/` with 17 files.
