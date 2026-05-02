#!/usr/bin/env bash
#
# .claude/hooks/post-merge-wiki-ingest.sh
#
# Optional PostToolUse hook for `Bash(git merge*)` and
# `Bash(gh pr merge*)` (NOT yet wired — wiring is Gate F via
# Batch 3, queued in `specs/full-evolution/gate-f-queue.md`).
#
# Purpose: when a PR or branch merge lands, capture the merged-PR
# description (best-effort via `gh`) and the merge-commit metadata
# into `.session-state/wiki-ingest-log.md`. Complements
# `post-commit-wiki-ingest.sh` (which captures direct commits).
#
# Detection logic:
#   - HEAD must be a merge commit (two or more parents).
#   - Parse the merge-commit subject for "Merge pull request #<N>"
#     pattern; if found, attempt `gh pr view <N>` to fetch description.
#   - Fall back to merge-commit subject + parent SHAs.
#
# Idempotent (PPID + SHA marker). Non-blocking. Bypass via
# DESKMODAL_LAX=1.

set -u

[ "${DESKMODAL_LAX:-0}" = "1" ] && exit 0

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$ROOT_DIR" ] && exit 0

HEAD_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null)"
[ -z "$HEAD_SHA" ] && exit 0

# Merge commits have ≥2 parents.
PARENT_COUNT="$(git -C "$ROOT_DIR" log -1 --format='%P' "$HEAD_SHA" 2>/dev/null | wc -w | tr -d ' ')"
[ "$PARENT_COUNT" -lt 2 ] && exit 0

# Idempotency marker.
MARKER_DIR="/tmp/wiki-merge-ingest-${PPID}"
MARKER="${MARKER_DIR}/${HEAD_SHA}"
mkdir -p "$MARKER_DIR" 2>/dev/null || exit 0
[ -f "$MARKER" ] && exit 0
: > "$MARKER" 2>/dev/null || exit 0

# Cleanup old marker dirs.
find /tmp -maxdepth 1 -name 'wiki-merge-ingest-*' -mtime +1 -exec rm -rf {} + 2>/dev/null

SUBJECT="$(git -C "$ROOT_DIR" log -1 --format='%s' "$HEAD_SHA" 2>/dev/null)"
PARENTS="$(git -C "$ROOT_DIR" log -1 --format='%P' "$HEAD_SHA" 2>/dev/null)"
AUTHOR="$(git -C "$ROOT_DIR" log -1 --format='%an' "$HEAD_SHA" 2>/dev/null)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Parse PR number if present (GitHub merge-commit convention).
PR_NUMBER=""
if echo "$SUBJECT" | grep -qE 'Merge pull request #[0-9]+'; then
    PR_NUMBER="$(echo "$SUBJECT" | sed -nE 's/.*Merge pull request #([0-9]+).*/\1/p')"
fi

# Best-effort PR description via gh (silent on failure).
PR_DESC=""
if [ -n "$PR_NUMBER" ] && command -v gh >/dev/null 2>&1; then
    PR_DESC="$(gh pr view "$PR_NUMBER" --json body --jq '.body' 2>/dev/null | head -c 2000 || true)"
fi

# Detect wiki/ files in the merge.
WIKI_FILES="$(git -C "$ROOT_DIR" log -1 --name-only --pretty=format: "$HEAD_SHA" 2>/dev/null \
  | grep -E '^wiki/' \
  | sort -u || true)"

LOG="$ROOT_DIR/.session-state/wiki-ingest-log.md"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

if [ ! -f "$LOG" ]; then
    cat > "$LOG" <<'HEADER'
# Wiki ingest log (session-state, gitignored)

Auto-populated by `.claude/hooks/post-commit-wiki-ingest.sh` and
`.claude/hooks/post-merge-wiki-ingest.sh`. The /loop's
documentation-engineer dispatch consumes this log when authoring
durable `wiki/log.md` entries during ship cycles.

Format: one block per commit, separated by `---`.
HEADER
fi

{
    echo ""
    echo "---"
    echo ""
    echo "## ${HEAD_SHA:0:7} · $TIMESTAMP · MERGE"
    echo ""
    echo "**Subject**: $SUBJECT"
    echo "**Author**: $AUTHOR"
    echo "**Parents**: $PARENTS"
    if [ -n "$PR_NUMBER" ]; then
        echo "**PR**: #$PR_NUMBER"
    fi
    if [ -n "$WIKI_FILES" ]; then
        echo ""
        echo "**Wiki files in merge range**:"
        echo ""
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            echo "- \`$f\`"
        done <<<"$WIKI_FILES"
    fi
    if [ -n "$PR_DESC" ]; then
        echo ""
        echo "**PR description** (truncated to 2KB):"
        echo ""
        echo '```'
        echo "$PR_DESC"
        echo '```'
    fi
} >> "$LOG" 2>/dev/null || true

exit 0
