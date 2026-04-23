# Claude Code plugins — DeskModal workspace

Declared in `.claude/settings.json` under `enabledPlugins.anthropics/claude-code`. Committed to git so every machine gets the same set on `git pull`.

If `enabledPlugins` auto-install does not fire in your Claude Code version, run the idempotent fallback: `scripts/install-plugins.sh`.

## Installed (6)

| Plugin | Purpose for DeskModal |
|---|---|
| **context7** | Live version-specific docs lookup. Anti-hallucination for hot external APIs: Tauri 2, React 19, FDC3 2.2, tokio, serde, flume, DashMap, ArcSwap. Used when authoring integration code against these surfaces. |
| **typescript-lsp** | TypeScript/JavaScript language server. Symbol references, diagnostics, hover across all TS code: 8 TradeSurface apps, marketplace/, plugin-tools/, core-server-api/. Complements `codebase-memory-mcp` (graph) with per-file LSP signals. |
| **semgrep** | Real-time scanning for command injection, XSS, unsafe eval, hardcoded secrets. Complements `security-engineer` post-hoc review with inline detection. Fires as code is authored. |
| **plugin-dev** | Seven skills for authoring Claude Code hooks, MCP servers, commands, agents. We actively author all four in `.claude/` — this plugin's checks prevent configuration drift. |
| **skill-creator** | Author and measure skills. Useful as more workflow patterns emerge in `.claude/skills/`. |
| **chrome-devtools-mcp** | Control and inspect live Chrome browsers via CDP. Complements `scripts/cdp-test-runner.py` with richer DOM + network + evaluation during GUI verification of DeskModal + TradeSurface apps. |

## Explicitly NOT installed — conflict with existing MCPs

| Plugin | Conflict |
|---|---|
| `playwright` | `.mcp.json` already declares `@playwright/mcp@0.0.70` with project-local chromium under `tools/gui/.playwright-browsers`. |
| `github` | `.mcp.json` declares custom `github-mcp-server` binary in `tools/`. |
| `rust-analyzer-lsp` | `.mcp.json` declares custom `rust-analyzer-mcp` binary in `tools/bin/`. |

## Explicitly NOT installed — overlap with existing config

| Plugin | Overlap |
|---|---|
| `serena`, `sourcegraph`, `greptile` | All overlap `codebase-memory-mcp` semantic search. |
| `remember` | Overlaps commit-driven handoff protocol in `.claude/rules/core.md` §13 + `.session-state/handoffs/`. |
| `feature-dev`, `ralph-loop` | Overlap the `/loop` skill + `maestro-orchestrator` persona. |
| `coderabbit`, `code-review`, `pr-review-toolkit`, `optibot` | Adversarial-review matrix in `.claude/rules/core.md` §7 is custom-tuned per capability signal. |
| `frontend-design`, `code-simplifier` | Overlap `deskmodal-design-agent`, `ux-design-lead`, `style-bot`. |
| `explanatory-output-style`, `learning-output-style` | `outputStyle: "concise"` is set; these go the opposite direction. |

## Explicitly NOT installed — out of scope

- Non-TS language LSPs (clangd, csharp, gopls, jdtls, kotlin, swift, php, ruby, lua, elixir-ls, pyright) — workspace has no code in these languages beyond minimal Python scripts.
- Hosting/DevOps plugins (vercel, supabase, firebase, railway, netlify-skills, deploy-on-aws, aws-serverless, fastly, aikido, sonatype-guide, endor-labs) — DeskModal ships as signed desktop binary + `@deskmodal/plugins` npm scope; none of these hosts apply.
- PM/Comms (linear, asana, atlassian, slack, discord, telegram, imessage, intercom, zoominfo) — not part of our workflow.
- Payment/Marketing (stripe, sumup, revenuecat, adspirer, postiz) — not our domain.
- CMS (sanity, wix, mintlify) — not our domain.
- Data/ML (data-engineering, huggingface, pinecone, posthog, product-tracking) — not our domain.

## Revising the set

Add or remove from the array in `.claude/settings.json`, update this file, update `scripts/install-plugins.sh`, commit all three together. Sub-repos mirror via the canonical-file sync — see `.claude/rules/parallel-sessions.md`.

## Verifying install

```bash
claude plugin list                    # all installed plugins
claude plugin info context7           # details of a specific plugin
cat .claude/settings.json | jq .enabledPlugins
```
