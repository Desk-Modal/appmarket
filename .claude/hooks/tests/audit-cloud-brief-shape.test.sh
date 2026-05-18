#!/usr/bin/env bash
#
# .claude/hooks/tests/audit-cloud-brief-shape.test.sh
#
# Regression coverage for scripts/audit-cloud-brief-shape.sh.
# Auto-discovered by `scripts/local-ci.sh --fast`'s hooks:* gate.
#
# The audit walks $CLAUDE_PROJECT_DIR/specs/154-per-app-sota-evolution/cloud-briefs/*.md.
# We point it at synthetic brief trees under TMPDIR to exercise pass/fail paths
# deterministically per architecture.md §31.1 + §31.5.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AUDIT="$ROOT_DIR/scripts/audit-cloud-brief-shape.sh"

[ -x "$AUDIT" ] || { echo "FAIL: $AUDIT not executable" >&2; exit 1; }

TMP=$(mktemp -d -t dm-cloud-brief-shape.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*" >&2; }

make_briefs_dir() {
    local case="$1"
    local d="$TMP/$case/specs/154-per-app-sota-evolution/cloud-briefs"
    mkdir -p "$d"
    echo "$d"
}

# ── Case 1: valid brief passes ───────────────────────────────────
D1=$(make_briefs_dir case1)
cat >"$D1/valid.md" <<'EOF'
# F154 cloud-lane brief — valid

## Fresh-clone
Each firing starts from `git pull --rebase origin main`.

## Scope
ALLOWED to write:
- specs/154-per-app-sota-evolution/research/valid-<date>.md

FORBIDDEN to write:
- Any .rs / .ts / .tsx file

## Discipline
Commit + `git push origin main` on completion.
EOF
out=$(CLAUDE_PROJECT_DIR="$TMP/case1" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$out" | grep -q "OK"; then
    pass "case 1 — valid brief passes (rc=0)"
else
    fail "case 1 — expected rc=0+OK, got rc=$rc, out=$out"
fi

# ── Case 2: brief missing ## Scope section fails C2 ──────────────
D2=$(make_briefs_dir case2)
cat >"$D2/no-scope.md" <<'EOF'
# F154 cloud-lane brief — no-scope

Just research stuff.

git pull --rebase origin main
git push origin main
EOF
out=$(CLAUDE_PROJECT_DIR="$TMP/case2" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "C2-write-set-section"; then
    pass "case 2 — missing scope section flagged as C2"
else
    fail "case 2 — expected rc=1 + C2, got rc=$rc, out=$out"
fi

# ── Case 3: brief with .rs in ALLOWED fails C4 ───────────────────
D3=$(make_briefs_dir case3)
cat >"$D3/src-edit.md" <<'EOF'
# F154 cloud-lane brief — src-edit

## Fresh-clone
git pull --rebase origin main

## Scope
ALLOWED to write:
- platform/crates/agent/src/lib.rs

## Discipline
git push origin main
EOF
out=$(CLAUDE_PROJECT_DIR="$TMP/case3" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "C4-source-file-edit" && echo "$out" | grep -q "lib.rs"; then
    pass "case 3 — *.rs in ALLOWED write-set flagged as C4"
else
    fail "case 3 — expected rc=1 + C4 + lib.rs, got rc=$rc, out=$out"
fi

# ── Case 4: per-app brief with cross-app reference fails C7 ──────
D4=$(make_briefs_dir case4)
cat >"$D4/chart.md" <<'EOF'
# F154 cloud-lane brief — chart (per-app)

## Fresh-clone
git pull --rebase origin main

## Scope
ALLOWED to write:
- specs/154-per-app-sota-evolution/research/chart-<date>.md

## Mission
Propose cross-app contracts spanning watchlist + blotter.

## Discipline
git push origin main
EOF
out=$(CLAUDE_PROJECT_DIR="$TMP/case4" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "C7-cross-app-in-per-app"; then
    pass "case 4 — per-app brief with cross-app reference flagged as C7"
else
    fail "case 4 — expected rc=1 + C7, got rc=$rc, out=$out"
fi

# ── Case 5: cohesion-aggregator brief with cross-app text PASSES ──
D5=$(make_briefs_dir case5)
cat >"$D5/cohesion-aggregator.md" <<'EOF'
# F154 cloud-lane brief — cohesion-aggregator

## Fresh-clone
git pull --rebase origin main

## Scope
ALLOWED to write:
- specs/154-per-app-sota-evolution/research/cohesion-aggregate-<date>.md

## Mission
Aggregate across apps + propose cross-app contracts.

## Discipline
git push origin main
EOF
out=$(CLAUDE_PROJECT_DIR="$TMP/case5" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$out" | grep -q "OK"; then
    pass "case 5 — cohesion-aggregator exempt from C7 (cross-app permitted)"
else
    fail "case 5 — expected rc=0, got rc=$rc, out=$out"
fi

# ── Case 6: empty cloud-briefs dir is a clean SKIP (rc=0) ────────
D6=$(make_briefs_dir case6)
out=$(CLAUDE_PROJECT_DIR="$TMP/case6" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$out" | grep -q "SKIP"; then
    pass "case 6 — empty cloud-briefs/ skips cleanly (rc=0)"
else
    fail "case 6 — expected rc=0+SKIP, got rc=$rc, out=$out"
fi

echo ""
echo "audit-cloud-brief-shape.test: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
