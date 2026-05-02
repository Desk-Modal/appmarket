#!/usr/bin/env bash
#
# .claude/hooks/commit-msg-wiki-trailer.sh
#
# Optional commit-msg hook (NOT wired into .claude/settings.json by
# default — wiring is a `wiki/governance/human-gates.md` Gate F change).
#
# When a commit touches any of:
#   - .claude/rules/*.md
#   - .claude/agents/*.md
#   - .specify/memory/constitution.md
#
# the linked wiki page(s) must be updated in the same commit OR the
# commit message must carry a `[wiki:not-impacted] <reason>` trailer
# (mirroring the `[adr:not-applicable]` pattern).
#
# To activate: add to `.claude/settings.json`:
#
#     {
#       "hooks": {
#         "commit-msg": [
#           {
#             "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/commit-msg-wiki-trailer.sh \"$1\""
#           }
#         ]
#       }
#     }
#
# (Plus an `.git/hooks/commit-msg` shim that invokes the harness, OR
# wire directly via Git's commit-msg hook with the same logic.)
#
# Bypass: DESKMODAL_LAX=1 in the commit environment skips the check
# and appends an audit line to .prod-check/wiki-lax-bypass.log.
#
# Exit codes: 0 = pass; 1 = block; 2 = configuration error.

set -o pipefail

MSG_FILE="${1:-}"
if [ -z "$MSG_FILE" ] || [ ! -f "$MSG_FILE" ]; then
    echo "commit-msg-wiki-trailer: COMMIT_EDITMSG path missing or unreadable: ${MSG_FILE}" >&2
    exit 2
fi

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT_DIR" ]; then
    echo "commit-msg-wiki-trailer: not inside a git repository" >&2
    exit 2
fi

# Honour the workspace-wide LAX bypass.
if [ "${DESKMODAL_LAX:-0}" = "1" ]; then
    log_dir="$ROOT_DIR/.prod-check"
    mkdir -p "$log_dir" 2>/dev/null || true
    {
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) commit-msg-wiki-trailer bypassed (DESKMODAL_LAX=1)"
    } >> "$log_dir/wiki-lax-bypass.log" 2>/dev/null || true
    exit 0
fi

# Canonical-source paths. Touching any of these triggers the trailer
# requirement. Each line is a path glob relative to repo root.
CANONICAL_GLOBS=(
    ".claude/rules/*.md"
    ".claude/agents/*.md"
    ".specify/memory/constitution.md"
)

# Get the staged file list (the actual commit content). On commit-msg
# hook invocation, the working tree may differ from the index; use the
# diff-cached against HEAD for accuracy.
staged_files() {
    git -C "$ROOT_DIR" diff --cached --name-only 2>/dev/null
}

# Detect if any canonical source is staged.
canonical_touched() {
    local touched=""
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        for glob in "${CANONICAL_GLOBS[@]}"; do
            # Translate the glob: only handle simple `<dir>/*.md` and exact paths.
            case "$f" in
                $glob)
                    touched+="$f"$'\n'
                    ;;
            esac
        done
    done < <(staged_files)
    printf '%s' "$touched"
}

# Detect if any wiki/ page is staged.
wiki_touched() {
    while IFS= read -r f; do
        case "$f" in
            wiki/*.md|wiki/*/*.md|wiki/*/*/*.md)
                return 0
                ;;
        esac
    done < <(staged_files)
    return 1
}

# Detect a `[wiki:not-impacted] <reason>` trailer with non-empty reason.
# The trailer must appear on its own line in the commit body.
has_not_impacted_trailer() {
    # Strip lines beginning with `#` (Git scissors / comments).
    grep -E '^\[wiki:not-impacted\][[:space:]]+\S' "$MSG_FILE" \
      | grep -vE '^\s*#' \
      > /dev/null 2>&1
}

CANONICAL_TOUCHED=$(canonical_touched)
if [ -z "$CANONICAL_TOUCHED" ]; then
    # No canonical source touched — nothing to enforce.
    exit 0
fi

if wiki_touched; then
    # Same-commit wiki update detected — pass.
    exit 0
fi

if has_not_impacted_trailer; then
    # Explicit opt-out with reason — pass.
    exit 0
fi

# Block.
{
    echo ""
    echo "commit-msg-wiki-trailer: BLOCKED"
    echo ""
    echo "This commit modifies canonical-source file(s):"
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        echo "  - $f"
    done <<<"$CANONICAL_TOUCHED"
    echo ""
    echo "but does NOT update any wiki/ page in the same commit, AND the"
    echo "commit message does NOT carry a '[wiki:not-impacted] <reason>'"
    echo "trailer."
    echo ""
    echo "Resolutions (choose one):"
    echo ""
    echo "  1. Stage the affected wiki page update(s) in the same commit:"
    echo "       git add wiki/<affected-page>.md"
    echo ""
    echo "  2. Add a non-empty trailer to the commit body explaining why"
    echo "     the wiki is not impacted:"
    echo ""
    echo "       [wiki:not-impacted] Typo fix in rules; no synthesis affected."
    echo ""
    echo "  3. Bypass once with DESKMODAL_LAX=1 (audit-logged to"
    echo "     .prod-check/wiki-lax-bypass.log)."
    echo ""
    echo "See wiki/CLAUDE.md §4 (the references_canonical contract)."
} >&2

exit 1
