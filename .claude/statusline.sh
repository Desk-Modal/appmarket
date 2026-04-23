#!/usr/bin/env bash
# Claude Code statusline — one line, <80 chars.
# Shows: branch | ahead/behind main | dirty file count | active feature (if any)
set -u

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
branch=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) || { echo ""; exit 0; }
ahead=$(git -C "$ROOT" rev-list --count "origin/main..HEAD" 2>/dev/null || echo 0)
behind=$(git -C "$ROOT" rev-list --count "HEAD..origin/main" 2>/dev/null || echo 0)
dirty=$(git -C "$ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

feat=""
[ -f "$ROOT/.session-state/active-feature" ] && feat="  feat=$(cat "$ROOT/.session-state/active-feature")"

# Compact format: ⎇ branch ↑N ↓M ●dirty  feat=xxx
printf '⎇ %s ↑%s ↓%s ●%s%s' "$branch" "$ahead" "$behind" "$dirty" "$feat"
