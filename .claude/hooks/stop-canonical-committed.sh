#!/usr/bin/env bash
# F157 Layer 4 Stop hook: ensure canonical edits are committed before the next turn.
# Per architecture.md §28.1 (auto-commit canonical surfaces).
#
# Reads JSON hook input on stdin; returns JSON decision on stdout.
# Blocks (decision: "block") if there are uncommitted canonical edits.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0   # if cwd invalid, just pass through

# Canonical paths (subset of what architecture.md §28.1 enumerates)
CANONICAL_GLOBS=(
  "specs/**/*.md"
  ".claude/rules/*.md"
  ".claude/agents/*.md"
  ".claude/skills/**/*.md"
  ".claude/settings.json"
  ".mcp.json"
  ".specify/memory/*.md"
  "CLAUDE.md"
)

# Build a `git status --porcelain` filter for canonical files
dirty=$(git status --porcelain 2>/dev/null | awk '
  /^[ MARCD][MARCD]?/ {
    path = $2
    # Strip leading status chars
    if (path ~ /^(specs\/|\.claude\/(rules|agents|skills)\/|\.mcp\.json$|CLAUDE\.md$|\.specify\/memory\/|\.claude\/settings\.json$)/) {
      print $0
    }
  }
' || true)

# Heartbeat regardless (this is also a Stop hook side-effect)
if [ -x "${CWD}/scripts/session-mesh/heartbeat.sh" ]; then
  bash "${CWD}/scripts/session-mesh/heartbeat.sh" >/dev/null 2>&1 || true
fi

if [ -z "$dirty" ]; then
  # No canonical dirt — proceed
  exit 0
fi

# Surface a non-blocking warning via additionalContext (don't hard-block to avoid
# false-positives on partial in-flight edits; the user can see the warning).
# To hard-block, set DESKMODAL_STOP_HOOK_BLOCK=1.
count=$(printf '%s\n' "$dirty" | wc -l | tr -d ' ')
msg="F157 Layer 10 honesty: ${count} canonical file(s) dirty per architecture.md §28.1 auto-commit. Run scripts/wave-commit.sh <file> '<reason>' before next turn:"

if [ "${DESKMODAL_STOP_HOOK_BLOCK:-0}" = "1" ]; then
  cat <<EOF
{
  "decision": "block",
  "reason": "${msg}\n${dirty}",
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "Canonical-files-dirty per F157 Layer 4. Commit before continuing."
  }
}
EOF
  exit 2
fi

# Advisory mode (default) — emit additionalContext, don't block
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "⚠ ${msg}\n${dirty}"
  }
}
EOF
exit 0
