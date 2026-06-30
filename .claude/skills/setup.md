---
description: "Sync the developer environment with the workspace's committed contract. Idempotent — safe to run anytime."
user-invocable: true
---

# /setup [mode]

Apply the Claude Code / MCP / hook scaffolding to every sub-repo and ensure
the workspace-vendored tools are installed + up-to-date. The drift-check
hook fires this automatically when the env contract changes; invoke
manually when you know you need to resync (e.g. just pulled a major
branch).

## Modes

| Mode | What runs |
|------|-----------|
| `/setup` | `scripts/setup.sh --config-only` — reinstalls / updates lodestar and all MCPs, rewrites sub-repo scaffolding, re-indexes every repo. Fast (~15–30s). |
| `/setup full` | `scripts/setup.sh` — the full first-time bootstrap: toolchains, mise, builds, dist, fast CI. Slow (~5–20 min). |

## When to invoke

- After `git pull` in the workspace when drift-check says "applying updates".
- After editing `mise.toml`, `.mcp.json`, or anything under `.claude/hooks/` in the workspace — these are the files hashed by drift-check, so a manual `/setup` re-applies before the next session starts.
- When `lodestar` is missing (`$HOME/.local/bin/lodestar`; freshly cloned, first session).
- After adding a new sub-repo to the clone map in `scripts/setup.sh`.
- Never: to "fix" compiler errors. Use `/build` or direct cargo/nx commands for that.

## Side effects

- Writes `<sub-repo>/.claude/settings.local.json`, `.claude/hooks/*.sh`, `.mcp.json`, `CLAUDE.md` (only if the sub-repo doesn't already own them).
- Adds those paths to each sub-repo's `.git/info/exclude`.
- Installs `lodestar` (to `$HOME/.local/bin/lodestar`), `tools/mise`, and optionally `tools/github-mcp-server` (the last only when `GITHUB_PERSONAL_ACCESS_TOKEN` is exported).
- Never touches `$HOME/.zshrc`, `$HOME/.bashrc`, or any tracked file in a sub-repo.

## Rules

- Run from the workspace root. Subcommands resolve via `$ROOT_DIR`.
- Idempotent — re-running is always safe. The drift-check hook stores a content hash in `tools/.setup-sync-hash` so a second run exits fast when nothing changed.
- If a failure message references a setup or lodestar index log, read it first — it carries the actual error.
