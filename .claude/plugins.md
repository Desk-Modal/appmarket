# Claude Code plugins — DeskModal workspace

Declared in `.claude/settings.json` under `enabledPlugins` with the format `"<plugin>@<marketplace>": true` (the actual format Claude Code 2.x writes on `claude plugin install --scope project`).

Auto-installed on every fresh `git clone` + first Claude Code session via the `bootstrap-plugins.sh` SessionStart hook — zero manual step required.

## Installed (6)

| Plugin | Purpose for DeskModal |
|---|---|
| **context7** | Live version-specific docs for Tauri 2, React 19, FDC3 2.2, tokio, serde, flume, DashMap, ArcSwap. Anti-hallucination when authoring against these surfaces. |
| **typescript-lsp** | TS symbol refs, diagnostics, hover across 8 TradeSurface apps, marketplace/, plugin-tools/, core-server-api/. Complements `codebase-memory-mcp`. |
| **semgrep** | Real-time scanning for command injection, XSS, unsafe eval, hardcoded secrets. Fires inline as code is authored. **Requires `semgrep` CLI on PATH** — installed automatically by `scripts/setup.sh` (macOS: Homebrew; Linux: pip); if missing at session start the plugin's own hook emits a non-blocking warning. |
| **plugin-dev** | Seven skills for authoring Claude Code hooks, MCP servers, commands, agents. Correctness for our own `.claude/` configuration. |
| **skill-creator** | Author and measure additional skills as workflow patterns emerge. |
| **chrome-devtools-mcp** | Control and inspect live Chrome via CDP. Richer DOM + network + evaluation than our `scripts/cdp-test-runner.py`. |

## Auto-installation mechanism

1. **`enabledPlugins` in `.claude/settings.json` (git-committed).** Format is `"<plugin>@<marketplace>": true`. Claude Code 2.x reads this on session start and enables the plugins if they're installed.
2. **`.claude/hooks/bootstrap-plugins.sh` (SessionStart hook).** On every session start, runs `scripts/install-plugins.sh --check`. If any listed plugin is missing, runs the full installer once. Idempotent — steady-state silent.
3. **`scripts/install-plugins.sh` (manual fallback).** Idempotent plugin installer. Uses `claude plugin install <name> --scope project` so installs persist into `.claude/settings.json`. Run once per new developer machine if the bootstrap hook hasn't fired yet (e.g. first `git clone` before a Claude Code session).

Marketplace `claude-plugins-official` (sourced from `anthropics/claude-plugins-official` GitHub repo) is ensured by the installer — adds the marketplace if missing.

## Explicitly NOT installed — conflict with existing MCPs

| Plugin | Conflict |
|---|---|
| `playwright` | `.mcp.json` declares `@playwright/mcp@0.0.70` with project-local chromium under `tools/gui/.playwright-browsers`. |
| `github` | `.mcp.json` declares custom `github-mcp-server` binary in `tools/`. |
| `rust-analyzer-lsp` | `.mcp.json` declares custom `rust-analyzer-mcp` binary in `tools/bin/`. (If the marketplace variant is also installed at user scope, it's harmless overlap — our MCP takes priority.) |

## Explicitly NOT installed — overlap with existing config

| Plugin | Overlap |
|---|---|
| `serena`, `sourcegraph`, `greptile` | All overlap `codebase-memory-mcp` semantic search. |
| `remember` | Overlaps commit-driven handoff protocol in `.claude/rules/core.md` §13 + `.session-state/handoffs/`. |
| `feature-dev`, `ralph-loop` | Overlap the `/loop` skill + `maestro-orchestrator` persona. |
| `coderabbit`, `code-review`, `pr-review-toolkit`, `optibot` | Adversarial-review matrix in `.claude/rules/core.md` §7 is custom-tuned per capability signal. |
| `frontend-design`, `code-simplifier` | Overlap `deskmodal-design-agent`, `ux-design-lead`, `style-bot`. |
| `explanatory-output-style`, `learning-output-style` | `outputStyle: "concise"` is set — these go the opposite direction. |

## Explicitly NOT installed — out of scope

Non-TS language LSPs (clangd, csharp, gopls, jdtls, kotlin, swift, php, ruby, lua, elixir-ls, pyright) — no code in these languages beyond minimal Python scripts. Hosting/DevOps (vercel, supabase, firebase, railway, netlify-skills, deploy-on-aws, aws-serverless, fastly) — DeskModal ships as signed desktop binary. PM/comms (linear, asana, atlassian, slack, discord, telegram, imessage, intercom, zoominfo). Payment/marketing/CMS/data plugins — not our domain.

## Verifying install state

```bash
bash scripts/install-plugins.sh --check       # workspace view — should report all 6 already installed
claude plugin list | grep claude-plugins-official
cat .claude/settings.json | python3 -c 'import json,sys; print(list(json.load(sys.stdin).get("enabledPlugins", {}).keys()))'
```

## Revising the set

Edit the `PLUGINS=( ... )` array in `scripts/install-plugins.sh`, then either:
- Run `claude plugin install <new-plugin> --scope project` (Claude Code writes to `.claude/settings.json` for you), OR
- Edit `.claude/settings.json` `enabledPlugins` manually using the `"<plugin>@<marketplace>": true` format.

Update this file to document the addition. Commit all three together. Sub-repos mirror via the canonical-file sync (see `.claude/rules/parallel-sessions.md`).
