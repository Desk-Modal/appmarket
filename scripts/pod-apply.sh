#!/usr/bin/env bash
# pod-apply.sh — atomic merge of multi-persona pod patches.
#
# Pod return contract (.claude/rules/agents.md): every impl sub-agent
# returns a unified-diff patch + verification output instead of
# committing directly. The main loop collects all returns and calls
# this script ONCE per pod to apply them atomically.
#
# Usage:
#   scripts/pod-apply.sh \
#     --patch <persona-a.patch> \
#     --patch <persona-b.patch> \
#     --patch <persona-c.patch> \
#     --verify-cmd "scripts/local-ci.sh --fast" \
#     --commit-msg "<message>" \
#     [--dry-run]
#
# Behaviour:
#   1. Snapshot working tree (git stash push -u if dirty; restore on failure).
#   2. Apply each patch with `git apply --index`. If any fails: unstash, exit 1.
#   3. Verify write-set disjointness: diff each patch, error if files overlap.
#   4. Run --verify-cmd on the integrated state. If rc != 0: unstash, exit 2.
#   5. Commit with --commit-msg. Push not performed by this script — caller pushes.
#   6. On any failure between steps 2-4: `git reset --hard HEAD` to discard
#      partial application; restore stash.
#
# Exit codes:
#   0  = pod applied + verified + committed
#   1  = patch failed to apply (or write-set overlap)
#   2  = verification failed on integrated state
#   3  = usage error

set -u

patches=()
verify_cmd=""
commit_msg=""
dry_run=0

while [ $# -gt 0 ]; do
    case "$1" in
        --patch)       patches+=("$2"); shift 2 ;;
        --verify-cmd)  verify_cmd="$2";  shift 2 ;;
        --commit-msg)  commit_msg="$2";  shift 2 ;;
        --dry-run)     dry_run=1;        shift 1 ;;
        *)             echo "unknown arg: $1" >&2; exit 3 ;;
    esac
done

[ "${#patches[@]}" -eq 0 ] && { echo "need at least one --patch" >&2; exit 3; }
[ -z "$verify_cmd" ]       && { echo "need --verify-cmd" >&2;       exit 3; }
[ -z "$commit_msg" ]       && [ "$dry_run" -eq 0 ] && { echo "need --commit-msg (unless --dry-run)" >&2; exit 3; }

for p in "${patches[@]}"; do
    [ -f "$p" ] || { echo "patch not found: $p" >&2; exit 3; }
done

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
cd "$ROOT_DIR" || exit 3

# 1. Snapshot working tree
stash_ref=""
if [ -n "$(git status --porcelain)" ]; then
    if git stash push -u -m "pod-apply-snapshot-$(date +%s)" >/dev/null 2>&1; then
        stash_ref=$(git stash list | head -1 | cut -d: -f1)
        echo "[pod-apply] snapshotted working tree to $stash_ref"
    fi
fi

restore_stash() {
    if [ -n "$stash_ref" ]; then
        git reset --hard HEAD >/dev/null 2>&1
        git stash pop "$stash_ref" >/dev/null 2>&1 && echo "[pod-apply] restored snapshot $stash_ref"
    fi
}

# 2. Check write-set disjointness across patches
tmp_sets=$(mktemp -d)
trap "rm -rf '$tmp_sets'" EXIT

i=0
for p in "${patches[@]}"; do
    grep -E '^\+\+\+ b/' "$p" | sed 's|^+++ b/||' | sort -u > "$tmp_sets/set-$i"
    i=$((i+1))
done

# Pairwise intersection check
for a in "$tmp_sets"/set-*; do
    for b in "$tmp_sets"/set-*; do
        [ "$a" = "$b" ] && continue
        [ "$a" \< "$b" ] || continue   # avoid double-check
        overlap=$(comm -12 "$a" "$b")
        if [ -n "$overlap" ]; then
            echo "[pod-apply] ERROR: write-set overlap between $(basename "$a") and $(basename "$b"):" >&2
            echo "$overlap" >&2
            restore_stash
            exit 1
        fi
    done
done

echo "[pod-apply] pairwise write-sets disjoint across ${#patches[@]} patch(es)"

# 3. Apply patches
for p in "${patches[@]}"; do
    if ! git apply --index "$p"; then
        echo "[pod-apply] ERROR: patch failed to apply: $p" >&2
        restore_stash
        exit 1
    fi
    echo "[pod-apply] applied: $p"
done

# 4. Verify integrated state
echo "[pod-apply] running verification: $verify_cmd"
if ! eval "$verify_cmd"; then
    rc=$?
    echo "[pod-apply] ERROR: verification failed (rc=$rc) on integrated state" >&2
    git reset --hard HEAD >/dev/null 2>&1
    restore_stash
    exit 2
fi

echo "[pod-apply] verification passed"

# 5. Commit (or dry-run)
if [ "$dry_run" -eq 1 ]; then
    echo "[pod-apply] --dry-run: NOT committing. Rolling back to unmodified state."
    git reset --hard HEAD >/dev/null 2>&1
    restore_stash
    exit 0
fi

git commit -m "$commit_msg" || { echo "[pod-apply] ERROR: commit failed" >&2; exit 2; }

echo "[pod-apply] committed pod at $(git rev-parse HEAD)"
echo "[pod-apply] push manually when ready: git push origin HEAD:<branch>"

# 6. Unstash if we had a snapshot
if [ -n "$stash_ref" ]; then
    echo "[pod-apply] NOTE: prior working-tree snapshot at $stash_ref — review + 'git stash pop' if you want it back"
fi

exit 0
