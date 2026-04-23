---
description: "Run the DeskModal local CI gate suite — fmt, clippy, typecheck, tests, build, sign. Scoped to --fast or --full."
user-invocable: true
---

# /ci [mode]

Thin wrapper over `scripts/local-ci.sh`. Runs the same gates that block every
push; if `/ci --full --sign` passes locally, CI on the remote should too.

## Modes

| Mode | What runs | Typical latency |
|------|-----------|-----------------|
| `/ci` or `/ci --fast` | fmt + clippy + typecheck across platform, tradesurface, optiscript, plugin-tools | ~30–90s (Nx + cargo cached) |
| `/ci --full` | all fast gates + `cargo test --workspace`, `nx run-many -t test`, JSON validation | ~3–8 min |
| `/ci --full --sign` | full + `build-dist.sh --release --sign` | ~5–12 min |

## Execution

1. **Never modify source files** — CI is read-only on the code under test.
2. **Incremental is default** — Nx cache + Cargo incremental stay warm between runs; don't pass `--skip-nx-cache` unless you're diagnosing a cache-related bug.
3. Run from the workspace root:
   ```bash
   ./scripts/local-ci.sh --fast
   ./scripts/local-ci.sh --full --sign
   ```
4. Read the "Results" table at the end. The gate set is deterministic — report pass/fail counts and the names of any failing gates.
5. For a single failing gate, drill in directly (e.g. `pnpm nx run <project>:test`) rather than re-running the whole suite.

## Flags worth knowing

| Flag | Effect |
|------|--------|
| `--fast` | fmt + clippy + typecheck only |
| `--full` | also runs tests + JSON schema validation |
| `--sign` | appends `build-dist.sh --release --sign` to produce a signed dist |
| `--platform` | platform gates only (no tradesurface / optiscript) |
| `--plugins` | tradesurface + optiscript + plugin-tools only |

## Rules

- A failing gate blocks push — fix it or explicitly document why it's deferred.
- Never skip hooks (`--no-verify`) or force-push — both violate `.claude/rules/honesty.md`.
- If a gate is flaky (e.g. port contention on parallel test runs), reproduce it with the exact CI invocation — don't hand-wave a retry.
- `local-ci.sh` supersedes any ad-hoc `cargo test` or `pnpm test` invocations for push-blocking verdicts; use it before claiming "CI green".
