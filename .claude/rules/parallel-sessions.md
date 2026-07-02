# Parallel Claude Code sessions

Multiple Claude Code sessions work against this workspace simultaneously. This file is the isolation contract so they don't stomp each other.

## Structure

```
/Users/adrian/deskmodal/        ← outer git repo: .claude/, .specify/, specs/, scripts/, docs
├── platform/                    ← independent git repo: Rust + Tauri app
├── plugins/{tradesurface,optiscript}/   ← independent git repos
├── plugin-tools/                ← independent git repo
├── marketplace/{appmarket,plugin-index}/ ← independent git repos
└── core-server-api/             ← independent git repo
```

Each sub-directory is a **separate git repo**, not a submodule. Their commits are fully independent.

## Session isolation contract

Every session MUST:

1. **Set `CLAUDE_PROJECT_DIR`** to the git repo it owns. Isolates `.session-state/`, hooks' working dirs, counters, handoffs.
2. **Work on a session-scoped branch**: `sess/<topic>-<YYYY-MM-DD-HHMM>` (or for Feature work, `feat/<NNN>-<topic>`). Never commit directly to `main` without a merge via PR.
3. **Edit only files inside its `$CLAUDE_PROJECT_DIR`.** Root-canonical files (see §Canonical file ownership) are edited only from the root session.
4. **Honor the launch-lockfile** before running `scripts/launch.sh --verify`: check `/tmp/deskmodal-launch.lock` — if present and recent (< 15 min old), another session owns the GUI; wait or skip.

Cross-session coordination is by **native per-repo worktree isolation + single-session-per-repo discipline + native auto-memory** (architecture.md §33) — the bespoke Session Mesh ledger is retired.

## Canonical file ownership

These paths are mirrored from root to each sub-repo by `scripts/sync-specs.sh --apply`. **They are edited only from the root session:**

- `CLAUDE.md`
- `.claude/rules/**`
- `.claude/agents/**`
- `.claude/skills/**`
- `.claude/hooks/**`
- `.claude/settings.json`
- `.mcp.json`
- `specs/personas/**`
- `.specify/memory/**`

Sub-repo sessions **never edit their local mirrored copies** — the next sync overwrites them. If a sub-repo needs a rule change, request it from the root session or pause and let root make the edit.

## sync-specs.sh usage

On-demand only. Run it when the root session has finished a batch of canonical-file edits AND no sub-repo session has uncommitted changes in its canonical paths. **Verify the latter first** with the per-repo `git status` pre-flight loop — full snippet + multi-session capacity reference table now live in `wiki/playbooks/onboard-new-developer.md`. If any sub-repo prints BLOCKED, resolve before `--apply`. The pre-commit hook does NOT enforce sync-specs — manual discipline.

## lodestar — shared code graph + cross-session knowledge bus

Shared across sessions; `auto_index` on (no manual `index_repository` unless provably unindexed). **Same machine:** one live in-repo store (concurrent reads, serialised writes) — a second session sees the first's graph + knowledge instantly. **Across machines:** git-paced via the committed conflict-free event log `.lodestar/knowledge/events/**` (set-union; `eol=lf`; `merge.ours.driver` from `setup.sh` 8a; `*.db`/`graph.db.zst` gitignored). Capture verified facts (`knowledge_put`→commit `.lodestar/knowledge/`→push) so peers cite via `knowledge_get`, not re-derivation. `invariant:pure` auto-activates (Stage-1 gate); subjective claims stay `draft` until a Stage-2 cross-family reviewer (not author `claude-code`) promotes them -- dormant today (0 drafts; enable via `ollama`+`gemma3:12b`). Anti-drift: `node_content_hash` anchors → auto `stale`/`contradicted` on change. Full model (both planes, capture discipline, `peer_digest` alignment, lifecycle dashboard): `wiki/playbooks/architecture/orchestration.md §33.1`.

## Cloud-scheduled lanes

Cloud lanes are DISABLED for impl/docs/audit/spec/research per quality.md §18.7 #2 (local-only delivery, 2026-05-23). The historical cloud-lane restrictions (CSS/token audits; markdown polish; perf baselines only; never source/IPC/canonical edits) are documented in architecture.md §31 for IF/WHEN re-enabled.

## Resource exclusivity

| Resource | Exclusivity | Mechanism |
|---|---|---|
| `$CLAUDE_PROJECT_DIR/.session-state/` | Per session | `CLAUDE_PROJECT_DIR` isolation |
| `/tmp/deskmodal-launch.lock` | One `launch.sh --verify` at a time | Lockfile with stale-check |
| `origin/main` push | Standard git race; second pushes rebase | `git pull --rebase` + retry |
| pre-commit hook | Serialised per repo | `flock` in `pre-commit-guard.sh` |
| lodestar index writes | Single-writer per project | Server-enforced |
| Per-repo `CARGO_TARGET_DIR` | Shared warm cache; same-repo builds serialise | Per-repo dir (architecture.md §29 no-duplicate-builds) |
