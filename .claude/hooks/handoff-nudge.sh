#!/usr/bin/env bash
#
# Stop hook — nudges the agent to write `.session-state/handoff.md`
# only in the narrow case where the session made substantial uncommitted
# changes AND no commit has happened AND no handoff exists. The old
# "every Stop" firing pattern was retired in task 002 (commit-boundary
# handoff scoping) — post-commit handoff authoring is now handled by
# `.claude/hooks/post-commit-handoff.sh` wired via
# `PostToolUse:Bash(git commit*)`. This hook is the passive safety net
# for the "session ran, did work, never committed, about to clear" case.
#
# Thresholds (all must be true to emit a nudge):
#   - >5 uncommitted file changes
#   - No commit in this session's git reflog tail (last 10 entries)
#   - Handoff file missing or >2 hours old
#
# Non-blocking: emits advisory text only.
# Wired in .claude/settings.json under hooks.Stop.

set -u

ROOT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
HANDOFF="$ROOT_DIR/.session-state/handoff.md"

# Bail fast if no git repo.
if ! command -v git >/dev/null 2>&1 || [ ! -d "$ROOT_DIR/.git" ]; then
    exit 0
fi

# >5 uncommitted file changes?
changes=$(cd "$ROOT_DIR" && git status --short 2>/dev/null | wc -l | tr -d ' ')
[ "$changes" -gt 5 ] || exit 0

# Any commit in recent reflog (proxy for "did this session commit")?
# If the last 10 reflog entries include a commit action, the session
# produced a durable checkpoint — post-commit hook handled the handoff.
recent_commit=0
if cd "$ROOT_DIR" 2>/dev/null && git reflog --format='%gs' -n 10 2>/dev/null | grep -qE '^commit'; then
    recent_commit=1
fi
[ "$recent_commit" -eq 0 ] || exit 0

# Handoff absent or >2 hours old?
stale=1
if [ -f "$HANDOFF" ]; then
    age_seconds=$(( $(date +%s) - $(stat -f %m "$HANDOFF" 2>/dev/null || stat -c %Y "$HANDOFF") ))
    if [ "$age_seconds" -lt 7200 ]; then
        stale=0
    fi
fi
[ "$stale" -eq 1 ] || exit 0

cat <<EOF

## Context-discipline nudge (rare-path safety net)

\`git status\` shows $changes uncommitted change(s), no commit in this
session's reflog, and \`.session-state/handoff.md\` is missing or
>2 hours old. Before the next /clear, either:

- Commit the work (the PostToolUse:Bash(git commit*) hook will
  auto-update the handoff), OR
- Write a handoff manually per \`.claude/rules/context-discipline.md\` §3.

Skip if this session was purely exploratory or the user is still
actively working.
EOF

exit 0
