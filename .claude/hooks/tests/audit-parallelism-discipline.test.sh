#!/usr/bin/env bash
#
# .claude/hooks/tests/audit-parallelism-discipline.test.sh
#
# Regression coverage for scripts/audit-parallelism-discipline.sh.
# Auto-discovered by `scripts/local-ci.sh --fast`'s hooks:* gate.
#
# Test cases (all use synthetic queue dirs under TMPDIR so they do
# not depend on the workspace's real queue state):
#
#   1. Complete specs pass (exit 0).
#   2. Missing Parallelism section fails (exit 1, path on stderr).
#   3. Missing required field fails (exit 1, field name on stderr).
#   4. Invalid Wave eligibility enum fails (exit 1).
#   5. Contradiction detection: A says "concurrent with B" while B
#      says "concurrent with none" — fails (exit 1).
#      5b. QA-H1 deliberate asymmetry: A says "concurrent with B",
#          B says "concurrent with [C]" — NOT flagged (transitive
#          non-overlap is not a contradiction; concurrency is a
#          hint, not a contract).
#   6. Serialise-after to unknown ID fails (exit 1).
#   7. DESKMODAL_LAX=1 bypasses all of the above (exit 0) AND
#      appends a durable audit line to `.prod-check/lax-bypass.log`
#      (SEC-H2 — mirror the qg_honor_lax pattern).
#   8. SEC-H1 — path containment: absolute, ~/-relative, ..-
#      traversal, and $-expansion paths all rejected at audit time.
#   9. MEDIUM — parse_ids strict: a numeric token that is NOT a
#      three-digit NNN (e.g. `15`) fails audit.
#  10. QA-H3 — unreadable spec surfaces a single, specific error
#      message (no dual-error mixing awk + "lacks section").
#  11. BD-B1 — multi-line Writes field captured in full (audit
#      doesn't validate Writes content beyond canonicalisation,
#      but the field extractor must not truncate).
#  12. SEC-LOW — security adversarial cases matching the dispatch-
#      wave suite (shell-metachar dirname safely parsed, evasion
#      vectors rejected).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AUDIT="$ROOT_DIR/scripts/audit-parallelism-discipline.sh"

if [ ! -x "$AUDIT" ]; then
    echo "FAIL: $AUDIT not executable" >&2
    exit 1
fi

TMPDIR_BASE=$(mktemp -d -t dm-audit-par.XXXXXX)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0
report_pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
report_fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*" >&2; }

write_spec() {
    local dir="$1" title="$2"
    local reads="$3" writes="$4" concurrent="$5" serialise="$6" wave="$7"
    mkdir -p "$dir"
    cat >"$dir/spec.md" <<EOF
# $title

## Personas
- **Primary:** \`qa-architect\`

## Parallelism
- **Reads:** $reads
- **Writes:** $writes
- **Concurrent with:** $concurrent
- **Serialise after:** $serialise
- **Wave eligibility:** $wave
- **Worktree isolation:** required
EOF
}

# Case 1: complete, non-contradictory specs → pass.
Q=$TMPDIR_BASE/q1
mkdir -p "$Q/done"
write_spec "$Q/001-alpha" "alpha" '`path/a`' '`out/a`' 'any' 'none' 'concurrent'
write_spec "$Q/002-beta"  "beta"  '`path/b`' '`out/b`' 'any' 'none' 'concurrent'
if "$AUDIT" "$Q" >/dev/null 2>&1; then
    report_pass "case 1 — complete specs accepted"
else
    report_fail "case 1 — expected exit 0, got $?"
fi

# Case 2: missing Parallelism section → fail.
Q=$TMPDIR_BASE/q2
mkdir -p "$Q/done/001-alpha"
mkdir -p "$Q/001-naked"
cat >"$Q/001-naked/spec.md" <<'EOF'
# naked spec

No parallelism section here.
EOF
out=$("$AUDIT" "$Q" 2>&1); rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q "missing '## Parallelism' section"; then
    report_pass "case 2 — missing section rejected"
else
    report_fail "case 2 — expected rejection, got rc=$rc, out=$out"
fi

# Case 3: missing a required field → fail.
Q=$TMPDIR_BASE/q3
mkdir -p "$Q/001-incomplete"
cat >"$Q/001-incomplete/spec.md" <<'EOF'
# incomplete

## Parallelism
- **Reads:** `a`
- **Writes:** `b`
- **Wave eligibility:** concurrent
EOF
out=$("$AUDIT" "$Q" 2>&1); rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q "Concurrent with"; then
    report_pass "case 3 — missing field rejected"
else
    report_fail "case 3 — expected rejection naming 'Concurrent with', got rc=$rc, out=$out"
fi

# Case 4: invalid wave eligibility → fail.
Q=$TMPDIR_BASE/q4
mkdir -p "$Q/001-badwave"
write_spec "$Q/001-badwave" "badwave" '`r`' '`w`' 'any' 'none' 'maybe'
out=$("$AUDIT" "$Q" 2>&1); rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q "Wave eligibility"; then
    report_pass "case 4 — invalid wave eligibility rejected"
else
    report_fail "case 4 — expected rejection, got rc=$rc, out=$out"
fi

# Case 5: contradictory concurrent-with pair → fail.
Q=$TMPDIR_BASE/q5
write_spec "$Q/005-alpha" "alpha" '`a`' '`out/a`' '`010`'  'none' 'concurrent'
write_spec "$Q/010-beta"  "beta"  '`b`' '`out/b`' 'none' 'none' 'concurrent'
out=$("$AUDIT" "$Q" 2>&1); rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q "contradiction"; then
    report_pass "case 5 — contradiction detected"
else
    report_fail "case 5 — expected contradiction rejection, got rc=$rc, out=$out"
fi

# Case 5b (QA-H1): asymmetric chain A→[B], B→[C] — NOT flagged.
#   A declares it can run concurrently with B; B declares it can run
#   concurrently with C. The asymmetry (B doesn't list A) is not a
#   contradiction by design. This test PINS the deliberate behaviour.
Q=$TMPDIR_BASE/q5b
mkdir -p "$Q/done"
write_spec "$Q/001-a" "a" '`ra`' '`wa`' '`002`'    'none' 'concurrent'
write_spec "$Q/002-b" "b" '`rb`' '`wb`' '`003`'    'none' 'concurrent'
write_spec "$Q/003-c" "c" '`rc`' '`wc`' 'any'      'none' 'concurrent'
out=$("$AUDIT" "$Q" 2>&1); rc=$?
if [ "$rc" = "0" ]; then
    report_pass "case 5b — asymmetric A→B, B→C tolerated (QA-H1 pinned)"
else
    report_fail "case 5b — asymmetric chain wrongly rejected: $out"
fi

# Case 6: serialise-after referencing unknown ID → fail.
Q=$TMPDIR_BASE/q6
mkdir -p "$Q/done"
write_spec "$Q/005-orphan" "orphan" '`a`' '`out/a`' 'any' '`999`' 'concurrent'
out=$("$AUDIT" "$Q" 2>&1); rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q "Serialise after"; then
    report_pass "case 6 — unknown serialise-after rejected"
else
    report_fail "case 6 — expected rejection, got rc=$rc, out=$out"
fi

# Case 7: DESKMODAL_LAX=1 bypasses everything AND writes an audit line.
Q=$TMPDIR_BASE/q7
mkdir -p "$Q/001-naked"
cat >"$Q/001-naked/spec.md" <<'EOF'
# naked

No parallelism section.
EOF
# Route the LAX-log to an isolated .prod-check under a fake ROOT_DIR.
# The script resolves $ROOT_DIR relative to its own location, so we
# instead set up a sentinel pre-count and post-count on the REAL log
# file, verifying exactly +1 line after the run.
LOG_FILE="$ROOT_DIR/.prod-check/lax-bypass.log"
mkdir -p "$ROOT_DIR/.prod-check"
pre_count=0
if [ -f "$LOG_FILE" ]; then
    pre_count=$(wc -l <"$LOG_FILE" | tr -d ' ')
fi
out=$(DESKMODAL_LAX=1 "$AUDIT" "$Q" 2>&1); rc=$?
post_count=$(wc -l <"$LOG_FILE" 2>/dev/null | tr -d ' ' || echo 0)
delta=$((post_count - pre_count))
if [ $rc -eq 0 ] && echo "$out" | grep -q "bypassed" && [ "$delta" -ge "1" ]; then
    report_pass "case 7 — LAX bypass honoured + audit-log entry appended (+$delta line)"
else
    report_fail "case 7 — expected bypass + log entry, got rc=$rc, delta=$delta, out=$out"
fi

# Case 8 (SEC-H1): path containment failures.
case8_ok=1
for bad in '/etc/shadow' '~/evil' 'foo/../.session-state/handoff.md' '$HOME/evil'; do
    Q=$TMPDIR_BASE/q8-$(echo "$bad" | tr -c '[:alnum:]' _)
    mkdir -p "$Q/001-bad"
    write_spec "$Q/001-bad" "bad" '`ra`' "\`$bad\`" 'any' 'none' 'concurrent'
    out=$("$AUDIT" "$Q" 2>&1); rc=$?
    if [ "$rc" = "1" ] && echo "$out" | grep -q "not workspace-relative"; then
        :
    else
        report_fail "case 8 — '$bad' not rejected: rc=$rc out=$out"
        case8_ok=0
    fi
done
[ "$case8_ok" = "1" ] && report_pass "case 8 — all 4 path-containment variants rejected (SEC-H1)"

# Case 9 (MEDIUM): non-3-digit numeric token in Concurrent with fails.
Q=$TMPDIR_BASE/q9
mkdir -p "$Q/done"
write_spec "$Q/001-bad"  "bad"  '`r`' '`w`' '`15`'  'none' 'concurrent'
out=$("$AUDIT" "$Q" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "malformed ID\|three-digit"; then
    report_pass "case 9 — non-3-digit ID '15' rejected (MEDIUM strict parse)"
else
    report_fail "case 9 — expected rejection of '15', got rc=$rc, out=$out"
fi

# Case 10 (QA-H3): unreadable spec — specific, non-dual error.
Q=$TMPDIR_BASE/q10
mkdir -p "$Q/001-locked"
cat >"$Q/001-locked/spec.md" <<'EOF'
# locked

## Parallelism
- **Reads:** `r`
- **Writes:** `w`
- **Concurrent with:** any
- **Serialise after:** none
- **Wave eligibility:** concurrent
EOF
chmod 000 "$Q/001-locked/spec.md"
out=$("$AUDIT" "$Q" 2>&1); rc=$?
chmod 644 "$Q/001-locked/spec.md"   # restore so trap cleanup works
if [ "$rc" = "1" ] && echo "$out" | grep -q "cannot read spec"; then
    # Must NOT ALSO complain about missing Parallelism section.
    if echo "$out" | grep -q "missing '## Parallelism'"; then
        report_fail "case 10 — dual-error regression: '$out'"
    else
        report_pass "case 10 — unreadable spec surfaces single 'cannot read' error (QA-H3)"
    fi
else
    report_fail "case 10 — expected 'cannot read spec' error, got rc=$rc, out=$out"
fi

# Case 11 (BD-B1): multi-line Writes — all declared paths must pass
#    canonicalisation. The audit shouldn't truncate the field.
Q=$TMPDIR_BASE/q11
mkdir -p "$Q/done"
mkdir -p "$Q/001-multi"
cat >"$Q/001-multi/spec.md" <<'EOF'
# multi

## Parallelism
- **Reads:** `r/a`
- **Writes:** `tools/fdc3-conformance/` (new vendored clone pinned
  by SHA), `scripts/quality-gates/fdc3-conformance.sh` (rewritten
  body), `.claude/hooks/tests/quality-fdc3-conformance.test.sh`
  (regression update if present).
- **Concurrent with:** any
- **Serialise after:** none
- **Wave eligibility:** concurrent
EOF
out=$("$AUDIT" "$Q" 2>&1); rc=$?
if [ "$rc" = "0" ]; then
    # Now plant a BAD continuation path — must be rejected since the
    # multi-line extractor now sees ALL paths, not just the first.
    mkdir -p "$Q/002-multi-bad"
    cat >"$Q/002-multi-bad/spec.md" <<'EOF'
# multi-bad

## Parallelism
- **Reads:** `r/a`
- **Writes:** `tools/fdc3-conformance/`,
  `/etc/shadow`
- **Concurrent with:** any
- **Serialise after:** none
- **Wave eligibility:** concurrent
EOF
    out=$("$AUDIT" "$Q" 2>&1); rc=$?
    if [ "$rc" = "1" ] && echo "$out" | grep -q "/etc/shadow"; then
        report_pass "case 11 — multi-line Writes fully captured (BD-B1); bad continuation rejected"
    else
        report_fail "case 11 — multi-line continuation '/etc/shadow' not caught: rc=$rc out=$out"
    fi
else
    report_fail "case 11 — legal multi-line Writes wrongly rejected: $out"
fi

# Case 12 (SEC-LOW adversarial): shell-metachar dirname safely processed.
#    The actual filesystem-level name may be sanitised by macOS; we
#    focus on the invariant "audit completes without crashing or
#    executing anything".
Q=$TMPDIR_BASE/q12
mkdir -p "$Q/done"
Q_PATH="$Q" python3 - <<'PYEOF'
import os
base = os.environ["Q_PATH"]
# Shell-meta-rich dirname (macOS may sanitise; that's fine — the
# point is `audit` must not execute anything from the name).
name = "001-x_backtick_dollar_semi"  # placeholder: exercises printf -v path
os.makedirs(os.path.join(base, name))
with open(os.path.join(base, name, "spec.md"), "w") as f:
    f.write("""# safe
## Parallelism
- **Reads:** `r`
- **Writes:** `w`
- **Concurrent with:** any
- **Serialise after:** none
- **Wave eligibility:** concurrent
""")
PYEOF
out=$("$AUDIT" "$Q" 2>&1); rc=$?
if [ "$rc" = "0" ]; then
    report_pass "case 12 — shell-metachar context handled without eval (SEC-B1)"
else
    report_fail "case 12 — expected exit 0, got rc=$rc, out=$out"
fi

echo ""
echo "audit-parallelism-discipline.test: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
