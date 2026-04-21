# ADR Discipline

Architecture Decision Records (`.codebase-memory/adr.md`) in every
indexed codebase-memory-mcp (CBM) project must stay current with the
code they describe. An ADR that is 6 months behind the code it
documents is a stale asset that misleads every future session.

## Cardinal rule

Any commit that changes an **architectural surface** (see table
below) MUST also do one of:

1. Update the project's `.codebase-memory/adr.md` in the same
   commit (author the update via `manage_adr(project=<CBM project>,
   mode="update", content=<updated ADR>)` — CBM writes to disk for
   you; `git add .codebase-memory/adr.md`), OR
2. Carry an `[adr:not-applicable] <reason>` trailer in the commit
   message body with a one-line justification (e.g., "dead-code
   removal", "test fixture", "rename only").

## Architectural surfaces (drift-triggering paths)

Per-project signals that `scripts/adr-drift-check.sh` flags:

| Project type | Surfaces |
|---|---|
| Rust workspace | `Cargo.toml` (root), new `crates/<N>/Cargo.toml`, new `crates/<N>/src/lib.rs`, new `services/<N>/Cargo.toml`, changes to `src/lib.rs`, new `src/routes/<N>.rs`, new `src/commands/<N>.rs`, new `migrations/*.sql` |
| TS monorepo | `package.json` (root), new `packages/<N>/package.json`, new `apps/<N>/plugin.toml`, new `apps/<N>/package.json` |
| Schema repos | `schema/**/*.md`, `plugin.toml` at repo root |
| Workspace / team discipline | `.claude/rules/*.md`, `.claude/agents/*.md`, `.specify/memory/constitution.md`, `specs/compat-ladder.yml` |
| Any | changes to `.codebase-memory/adr.md` resolve drift for that commit |

Paths **exempt** from drift detection (touching only these never
triggers a warning):

- `dist/**`, `target/**`, `node_modules/**`, `**/*.lock`
- `_worktrees/**` (transient parallel-dispatch workspaces)
- `tests/fixtures/**`, `fixtures/**`
- Pure documentation: `README.md`, `CHANGELOG.md`, `docs/**/*.md`
  (these MAY still warrant an ADR update; but the check does not
  trigger on them alone).

## Enforcement tiers

The rule scales with posture — start advisory, ratchet to strict
when the team is ready.

| Tier | Command | Exit behaviour | Where wired |
|---|---|---|---|
| **Advisory (default)** | `scripts/adr-drift-check.sh --ci` | Always exits 0; prints warning to stderr + logs to `.session-state/adr-drift.log` | `scripts/local-ci.sh --fast` (every commit) |
| **Advisory pre-commit** | `scripts/adr-drift-check.sh --staged` | Exit 0; prints warning to stderr | `scripts/pre-commit.sh` (installed as `.git/hooks/pre-commit`) |
| **Strict (opt-in)** | `scripts/adr-drift-check.sh --strict` | Exit 1 on drift | Teams can wire into pre-push or CI when ready |
| **Single-commit opt-out** | commit message trailer `[adr:not-applicable] <reason>` | Clean for that commit | Author discretion |

## How to satisfy the rule (architectural change)

```
# 1. Make the architectural code change.
vim crates/my-new-crate/src/lib.rs

# 2. Update the ADR via CBM (from your Claude Code session):
#    manage_adr(project="Users-alice-deskmodal-platform", mode="update", content=<...>)
#    CBM writes to platform/.codebase-memory/adr.md automatically.

# 3. Stage both.
git add crates/my-new-crate/ .codebase-memory/adr.md

# 4. Commit — the drift check sees the ADR update + passes.
git commit -m "feat: add my-new-crate for X use case"
```

## How to opt out (non-architectural change)

For a commit that touches an arch-surface path but doesn't change
architecture (rename, dead-code removal, test fixture, lockfile
regeneration), add a body trailer:

```
refactor: rename internal helper fn

[adr:not-applicable] Rename only; no API surface change.
```

Abuse of the trailer is a review-gate issue — reviewers should
reject opt-outs that hide real architecture changes.

## Escape hatch

`DESKMODAL_LAX=1` bypasses `--strict` globally. Every bypass
appends one line to `.prod-check/lax-bypass.log` with the repo +
commit range + drift count — consistent with the existing
`commit-message-honesty` and `parallelism` bypasses.

## Interaction with related rules

- `.claude/rules/honesty.md` — the ADR drift check is an
  evidence-based assertion; the report cites exact file paths and
  commit SHAs.
- `.claude/rules/no-deferrals.md` — "I'll update the ADR in a
  follow-up task" is a deferral, banned. Either update in-commit or
  use the `[adr:not-applicable]` trailer with a reason.
- `.claude/rules/verification.md` — `adr-drift-check.sh` runs as a
  `local-ci.sh --fast` gate, not as a standalone tool. The
  canonical verification path is preserved.
- `.claude/rules/context-discipline.md` — CBM's `manage_adr` is the
  structured way to persist architectural decisions; advisory
  drift-check surfaces when that persistence has fallen behind.

## Amendment

Amendments follow the Constitution (`.specify/memory/constitution.md`
Governance). Required reviewers: `documentation-engineer` (primary)
+ `qa-architect` (CI gate integrity).
