#!/usr/bin/env bash
#
# Stop hook — nudges to `git push` when the session left the repo in a
# clean, CI-passing state ahead of origin/main. Non-blocking — advisory
# text only; pushing is a shared-state action the user owns.
#
# Conditions for the nudge (all must hold):
#   - Working tree clean (git status --short is empty).
#   - HEAD ahead of origin/main by ≥1 commit.
#   - `.session-state/last-ci-pass.stamp` exists and is <15 min old,
#     proving the most recent full local-ci.sh run passed.
#
# Wired in .claude/settings.json under hooks.Stop (after handoff-nudge).

set -u

ROOT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STAMP="$ROOT_DIR/.session-state/last-ci-pass.stamp"

command -v git >/dev/null 2>&1 || exit 0
[ -d "$ROOT_DIR/.git" ] || exit 0

cd "$ROOT_DIR"

# Clean working tree?
if [ -n "$(git status --short 2>/dev/null)" ]; then
    exit 0
fi

# Ahead of origin/main?
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || exit 0
[ -n "$upstream" ] || exit 0
ahead=$(git rev-list --count "$upstream..HEAD" 2>/dev/null || echo 0)
[ "$ahead" -gt 0 ] || exit 0

# Recent local-ci pass?
[ -f "$STAMP" ] || exit 0
age=$(( $(date +%s) - $(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP") ))
[ $age -lt 900 ] || exit 0

cat <<EOF

## Push nudge

Working tree is clean, HEAD is $ahead commit(s) ahead of $upstream, and
\`scripts/local-ci.sh\` passed less than 15 min ago (stamp:
\`.session-state/last-ci-pass.stamp\`).

If you've finished the current unit of work, this is the moment to:

    git push

Skip if the commits are still WIP or pushing needs coordination.
EOF

exit 0
