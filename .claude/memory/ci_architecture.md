---
name: CI architecture
description: How GitHub Actions CI is structured across all 7 repos, where the canonical docs and local scripts live, and what was already fixed in prior sessions
type: reference
originSessionId: 52daa5a6-91e7-4fa7-990b-26a30d0b15b5
---
CI across the DeskModal ecosystem is documented canonically at
`D:\celer\desk\docs\ci-architecture.md`. Load that file before starting
any CI-related work.

**Repos and workflows** (7 total):

| Repo | Path | Owner |
|---|---|---|
| deskmodal | `D:\celer\desk` | main pipeline — `.github/workflows/ci.yml` + codeql.yml + deskmodal-ffi.yml + docs.yml |
| tradesurface | `D:\code\tradesurface` | `.github/workflows/ci.yml` + `plugin-ci.yml` + benchmark.yml + nightly.yml + release.yml |
| service-sdk | `D:\code\repo-extraction\service-sdk` | `.github/workflows/ci.yml` + release.yml |
| plugin-tools | `D:\code\repo-extraction\plugin-tools` | `.github/workflows/ci.yml` + release.yml |
| price-feed-service | `D:\code\repo-extraction\price-feed-service` | `.github/workflows/ci.yml` + release.yml |
| paper-trading | `D:\code\repo-extraction\paper-trading` | `.github/workflows/ci.yml` |
| plugin-index | `D:\code\repo-extraction\plugin-index` | `.github/workflows/validate.yml` |

**Local parity**:
- `scripts/local-ci.sh` (deskmodal + tradesurface) runs the exact same
  commands CI runs. Flags: `--quick`, `--rust-only`, `--fe-only`, `--ts-only`.
- `scripts/pre-commit` runs the fast subset before every commit. Installed
  via `scripts/install-hooks.sh` → `.git/hooks/pre-commit`.

**Composite actions**:
- `.github/actions/install-protoc/action.yml` — single source of truth for
  apt/brew/choco protoc install. Duplicated into each repo that needs it
  (composite actions can't be referenced across repos).

**rust-cache strategy**: every `Swatinem/rust-cache@v2` shared-key
includes `hashFiles('**/Cargo.lock')`. Prevents stale caches from masking
dependency-upgrade bugs.

**Advisory exceptions** (kept in sync across deny.toml + audit.toml):
- `deny.toml` — v2 schema. Ignores RUSTSEC-2024-0370 (proc-macro-error),
  RUSTSEC-2024-0411..0420 (gtk-rs GTK3 family), RUSTSEC-2024-0436 (paste),
  RUSTSEC-2025-0057 (fxhash), RUSTSEC-2025-0075/0080/0081/0098/0100
  (unic-*), RUSTSEC-2025-0119 (number_prefix), RUSTSEC-2023-0071 (rsa
  Marvin Attack). All have "revisit by 2026-07-01" or "until tauri
  drops gtk3" justifications inline.
- `.cargo/audit.toml` — same list PLUS RUSTSEC-2024-0429 (glib). glib
  only surfaces in cargo-audit's wider (unfiltered) target scan;
  cargo-deny filters by configured targets and doesn't see it.
- `deny.toml` [licenses] allow list must only contain licenses that
  actually appear in the graph. `OpenSSL` and `Unicode-DFS-2016` were
  removed because cargo-deny in CI treats `license-not-encountered` as
  FAILED. If a new dep introduces one of these, add it back with a
  justification.
- Any new exception needs RUSTSEC ID + justification + revisit date +
  Security Engineer sign-off.

**Workspace member license field**: every crate under `crates/`, `apps/`,
and `OptiScript/crates/` must declare `license = "MIT OR Apache-2.0"` and
`publish = false` explicitly in its own Cargo.toml (NOT via
`license.workspace = true`) so cargo-deny can resolve them without
`[licenses] private = { ignore = true }` backstop ambiguity.

**Platform scope: Windows + macOS only.** Linux is out of scope —
the matrix entries, `libwebkit2gtk`/gtk/appindicator installs,
`package-linux`, `sign-linux`, `coverage-rust`, `integration-test`,
and `benchmark` jobs have all been removed from ci.yml. `sbom:`
still runs on ubuntu-latest because it's a host-agnostic
cargo-metadata job, not a Linux target build. To re-introduce
Linux, see the "Platform scope" section of
`D:\celer\desk\docs\ci-architecture.md`.

**Known disabled jobs** (awaiting fix):
1. **FDC3 Conformance** — job removed because `tests/e2e/run-conformance.sh`
   referenced the missing `e2e/fdc3-conformance` directory and needed
   cargo-tauri. Re-add once a real Playwright harness is wired up.
2. **Vitest drifts** — `vitest:` and `coverage-frontend:` jobs have
   `continue-on-error: true` tracking ~20 pre-existing drifts across
   AppStore, DragContext, CommandPalette, WatchlistPanel, etc. Fix in a
   dedicated test-maintenance pass.

**What was fixed in recent sessions** (committed to main, don't redo):
- `target-cpu=native` removed from `.cargo/config.toml` (fixed ring 0.17
  CAPS_STATIC assertion on macOS ARM64).
- `@types/jest` added to `apps/deskmodal-agent/package.json` + tsconfig
  test file exclusion (fixed TS2688 on eslint job).
- `ort` dep added with `download-binaries` feature to `crates/deskmodal-ai/Cargo.toml`
  (fixed ort-sys xcframework linking on macOS).
- `deny.toml` rewritten to v2 schema with explicit RUSTSEC ignores.
- `.cargo/audit.toml` created with explicit ignores.
- cargo-deny + cargo-audit `continue-on-error` removed.
- `@testing-library/jest-dom/vitest` subpath in tradesurface tsconfigs
  across 10 packages.
- `channels[0]!.id` non-null assertion pattern across 13 App.tsx files.
- Multiple vitest test-file rewrites: ThemeGallery, SettingsPanel,
  WelcomeScreen, IntentResolver, useSkin, useWorkspaceHue, theme-presets,
  WorkspaceManager.
- Inline-style-audit violations fixed in Toolbar, StatusBar, TabStrip,
  SettingsPanel.
- Service-SDK `drain Hello before HealthReport` test fix (in-monorepo
  copy AND extracted repo).
- Circuit-breaker `test_force_half_open` helper (replaces panicking
  `Instant::now() - Duration::from_secs(600)` on Windows low-uptime CI).
- Composite protoc install action across deskmodal + 4 extraction repos.
- rust-cache keys aligned with `hashFiles('**/Cargo.lock')` everywhere.
- DESKMODAL_REPO_TOKEN set as Dependabot secret (not just Actions)
  across all 7 repos — fixes private dep cloning on Dependabot PRs.
- `CARGO_NET_GIT_FETCH_WITH_CLI=true` + `persist-credentials: false`
  combo for cross-repo cargo git deps.
