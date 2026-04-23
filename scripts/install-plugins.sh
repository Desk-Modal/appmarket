#!/usr/bin/env bash
# install-plugins.sh — idempotent Claude Code plugin installer.
#
# Fallback for environments where settings.json `enabledPlugins` doesn't
# auto-install. Run once per machine after a fresh `git clone`.
#
# Plugins recommended for the DeskModal workspace — see .claude/plugins.md
# for the rationale behind each selection.
#
# Usage: scripts/install-plugins.sh
#
# Idempotent: running twice is safe; `claude plugin install` is a no-op
# when a plugin is already present.

set -u

PLUGINS=(
    context7            # live version-specific docs — anti-hallucination
    typescript-lsp      # TS symbol intelligence for TradeSurface + marketplace TS
    semgrep             # real-time security pattern detection
    plugin-dev          # hooks + MCP + commands + agents correctness
    skill-creator       # author additional skills
    chrome-devtools-mcp # live CDP inspection beyond cdp-test-runner.py
)

# Skipped on purpose (reason documented in .claude/plugins.md):
#   playwright           — custom .mcp.json playwright already in use
#   github               — custom github-mcp-server binary in tools/
#   rust-analyzer-lsp    — custom rust-analyzer-mcp binary in tools/
#   serena, sourcegraph, greptile — overlap codebase-memory-mcp
#   remember             — overlaps commit-driven handoff in .claude/rules/core.md §13
#   feature-dev, ralph-loop — overlap /loop + maestro-orchestrator
#   coderabbit, code-review, pr-review-toolkit, optibot — our review matrix is custom

if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: 'claude' CLI not on PATH" >&2
    exit 1
fi

installed=0
skipped=0
failed=0

for p in "${PLUGINS[@]}"; do
    printf "→ %-24s  " "$p"
    if claude plugin install "$p" >/dev/null 2>&1; then
        echo "installed"
        installed=$((installed + 1))
    elif claude plugin list 2>/dev/null | grep -q "^$p\b"; then
        echo "already installed"
        skipped=$((skipped + 1))
    else
        echo "failed (see: claude plugin install $p)"
        failed=$((failed + 1))
    fi
done

echo ""
echo "summary: installed=$installed  already=$skipped  failed=$failed"

[ "$failed" -eq 0 ]
