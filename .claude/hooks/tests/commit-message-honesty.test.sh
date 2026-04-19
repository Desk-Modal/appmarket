#!/usr/bin/env bash
#
# Regression test for .claude/hooks/commit-message-honesty.sh.
#
# Pins (per specs/tasks/queue/007-commit-message-honesty-hook/spec.md
# §Acceptance):
#
#   1. "fix: tests pass"                                  → rejected (rc=1)
#   2. "fix: tests pass (see .prod-check/cargo_tests.log)" → accepted (rc=0)
#   3. "fix: tests pass — exit=0"                          → accepted (rc=0)
#   4. "fix: platform/src/main.rs:42 off-by-one"          → accepted (rc=0)
#      (no banned phrase — file:line citation present but is incidental)
#   5. "I believe this works" without citation            → rejected (rc=1)
#   6. "chore: bump version"                              → accepted (rc=0)
#   7. empty message                                      → accepted (rc=0)
#   8. DESKMODAL_LAX=1 with banned phrase                 → accepted (rc=0)
#      + advisory on stderr + lax-bypass.log entry.
#
# Additional (security-engineer lens — "auditable not foolproof"):
#   9. Case-insensitive match: "I BELIEVE" without citation → rejected.
#  10. Merge commit auto-exempt: "Merge pull request #42 from x/y"
#      with banned phrase body → accepted.
#  11. Revert commit auto-exempt: "Revert \"feat: X\"" → accepted.
#  12. Comment-only lines with banned phrase are ignored (git strips them).
#  13. URL citation form                                  → accepted.
#  14. 7-hex commit SHA citation form                     → accepted.
#  15. False-positive guard: "brought" must NOT match "ought to".
#  16. False-positive guard: "thought" must NOT match "ought to".
#  17. `it worked` (past tense) must NOT match `it works` (present).
#
# Exit 0 if every case passes; exit 1 with summary on any miss.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$HERE/../../.." && pwd)"
HOOK="$ROOT_DIR/.claude/hooks/commit-message-honesty.sh"

if [ ! -x "$HOOK" ]; then
    chmod +x "$HOOK" 2>/dev/null || true
fi
if [ ! -x "$HOOK" ]; then
    echo "FAIL: $HOOK is not executable" >&2
    exit 1
fi

PASS=0
FAIL=0
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

run_case() {
    # run_case <msg_content> <expected_rc> [env-var=value ...]
    local content="$1"; shift
    local expected="$1"; shift
    local msg="$tmpdir/msg.txt"
    printf '%s' "$content" > "$msg"
    local out rc
    # shellcheck disable=SC2086
    out=$(env -u DESKMODAL_LAX "$@" bash "$HOOK" "$msg" 2>&1)
    rc=$?
    printf '%d\t%s' "$rc" "$out"
}

# -------------------------------------------------------------------
# Case 1: banned phrase, no citation → rejected.
# -------------------------------------------------------------------
res=$(run_case "fix: tests pass" 1)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'commit-msg REJECTED'; then
    pass 'case 1: "fix: tests pass" rejected without citation'
else
    fail 'case 1' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 2: banned phrase + .prod-check/ citation → accepted.
# -------------------------------------------------------------------
res=$(run_case $'fix: tests pass (see .prod-check/cargo_tests.log)\n' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 2: banned phrase + .prod-check/ citation accepted'
else
    fail 'case 2' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 3: banned phrase + exit=0 citation → accepted.
# -------------------------------------------------------------------
res=$(run_case $'fix: tests pass — exit=0\n' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 3: banned phrase + exit=0 citation accepted'
else
    fail 'case 3' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 4: no banned phrase + file:line citation → accepted
# (verifies no false positive on ordinary fix commits with citations).
# -------------------------------------------------------------------
res=$(run_case $'fix: platform/src/main.rs:42 off-by-one\n' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 4: no banned phrase + file:line accepted'
else
    fail 'case 4' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 5: banned phrase "I believe" without citation → rejected.
# -------------------------------------------------------------------
res=$(run_case $'I believe this works\n' 1)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'commit-msg REJECTED'; then
    pass 'case 5: "I believe" without citation rejected'
else
    fail 'case 5' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 6: no banned phrase → accepted.
# -------------------------------------------------------------------
res=$(run_case $'chore: bump version\n' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 6: "chore: bump version" accepted'
else
    fail 'case 6' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 7: empty message → accepted (git rejects empty msgs itself).
# -------------------------------------------------------------------
res=$(run_case '' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 7: empty message accepted'
else
    fail 'case 7' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 8: DESKMODAL_LAX=1 with banned phrase → accepted + advisory.
# -------------------------------------------------------------------
msg="$tmpdir/msg-lax.txt"
printf 'fix: tests pass\n' > "$msg"
# Clean any prior test audit entries so we can verify a fresh append.
rm -f "$ROOT_DIR/.prod-check/lax-bypass.log" 2>/dev/null || true
out=$(DESKMODAL_LAX=1 bash "$HOOK" "$msg" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'DESKMODAL_LAX=1 honoured'; then
    if [ -f "$ROOT_DIR/.prod-check/lax-bypass.log" ] \
       && grep -q 'gate=commit-message-honesty' "$ROOT_DIR/.prod-check/lax-bypass.log"; then
        pass 'case 8: DESKMODAL_LAX=1 accepted with advisory + audit log entry'
    else
        fail 'case 8' "rc=$rc advisory present but audit log missing/incomplete — out=$out"
    fi
else
    fail 'case 8' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 9: case-insensitive banned phrase → rejected.
# -------------------------------------------------------------------
res=$(run_case $'I BELIEVE THIS FIXES IT\n' 1)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'commit-msg REJECTED'; then
    pass 'case 9: uppercase "I BELIEVE" rejected (case-insensitive match)'
else
    fail 'case 9' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 10: Merge commit auto-exempt.
# -------------------------------------------------------------------
res=$(run_case $'Merge pull request #42 from x/y\n\ntests pass\n' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 10: merge commit auto-exempt'
else
    fail 'case 10' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 11: Revert commit auto-exempt.
# -------------------------------------------------------------------
res=$(run_case $'Revert "feat: X"\n\nThis reverts commit abc1234. It works now.\n' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 11: revert commit auto-exempt'
else
    fail 'case 11' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 12: comment-only lines with banned phrase ignored (git strips).
# Real git strips these before the hook runs, but we verify we do too.
# -------------------------------------------------------------------
res=$(run_case $'chore: bump version\n\n# please enter a commit msg - tests pass\n# it works should not count\n' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 12: comment lines with banned phrases ignored'
else
    fail 'case 12' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 13: banned phrase + URL citation → accepted.
# -------------------------------------------------------------------
res=$(run_case $'fix: it works after applying https://github.com/foo/bar/pull/1\n' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 13: banned phrase + URL citation accepted'
else
    fail 'case 13' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 14: banned phrase + 7-hex commit SHA → accepted.
# -------------------------------------------------------------------
res=$(run_case $'fix: it works after reverting abc1234\n' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 14: banned phrase + commit SHA accepted'
else
    fail 'case 14' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 15: word boundary — "brought" must NOT match "ought to".
# -------------------------------------------------------------------
res=$(run_case $'chore: brought configuration into alignment\n' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 15: "brought" not false-matched to "ought to"'
else
    fail 'case 15' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 16: word boundary — "thought" must NOT match "ought to".
# -------------------------------------------------------------------
res=$(run_case $'chore: refactor per second thought\n' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 16: "thought" not false-matched to "ought to"'
else
    fail 'case 16' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 17: word boundary — past tense "worked" must not trigger "it works".
# -------------------------------------------------------------------
res=$(run_case $'chore: rework after rebase; it worked previously\n' 0)
rc="${res%%$'\t'*}"
out="${res#*$'\t'}"
if [ "$rc" -eq 0 ]; then
    pass 'case 17: past-tense "it worked" not treated as "it works"'
else
    fail 'case 17' "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Summary.
# -------------------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then
    echo "commit-message-honesty.test.sh: all $PASS cases passed."
    exit 0
else
    echo "commit-message-honesty.test.sh: $PASS passed, $FAIL FAILED." >&2
    exit 1
fi
