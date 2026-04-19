---
description: "Build individual apps, services, crates, plugins, platform, or full bundle. Incremental — only changed components rebuild."
user-invocable: true
---

# /build [target]

Build DeskModal components. Only rebuilds what changed.

## Targets

| Target | What it builds | Location |
|--------|---------------|----------|
| `/build platform` | DeskModal agent binary | `platform/` |
| `/build crate <name>` | Single platform crate | `platform/crates/<name>` |
| `/build app <name>` | Single web app (chart, feeds, etc.) | `plugins/tradesurface/apps/<name>` |
| `/build service <name>` | Single native service DLL/dylib | `plugins/tradesurface/services/<name>` |
| `/build plugin` | All web apps + services for TradeSurface | `plugins/tradesurface/` |
| `/build bundle` | Full dist/ — platform + plugin + signed | `dist/` |
| `/build release` | Optimized dist/ for deployment | `dist/` (release profile) |
| `/build affected` | Only changed packages/crates | Automatic scope detection |

## Execution Steps

1. **Parse target** from user request. Default to smallest scope.
2. **Graph-first scope detection** — use codebase-memory-mcp to understand impact:
   - `detect_changes(project=<platform-project>  # resolve via list_projects())` → which symbols/crates changed
   - `get_architecture(project=<platform-project>  # resolve via list_projects())` → crate dependency overview
   - This avoids rebuilding crates that aren't affected by the change.
3. **Detect changes** — `git diff --name-only HEAD` to determine what changed.
4. **Map changes to build scope:**
   - `platform/crates/*` changed → `cargo check -p <crate>` (Cargo handles dep chain)
   - `plugins/tradesurface/apps/*` changed → `pnpm nx affected -t build`
   - `plugins/tradesurface/services/*` changed → build only that service
   - Multiple areas changed → build each independently (parallel when possible)
4. **Build** using the commands below.
5. **Verify** — run the matching quality gate.
6. **Report** — what built, binary sizes, warnings.

## Commands

### Platform (Rust)
```bash
cd platform

# Single crate check (fastest — ~2s if cached):
cargo check -p deskmodal-core

# Full agent binary (debug):
cargo build -p deskmodal-agent

# Full agent binary (release — slow, use for dist):
cargo build -p deskmodal-agent --release

# Only recompiles crates with changed source files.
# Cargo tracks file timestamps — no manual invalidation needed.
```

### Web Apps (TypeScript)
```bash
cd plugins/tradesurface

# Single app:
pnpm nx run @deskmodal/app-chart:build

# Only affected apps (based on Nx dependency graph):
pnpm nx affected -t build

# All apps (parallel):
pnpm nx run-many -t build --all --parallel=4
```

### Services (Rust — independent builds)
```bash
# Each service is its own Cargo project. Build independently:
cd plugins/tradesurface/services/price-feed
cargo build --lib

# Sign after building:
./scripts/sign-service.sh price-feed
```

### Full Distribution Bundle
```bash
# Debug bundle (fast):
./scripts/build-dist.sh --sign

# Release bundle (optimized):
./scripts/build-dist.sh --release --sign

# Launch from dist/:
./scripts/launch.sh
```

dist/ IS the runtime — no deploy/copy step needed.

## Incremental Build Rules

- **Cargo** automatically tracks source file changes per crate. `cargo build -p X` only recompiles X and its changed transitive deps.
- **Nx** tracks TypeScript package dependencies. `pnpm nx affected -t build` uses git diff to determine which apps need rebuilding.
- **Services** are independent Cargo projects — building one never touches another.
- **NEVER** run `cargo build --workspace` or `pnpm nx run-many -t build --all` unless explicitly asked for a full build. Always prefer affected/targeted builds.

## Cross-Platform

build-dist.sh detects the host OS/arch and emits the platform-appropriate
dist layout — one flat tree per OS, with the binary at `dist/` root.

| Platform | Binary location | Service extension |
|----------|-----------------|-------------------|
| macOS (arm64 + x64) | `dist/DeskModal.app/Contents/MacOS/DeskModal` | `.dylib` |
| Linux (x64 + arm64) | `dist/DeskModal` | `.so` |
| Windows (x64 + arm64) | `dist/DeskModal.exe` | `.dll` |

## Quality Gates (post-build)
```bash
cargo fmt --all -- --check                    # Format
cargo clippy --workspace -- -D warnings       # Lint
pnpm nx affected -t typecheck                 # TypeScript
grep -rn 'Mutex\|RwLock' --include='*.rs'     # Lock audit → 0 matches
```
