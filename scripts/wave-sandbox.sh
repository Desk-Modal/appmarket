#!/usr/bin/env bash
# wave-sandbox.sh — structural enforcement of wave discipline (core.md §15).
#
# Prevents the ITER-02 failure mode: impl Agents committing behind the
# orchestrator's back, resulting in partial pod landings that reference
# symbols that don't exist.
#
# Commands:
#   init <wave-id>              Snapshot HEAD + stash dirt. Writes
#                               .session-state/wave/<id>.base with the
#                               SHA. Prints WAVE_BASE to stdout.
#
#   assert-clean <wave-id>      Asserts HEAD has not moved since init.
#                               Exit 0 = clean; exit 1 = violation
#                               (someone committed during the wave).
#
#   assert-no-push <wave-id>    Asserts no push happened since init
#                               (origin/<branch> unchanged).
#
#   reconcile <wave-id> <persona> <write-set-file>
#                               Captures `git diff WAVE_BASE -- <paths>`
#                               into .session-state/wave/<id>-<persona>.patch.
#                               Paths read one-per-line from <write-set-file>.
#
#   rollback <wave-id>          git reset --hard WAVE_BASE; pop stash if
#                               any; remove .session-state/wave/<id>*
#                               (except a final rollback.log entry).
#
#   finish <wave-id>            Success path: removes wave state files.
#                               Keeps the stash only if explicitly flagged.
#
# Exit codes:
#   0  success (or clean state)
#   1  violation detected (wave must abort)
#   2  usage error
#   3  missing wave state (called out of order)

set -u

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$ROOT_DIR" ] || { echo "wave-sandbox: not in a git repo" >&2; exit 2; }

WAVE_DIR="$ROOT_DIR/.session-state/wave"
mkdir -p "$WAVE_DIR"

CMD="${1:-}"
WAVE_ID="${2:-}"
[ -n "$CMD" ] || { sed -n '2,40p' "$0"; exit 2; }
[ -n "$WAVE_ID" ] || { echo "wave-sandbox: missing <wave-id>" >&2; exit 2; }

# Sanitize wave-id — only [A-Za-z0-9_-]
case "$WAVE_ID" in
    *[!A-Za-z0-9_-]*) echo "wave-sandbox: wave-id contains invalid chars (allowed: A-Za-z0-9_-)" >&2; exit 2 ;;
esac

BASE_FILE="$WAVE_DIR/$WAVE_ID.base"
STASH_FILE="$WAVE_DIR/$WAVE_ID.stash"
BRANCH_FILE="$WAVE_DIR/$WAVE_ID.branch"

cmd_init() {
    if [ -f "$BASE_FILE" ]; then
        echo "wave-sandbox: wave '$WAVE_ID' already initialised — aborting" >&2
        exit 1
    fi
    local base
    base=$(git -C "$ROOT_DIR" rev-parse HEAD)
    echo "$base" > "$BASE_FILE"
    git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD > "$BRANCH_FILE"

    if [ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]; then
        if git -C "$ROOT_DIR" stash push -u -m "wave-sandbox-$WAVE_ID" >/dev/null 2>&1; then
            git -C "$ROOT_DIR" stash list | head -1 | cut -d: -f1 > "$STASH_FILE"
            echo "wave-sandbox: snapshotted dirt to $(cat "$STASH_FILE")" >&2
        fi
    fi
    echo "$base"
}

cmd_assert_clean() {
    [ -f "$BASE_FILE" ] || { echo "wave-sandbox: wave '$WAVE_ID' not init" >&2; exit 3; }
    local expected actual
    expected=$(cat "$BASE_FILE")
    actual=$(git -C "$ROOT_DIR" rev-parse HEAD)
    if [ "$expected" = "$actual" ]; then
        echo "wave-sandbox: HEAD unchanged ($expected)" >&2
        return 0
    fi
    echo "wave-sandbox: VIOLATION — HEAD moved during wave" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    echo "  diff:" >&2
    git -C "$ROOT_DIR" log --oneline "$expected..$actual" | sed 's/^/    /' >&2
    return 1
}

cmd_assert_no_push() {
    [ -f "$BRANCH_FILE" ] || { echo "wave-sandbox: wave '$WAVE_ID' not init" >&2; exit 3; }
    local branch
    branch=$(cat "$BRANCH_FILE")
    # Refresh remote tracking state
    git -C "$ROOT_DIR" fetch origin "$branch" >/dev/null 2>&1 || return 0
    local expected actual
    expected=$(cat "$BASE_FILE")
    actual=$(git -C "$ROOT_DIR" rev-parse "origin/$branch" 2>/dev/null) || return 0
    # If origin/branch moved beyond expected AND the new commits contain
    # HEAD-after-init, someone pushed.
    if [ "$expected" = "$actual" ]; then
        return 0
    fi
    # Only a violation if origin/branch contains commits NOT in expected
    if git -C "$ROOT_DIR" merge-base --is-ancestor "$expected" "$actual" >/dev/null 2>&1; then
        echo "wave-sandbox: VIOLATION — push occurred during wave" >&2
        git -C "$ROOT_DIR" log --oneline "$expected..$actual" | sed 's/^/    /' >&2
        return 1
    fi
    return 0
}

cmd_reconcile() {
    [ -f "$BASE_FILE" ] || { echo "wave-sandbox: wave '$WAVE_ID' not init" >&2; exit 3; }
    local persona="${3:-}"
    local write_set_file="${4:-}"
    [ -n "$persona" ] || { echo "usage: reconcile <wave-id> <persona> <write-set-file>" >&2; exit 2; }
    [ -n "$write_set_file" ] && [ -f "$write_set_file" ] || { echo "write-set file not found: $write_set_file" >&2; exit 2; }

    local base patch_file
    base=$(cat "$BASE_FILE")
    patch_file="$WAVE_DIR/$WAVE_ID-$persona.patch"

    # Build `git diff` args from write-set paths (one per line)
    local args=()
    while IFS= read -r path; do
        [ -z "$path" ] && continue
        case "$path" in \#*) continue ;; esac
        args+=("$path")
    done < "$write_set_file"

    if [ "${#args[@]}" -eq 0 ]; then
        echo "wave-sandbox: empty write-set for $persona" >&2
        exit 2
    fi

    git -C "$ROOT_DIR" diff "$base" -- "${args[@]}" > "$patch_file"
    if [ ! -s "$patch_file" ]; then
        echo "wave-sandbox: WARN — $persona produced an empty diff" >&2
    fi
    echo "$patch_file"
}

cmd_rollback() {
    [ -f "$BASE_FILE" ] || { echo "wave-sandbox: wave '$WAVE_ID' not init" >&2; exit 3; }
    local base stash_ref
    base=$(cat "$BASE_FILE")
    git -C "$ROOT_DIR" reset --hard "$base" >/dev/null 2>&1

    if [ -f "$STASH_FILE" ]; then
        stash_ref=$(cat "$STASH_FILE")
        git -C "$ROOT_DIR" stash pop "$stash_ref" >/dev/null 2>&1 && \
            echo "wave-sandbox: restored stash $stash_ref" >&2
    fi

    # Append one-line audit entry
    {
        echo "$(date -u +%FT%TZ) wave=$WAVE_ID rollback base=$base"
    } >> "$WAVE_DIR/rollback.log"

    # Remove wave state (keep rollback.log)
    rm -f "$BASE_FILE" "$STASH_FILE" "$BRANCH_FILE" "$WAVE_DIR/$WAVE_ID"*.patch 2>/dev/null
    echo "wave-sandbox: rolled back to $base" >&2
}

cmd_finish() {
    [ -f "$BASE_FILE" ] || { echo "wave-sandbox: wave '$WAVE_ID' not init" >&2; exit 3; }
    # Success path — remove wave state files (patches already consumed)
    rm -f "$BASE_FILE" "$STASH_FILE" "$BRANCH_FILE" "$WAVE_DIR/$WAVE_ID"*.patch 2>/dev/null
    echo "wave-sandbox: wave $WAVE_ID finished cleanly" >&2
}

case "$CMD" in
    init)            cmd_init ;;
    assert-clean)    cmd_assert_clean ;;
    assert-no-push)  cmd_assert_no_push ;;
    reconcile)       cmd_reconcile "$@" ;;
    rollback)        cmd_rollback ;;
    finish)          cmd_finish ;;
    *)               echo "wave-sandbox: unknown command '$CMD'" >&2; exit 2 ;;
esac
