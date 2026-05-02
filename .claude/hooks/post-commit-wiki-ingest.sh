#!/usr/bin/env bash
#
# .claude/hooks/post-commit-wiki-ingest.sh
#
# Optional PostToolUse hook for `Bash(git commit*)` (NOT yet wired —
# wiring is `wiki/governance/human-gates.md` Gate F via Batch 1).
#
# Purpose: observational audit trail. After every commit, records
# (a) the SHA, (b) the wiki/ files touched, (c) the commit subject —
# to `.session-state/wiki-ingest-log.md`. The /loop reads this log
# when authoring durable wiki/log.md entries during ship cycles.
#
# Idempotent: a PPID + SHA marker file prevents double-recording on
# repeated firings (Claude Code can fire PostToolUse multiple times
# for nested Bash invocations).
#
# Non-blocking: always exits 0. Failures are silent (this is audit,
# not enforcement).
#
# Bypass: DESKMODAL_LAX=1 in the environment skips entirely.

set -u

[ "${DESKMODAL_LAX:-0}" = "1" ] && exit 0

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$ROOT_DIR" ] && exit 0

# Only react to commits that just landed (HEAD freshly moved).
HEAD_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null)"
[ -z "$HEAD_SHA" ] && exit 0

# Idempotency marker scoped to PPID (Claude PID) + SHA.
MARKER_DIR="/tmp/wiki-ingest-${PPID}"
MARKER="${MARKER_DIR}/${HEAD_SHA}"
mkdir -p "$MARKER_DIR" 2>/dev/null || exit 0
[ -f "$MARKER" ] && exit 0
: > "$MARKER" 2>/dev/null || exit 0

# Cleanup old marker dirs (>1 day) on each invocation.
find /tmp -maxdepth 1 -name 'wiki-ingest-*' -mtime +1 -exec rm -rf {} + 2>/dev/null

# Detect wiki/ files in this commit. If none, do nothing.
WIKI_FILES="$(git -C "$ROOT_DIR" show --pretty=format: --name-only HEAD 2>/dev/null \
  | grep -E '^wiki/' \
  | sort -u || true)"

if [ -z "$WIKI_FILES" ]; then
    # Also honor [wiki:ingest <topic>] commit trailer for non-wiki commits.
    SUBJECT="$(git -C "$ROOT_DIR" log -1 --format='%s' 2>/dev/null)"
    BODY="$(git -C "$ROOT_DIR" log -1 --format='%b' 2>/dev/null)"
    if ! echo "$BODY" | grep -qE '^\[wiki:ingest\]'; then
        # No wiki impact, no opt-in trailer — skip silently.
        exit 0
    fi
fi

# Append to the session-state ingest log.
LOG="$ROOT_DIR/.session-state/wiki-ingest-log.md"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

if [ ! -f "$LOG" ]; then
    cat > "$LOG" <<'HEADER'
# Wiki ingest log (session-state, gitignored)

Auto-populated by `.claude/hooks/post-commit-wiki-ingest.sh` after
every commit that touches `wiki/**` OR carries a `[wiki:ingest]`
trailer. The /loop's documentation-engineer dispatch consumes this
log when authoring durable `wiki/log.md` entries during ship cycles.

Format: one block per commit, separated by `---`.
HEADER
fi

SUBJECT="$(git -C "$ROOT_DIR" log -1 --format='%s' 2>/dev/null)"
AUTHOR="$(git -C "$ROOT_DIR" log -1 --format='%an' 2>/dev/null)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
    echo ""
    echo "---"
    echo ""
    echo "## ${HEAD_SHA:0:7} · $TIMESTAMP"
    echo ""
    echo "**Subject**: $SUBJECT"
    echo "**Author**: $AUTHOR"
    if [ -n "$WIKI_FILES" ]; then
        echo ""
        echo "**Wiki files touched**:"
        echo ""
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            echo "- \`$f\`"
        done <<<"$WIKI_FILES"
    else
        echo ""
        echo "**Wiki ingest opt-in** via \`[wiki:ingest]\` trailer (non-wiki commit)."
    fi
} >> "$LOG" 2>/dev/null || true

exit 0
