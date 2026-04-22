# Parallel Claude Code sessions

Multiple Claude Code sessions — local terminals + cloud-scheduled routines — work against this workspace simultaneously. This file is the isolation contract so they don't stomp each other.

## Structure

```
/Users/adrian/deskmodal/        ← outer git repo: .claude/, .specify/, specs/, scripts/, docs
├── platform/                    ← independent git repo: Rust + Tauri app
├── plugins/
│   ├── tradesurface/            ← independent git repo: TradeSurface 8 apps
│   └── optiscript/              ← independent git repo: OptiScript runtime + editor
├── plugin-tools/                ← independent git repo
├── marketplace/
│   ├── appmarket/               ← independent git repo
│   └── plugin-index/            ← independent git repo
└── core-server-api/             ← independent git repo
```

Each sub-directory is a **separate git repo**, not a submodule. Their commits are fully independent.

## Session isolation contract

Every session MUST:

1. **Set `CLAUDE_PROJECT_DIR`** to the git repo it owns. Isolates `.session-state/`, hooks' working dirs, counters, handoffs.
2. **Work on a session-scoped branch**: `sess/<topic>-<YYYY-MM-DD-HHMM>` (or for Feature work, `feat/<NNN>-<topic>`). Never commit directly to `main` without a merge via PR.
3. **Edit only files inside its `$CLAUDE_PROJECT_DIR`.** Root-canonical files (see §Canonical file ownership) are edited only from the root session.
4. **Honor the launch-lockfile** before running `scripts/launch.sh --verify`: check `/tmp/deskmodal-launch.lock` — if present and recent (< 15 min old), another session owns the GUI; wait or skip.

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

On-demand only. Run it when:
- Root session has finished a batch of canonical-file edits AND
- No sub-repo session has uncommitted changes in its canonical paths

Verify the latter first:
```bash
for d in platform plugins/tradesurface plugins/optiscript plugin-tools marketplace/appmarket marketplace/plugin-index core-server-api; do
  n=$(git -C "$d" status --short .claude/ CLAUDE.md .mcp.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] && echo "BLOCKED: $d has $n uncommitted canonical-file edits"
done
```

If any line prints BLOCKED: do not run `sync-specs.sh --apply`. Resolve first.

The pre-commit hook does NOT enforce sync-specs — that was too noisy. It's manual discipline now.

## CBM server (codebase-memory-mcp)

Shared across sessions. `auto_index` is on — do not call `index_repository` manually unless the index is provably stale. Concurrent sessions querying the same project is safe.

## Cloud-scheduled lanes

Created via `RemoteTrigger create` (or the `schedule` skill). Cadence: hourly minimum. Each firing is an isolated cloud session with a fresh git clone.

Cloud lanes are restricted to:
- CSS / design-token audits (Lane D pattern)
- Markdown / doc / spec polish
- Perf baseline captures (bench runs without GUI)

Cloud lanes **do not** do:
- Cross-stack impl requiring GUI verification
- Tauri IPC changes (needs local verification)
- Anything editing root-canonical files (no sync coordination possible from cloud)

## Resource exclusivity

| Resource | Exclusivity | Mechanism |
|---|---|---|
| `$CLAUDE_PROJECT_DIR/.session-state/` | Per session | `CLAUDE_PROJECT_DIR` isolation |
| `/tmp/deskmodal-launch.lock` | One `launch.sh --verify` at a time | Lockfile with stale-check |
| `origin/main` push | Standard git race; second pushes rebase | `git pull --rebase` + retry |
| pre-commit hook | Serialised per repo | `flock` in `pre-commit-guard.sh` |
| CBM index writes | Single-writer per project | Server-enforced |

## Multi-session capacity on one machine (reference)

| Session | Role | `CLAUDE_PROJECT_DIR` | Model |
|---|---|---|---|
| 1 | Orchestrator — rule edits, spec authoring, cross-repo coordination | `/Users/adrian/deskmodal` | Opus 4.7 1M ctx |
| 2 | Platform Rust impl | `/Users/adrian/deskmodal/platform` | Opus 4.7 or Sonnet 4.6 |
| 3 | TradeSurface TSX impl | `/Users/adrian/deskmodal/plugins/tradesurface` | Sonnet 4.6 |
| 4 | OptiScript | `/Users/adrian/deskmodal/plugins/optiscript` | Sonnet 4.6 |
| N | Cloud lanes | (cloud clones) | Sonnet 4.6 |

4 local concurrent + N cloud. Fully isolated by per-repo git + `CLAUDE_PROJECT_DIR` + branch discipline.
