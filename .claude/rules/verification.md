# Verification Rules

Per the 2026-04-19 directive: **always verify by leveraging our local
CI/CD, launching and verifying with signed plugins; never build
independently of our local CI/CD.**

## Cardinal rule: one verification path

Every verification invocation — in task specs, the /loop runbook,
rules, agent prompts, and CI workflows — uses one of these
entrypoints:

| Entrypoint | When to use |
|---|---|
| `scripts/local-ci.sh --fast` | Per-commit sanity: fmt + clippy + typecheck + hook tests + prod-check --fast. ~2 min. |
| `scripts/local-ci.sh --full` | Pre-push Rust-centric: adds cargo test + release check + lock audit + Rust-side integration tests. ~10 min. |
| `scripts/local-ci.sh --full --sign` | Adds dmpkg sign round-trip. Required any time the change touches a signed plugin or the SDK signing path. |
| `scripts/launch.sh --verify` | **End-gate**: runs `local-ci --full --sign` (which includes `build-dist --release --sign`), then exits 0. The signed `dist/` is the shipping artefact. No launch, no CDP — runtime behaviour is asserted by the Rust + TS test suites exercised inside `local-ci`. |
| `scripts/build-dist.sh --sign` | Explicit artefact build. Invoked by the two above; call directly only when you need the signed dist without launching. |
| `.claude/scripts/optiscript-prod-check.sh` (→ `scripts/prod-check.sh` after task 005) | Gate runner. Invoked by `local-ci.sh` and `launch.sh --verify`. |

Direct `cargo build` / `cargo test` / `pnpm nx build` / `pnpm nx test`
are **per-crate development conveniences**, not verification. They
do not satisfy any Acceptance clause in any task spec.

## Why

- **Signed plugins.** The ACL/signature chain is part of the
  production contract. Verifying against an unsigned cdylib hides
  signature regressions until they land on a teammate machine. Every
  verify path builds + signs.
- **dist/ IS the runtime.** `install_root()` walks up from the binary
  looking for `config/desk.toml`; `target/` doesn't have that
  marker. Launching from `target/` runs a fundamentally different
  code path than what teammates and users run.
- **Runtime behaviour lives in the test suites.** Rust `cargo test`
  (incl. integration tests that spin up a real `Tauri::Builder`) plus
  TS `vitest` / `@playwright/test` assertions are the runtime truth.
  They run inside `local-ci --full`. CDP was removed 2026-04-21 — it
  was never reachable on macOS WKWebView and introduced a
  cross-platform-infeasible gate. Apps/FDC3/price-flow assertions now
  live in Rust integration tests + Playwright GUI specs under
  `tests/gui/`.
- **CI/CD parity.** The `.github/workflows/prod-check.yml` matrix job
  runs `scripts/setup.sh --ci` + `.claude/scripts/optiscript-prod-check.sh`.
  Local verification must hit the same gates or local-green → remote-red
  divergence kills trust.

## Enforcement

- **In task specs:** the **Verification commands** section of every
  task spec uses commands from the table above. Any raw
  `cargo (build|test|run|check)` / `pnpm (build|test|nx build|nx test)`
  is flagged by `scripts/audit-verify-discipline.sh`
  (task 015) at commit time.
- **In the /loop runbook:** Phase 4 (smoke-check) calls
  `scripts/local-ci.sh --fast`. Phase 5 (extended verification) calls
  `scripts/launch.sh --verify` for any change that touches GUI /
  FDC3 / plugins / signed artefacts.
- **In CI:** the `.github/workflows/prod-check.yml` matrix already
  uses `scripts/setup.sh --ci` + `scripts/launch.sh --verify`.

## Permitted exceptions

A short, enumerable list — **not an escape hatch**:

1. **`scripts/setup.sh`** itself — installs cargo tools
   (`cargo install cargo-deny`, etc.), invokes `cargo build` on
   internal helpers. Setup is the bootstrap; it can't verify itself
   through the gates it's installing.
2. **`scripts/local-ci.sh`** and everything it calls — the
   implementation of the verification pipeline uses raw `cargo` and
   `pnpm` directly. This is the engine; rules govern its callers.
3. **`scripts/build-dist.sh`** — same reason.
4. **Per-crate dev in a developer's shell** — when iterating on one
   crate, developers run `cargo check -p <crate>` freely. Verification
   of a commit is different from iterating on work-in-progress.
5. **Hook regression tests** (`.claude/hooks/tests/*.test.sh`) — unit
   tests for shell scripts don't need to boot dist; they can run
   directly. Wired into `local-ci.sh --fast`'s `hooks:*` gate
   already.
6. **Implementation helpers under `scripts/quality-gates/**`,
   `scripts/lib/**`, `.claude/scripts/**`, `tools/**`** — the audit's
   allowlist is extension-scoped here: only `*.sh`, `*.ps1`, `*.cmd`,
   `*.py`, `*.rs`, `*.toml` are exempt. Documentation files under
   those roots (e.g. `scripts/quality-gates/README.md`) still go
   through the audit. This is deliberate: docs describing the
   verification pipeline should not themselves quote the forbidden
   patterns outside of a properly-justified `audit:allow` bypass.

No other exceptions. If a new scenario arises, amend this file
(requires a commit that itself passes verification).

## Per-line escape hatch — `<!-- audit:allow: <reason> -->`

In the rare case a Verification section legitimately needs to show a
raw `cargo`/`pnpm`/`npm`/`npx` invocation (for example, a spec that
documents the audit's OWN regression-test fixtures, or a migration
note explaining what a historical command used to look like), place
the annotation **at column 0** on the same line as the forbidden
command:

```
<!-- audit:allow: <one-sentence justification> --> cargo test --workspace
```

Rules enforced by `scripts/audit-verify-discipline.sh`:

- **Non-empty justification** — the `<reason>` between `audit:allow:`
  and the closing `-->` must contain at least one non-whitespace
  character. A bare `<!-- audit:allow -->` (no reason) is **rejected**
  and surfaces as a meta-violation.
- **Column-0 only** — the annotation must begin with (optional)
  leading whitespace only. Wrapping it inside backticks, quotes, or
  any other non-whitespace context does **not** suppress the
  violation — the audit flags it as structural invalidity. This
  prevents backtick-wrapped prose (`"run \`<!-- audit:allow --> cargo test\` to..."`)
  from silently bypassing the gate.
- **Audit log** — every honoured bypass appends one line to
  `.prod-check/audit-allow-bypasses.log` with ISO timestamp, short
  git SHA, file path, line number, and the reason string. Reviewers
  use the log to spot escape-hatch abuse trends across specs and
  sessions. The log is git-ignored (machine-local history).

If `audit-verify-discipline.sh` cannot write to `.prod-check/`
(permission denied), the bypass is still honoured but a `WARN` is
printed to stderr so the operator can repair the permission issue.
This mirrors the `DESKMODAL_LAX` audit behaviour in
`scripts/quality-gates/lib/common.sh:180-206`.

## How to add to this rule

Cite a concrete failure mode the cardinal rule can't handle, propose
a new entrypoint or exception, get a reviewer's APPROVE per the
adversarial review matrix, amend this file plus `scripts/audit-
verify-discipline.sh`'s allowlist in the same commit.
