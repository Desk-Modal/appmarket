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

lodestar is the cross-session findings bus (`architecture.md §33`; `discipline.md §26` tier 2). Two sharing planes:

**Same machine (real-time).** All sessions share ONE in-repo store per project; cross-process lock = concurrent reads, serialised same-project writes. `auto_index` is on — never call `index_repository` manually unless a project is provably unindexed. A second session sees the first's graph + knowledge immediately, no git round-trip. `mcp__lodestar__distributed_status` reporting `origin_collisions:1` confirms a single shared cache (`>1` = split cache — re-resolve before trusting reads).

**Across machines / collaborators (git-paced).** Knowledge rides the committed, append-only event log `.lodestar/knowledge/events/*.json` — content-addressed + conflict-free (set-union: distinct events are distinct files; a pull always folds cleanly, no merge conflict). Committed (text `eol=lf`): `events/**` + `snapshot.json`. Gitignored (regenerable cache): `*.db`, `graph.db.zst`. The `ours` merge driver (`.gitattributes merge=ours` on the cache) is registered per-clone by `setup.sh` step 8a. A peer sees a claim only after `push`→`pull`; `distributed_status.peer_digest` proves convergence WITHOUT folding (equal digest across two checkouts ⇒ identical knowledge set).

**Capture discipline (how knowledge evolves + is shared).** When a session verifies a durable fact (invariant, decision, deliverable roll-up), write a claim via `mcp__lodestar__knowledge_put` (anchored to real symbols), then commit `.lodestar/knowledge/` + push — so the next session/dev cites it via `knowledge_get`/`knowledge_claims` instead of re-deriving (~21× fewer tokens; mitigates relearning + keeps everyone aligned on the same anchored facts). `invariant:pure` claims auto-activate (Stage-1 deterministic gate, no model). Subjective claims (design/a11y/decision/usage) stay `draft` until a cross-FAMILY Stage-2 judge affirms them — NOT configured today (no ollama/API judge), so they remain `draft`: still readable via `knowledge_claims`, just not served as `active` by `knowledge_get`'s default. The full code-knowledge GRAPH (symbols/calls/impact) shares regardless of judge.

**Anti-drift.** Each claim anchors to a `node_content_hash`; when that code changes the claim auto-transitions `stale`/`contradicted` (never silently wrong), with `dead_active` detection for claims that no longer anchor live code. `mcp__lodestar__knowledge_coverage` is the lifecycle dashboard (active/draft/stale/contradicted/dead_active). A `projection_fresh:false` in `distributed_status` means the SQLite projection needs a refold (lazy, self-heals on next index) — it is NOT drift.

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
