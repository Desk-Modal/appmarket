---
description: "Run tests scoped to what changed. Supports platform crates, individual apps, services, or full suite."
user-invocable: true
---

# /test [scope]

Run tests for the specified scope. Defaults to affected-only.

## Scopes

| Scope | What it tests | Command |
|-------|--------------|---------|
| `/test` | Auto-detect affected tests | See detection below |
| `/test platform` | All platform Rust lib tests | `cd platform && cargo test --workspace --lib` |
| `/test crate <name>` | Single crate tests | `cd platform && cargo test -p <name>` |
| `/test app <name>` | Single web app tests | `cd plugins/tradesurface && pnpm nx run @deskmodal/app-<name>:test` |
| `/test apps` | All web app tests | `cd plugins/tradesurface && pnpm nx run-many -t test --all` |
| `/test service <name>` | Service tests | `cd plugins/tradesurface/services/<name> && cargo test` |
| `/test affected` | Only tests for changed code | Auto git-diff scoped |
| `/test full` | Everything — platform + apps + services + CDP | Full CI suite |
| `/test cdp` | CDP validation of running DeskModal | `python scripts/cdp-test-runner.py` |

## Auto-Detection (default)

1. **Graph-first** — `detect_changes(project=<platform-project>  # resolve via list_projects())` to see which symbols are affected and their risk level. Use `trace_path` to identify downstream test targets.
2. Run `git diff --name-only HEAD` to find changed files.
2. Map changed files to test scope:
   - `platform/crates/<name>/*` → `cargo test -p <name>`
   - `platform/apps/deskmodal-agent/*` → `cargo test -p deskmodal-agent`
   - `plugins/tradesurface/apps/<name>/*` → `pnpm nx run @deskmodal/app-<name>:test`
   - `plugins/tradesurface/packages/<name>/*` → `pnpm nx run @deskmodal/<name>:test`
   - `plugins/tradesurface/services/<name>/*` → `cd services/<name> && cargo test`
3. Run ONLY the affected tests — never the full suite unless asked.

## Commands

### Platform
```bash
cd platform

# Single crate:
cargo test -p deskmodal-core --lib

# Workspace (all platform crates):
cargo test --workspace --lib

# With output:
cargo test -p deskmodal-core -- --nocapture
```

### Web Apps
```bash
cd plugins/tradesurface

# Single app:
pnpm nx run @deskmodal/app-feeds:test

# Affected only:
pnpm nx affected -t test

# All (with heap size for large suites):
NODE_OPTIONS=--max-old-space-size=4096 pnpm nx run-many -t test --all
```

### Services
```bash
cd plugins/tradesurface/services/price-feed
cargo test
```

### CDP (End-to-End)
```bash
# Requires DeskModal running with --remote-debugging-port=9222
python scripts/cdp-test-runner.py
python scripts/cdp-test-runner.py --app chart  # Single app
```

## Rules
- NEVER run full test suite by default — use affected detection
- Platform Rust tests use `pool: 'forks'` in vitest configs (Windows tinypool fix)
- `NODE_OPTIONS=--max-old-space-size=4096` for large TS test suites
- CDP tests verify user-facing outcomes, not implementation details
