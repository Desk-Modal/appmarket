#!/usr/bin/env bash
# install-plugins.sh — idempotent Claude Code plugin installer.
#
# Recommended plugins for the DeskModal workspace. See .claude/plugins.md
# for rationale. Uses --scope project so installs are persisted into
# .claude/settings.json (git-tracked) — every developer who pulls the
# repo gets the same plugin set.
#
# Claude Code's own auto-install-from-settings.json behaviour is version-
# dependent. This script is the reliable path: idempotent, safe to run
# twice, works on every Claude Code version >= 2.0.
#
# Usage:
#   scripts/install-plugins.sh                  # install missing; leave existing alone
#   scripts/install-plugins.sh --check          # list what would be installed; no writes

set -u

MARKETPLACE="claude-plugins-official"

PLUGINS=(
    context7              # live version-specific docs — anti-hallucination
    typescript-lsp        # TS symbol intelligence for TradeSurface + marketplace TS
    semgrep               # real-time security pattern detection
    plugin-dev            # hooks + MCP + commands + agents authoring correctness
    skill-creator         # author + measure additional skills
    chrome-devtools-mcp   # live CDP inspection for GUI verification
)

# Skipped on purpose (see .claude/plugins.md for full rationale):
#   playwright           — custom .mcp.json playwright config already in use
#   github               — custom github-mcp-server binary in tools/
#   rust-analyzer-lsp    — custom rust-analyzer-mcp binary in tools/ (user-scope
#                          install of the marketplace variant is OK as belt-
#                          and-braces but not required)
#   serena, sourcegraph, greptile — overlap codebase-memory-mcp
#   remember             — overlaps commit-driven handoff (core.md §13)
#   feature-dev, ralph-loop — overlap /loop + maestro-orchestrator
#   coderabbit, code-review, pr-review-toolkit, optibot — custom review matrix

MODE=install
for arg in "$@"; do
    case "$arg" in
        --check) MODE=check ;;
        -h|--help)
            sed -n '2,25p' "$0"
            exit 0
            ;;
    esac
done

if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: 'claude' CLI not on PATH. Install from https://claude.com/code." >&2
    exit 1
fi

# Ensure the marketplace is configured. Required once per machine if
# the user has never initialised it. Safe to run repeatedly.
if ! claude plugin marketplace list 2>/dev/null | grep -q "^  ❯ $MARKETPLACE\b"; then
    echo "→ configuring marketplace: $MARKETPLACE"
    claude plugin marketplace add anthropics/claude-plugins-official 2>&1 | tail -2 || true
fi

installed_list=$(claude plugin list 2>/dev/null | grep -E "^  ❯ .+@$MARKETPLACE\$" | sed -E "s/^  ❯ (.+)@$MARKETPLACE\$/\1/")

installed=0
already=0
failed=0

for p in "${PLUGINS[@]}"; do
    printf "→ %-24s  " "$p"
    if echo "$installed_list" | grep -qx "$p"; then
        echo "already installed"
        already=$((already + 1))
        continue
    fi
    if [ "$MODE" = "check" ]; then
        echo "would install"
        continue
    fi
    # --scope project persists into .claude/settings.json (git-tracked)
    if claude plugin install "$p" --scope project 2>&1 | grep -q "Successfully installed"; then
        echo "installed (project scope)"
        installed=$((installed + 1))
    else
        echo "FAILED — try: claude plugin install $p --scope project"
        failed=$((failed + 1))
    fi
done

echo ""
if [ "$MODE" = "check" ]; then
    already_count=$already
    missing_count=$((${#PLUGINS[@]} - already))
    echo "summary: $already_count already installed, $missing_count would be installed"
    [ "$missing_count" -eq 0 ]
else
    echo "summary: installed=$installed  already=$already  failed=$failed"
    [ "$failed" -eq 0 ]
fi
