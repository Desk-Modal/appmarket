#!/usr/bin/env bash
# Regression coverage for scripts/audit-naming-tauri-not-decoration.sh.
# Auto-discovered by scripts/local-ci.sh --fast hooks:* gate.
# Cases: 1) clean tree → 0; 2) deprecated term → 1+file:line;
#        3) allowlist marker → 0; 4) audit's own self-reference allowlisted.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AUDIT="$ROOT_DIR/scripts/audit-naming-tauri-not-decoration.sh"
[ -x "$AUDIT" ] || { echo "FAIL: $AUDIT not executable" >&2; exit 1; }

TMP=$(mktemp -d -t dm-audit-vocab.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS: $*"; }
ko() { FAIL=$((FAIL+1)); echo "  FAIL: $*" >&2; }

# Runtime-constructed deprecated term so this file stays clean.
TERM=$(printf '\x63\x68\x72\x6f\x6d\x65')
mk() { mkdir -p "$1/platform/apps" "$1/scripts"; }

# Case 1: clean tree.
mk "$TMP/c1"; echo "// nothing offensive" >"$TMP/c1/platform/apps/Clean.tsx"
out=$(CLAUDE_PROJECT_DIR="$TMP/c1" "$AUDIT" 2>&1); rc=$?
[ "$rc" = "0" ] && ok "case 1 — clean exits 0" || ko "case 1 rc=$rc out=$out"

# Case 2: file containing deprecated term as a standalone word → flagged.
mk "$TMP/c2"; echo "// custom ${TERM} controls here" >"$TMP/c2/platform/apps/Bad.tsx"
out=$(CLAUDE_PROJECT_DIR="$TMP/c2" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "Bad.tsx:1"; then
    ok "case 2 — detected with file:line"
else
    ko "case 2 rc=$rc out=$out"
fi

# Case 3: per-line allowlist marker honoured.
mk "$TMP/c3"
echo "// legacy ${TERM}  // audit:allow-naming: historic" >"$TMP/c3/platform/apps/Marked.tsx"
out=$(CLAUDE_PROJECT_DIR="$TMP/c3" "$AUDIT" 2>&1); rc=$?
[ "$rc" = "0" ] && ok "case 3 — marker honoured" || ko "case 3 rc=$rc out=$out"

# Case 4: audit's own self-reference filename ignored.
mk "$TMP/c4"; echo "// detects ${TERM} matches" >"$TMP/c4/scripts/audit-naming-tauri-not-decoration.sh"
out=$(CLAUDE_PROJECT_DIR="$TMP/c4" "$AUDIT" 2>&1); rc=$?
[ "$rc" = "0" ] && ok "case 4 — audit self-reference allowlisted" || ko "case 4 rc=$rc out=$out"

echo ""
echo "audit-naming-tauri-not-decoration.test: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
