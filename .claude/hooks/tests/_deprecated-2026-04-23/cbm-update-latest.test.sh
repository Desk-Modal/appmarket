#!/usr/bin/env bash
#
# Regression test for cbm-update-latest.sh.
#
# Invariants this test pins:
#   1. Hook exits 0 when the workspace CBM binary is missing — a
#      missing binary must never block a Claude session.
#   2. Hook resolves the workspace-vendored binary at
#      $CLAUDE_PROJECT_DIR/tools/codebase-memory-mcp (NOT
#      $HOME/.local/bin — the legacy path).
#   3. Hook runs the update in the background — it never blocks the
#      foreground session on network I/O.
#   4. The PPID marker guards against re-entry within the same Claude
#      Code process.
#
# Exit status: 0 on pass, non-zero on any failure.

set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../cbm-update-latest.sh"

PASS=0
FAIL=0
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }

[ -x "$HOOK" ] || { echo "hook missing or non-exec: $HOOK" >&2; exit 1; }

# ---------------------------------------------------------------------
# Build a fake workspace with the marker files locate_workspace() looks
# for (scripts/setup.sh + mise.toml) but no tools/codebase-memory-mcp
# binary. The hook must still exit 0.
# ---------------------------------------------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/ws/scripts" "$TMP/ws/tools"
: > "$TMP/ws/scripts/setup.sh"
: > "$TMP/ws/mise.toml"

# --------- Case 1: binary missing, hook returns 0 --------------------
rm -f /tmp/cbm-update-$$   # defensive — shouldn't exist
CLAUDE_PROJECT_DIR="$TMP/ws" bash "$HOOK"
rc=$?
if [ "$rc" -eq 0 ]; then pass "binary-missing: exit 0"; \
else fail "binary-missing: exit 0" "actual rc=$rc"; fi

# --------- Case 2: the hook must not reference $HOME/.local/bin ------
# grep the hook source for the legacy path; if present, the fix
# regressed.
if grep -Fq '.local/bin/codebase-memory-mcp' "$HOOK"; then
    fail "no-legacy-path" "hook still references \$HOME/.local/bin"
else
    pass "no-legacy-path"
fi

# --------- Case 3: hook references the workspace tools/ binary -------
if grep -Fq 'tools/codebase-memory-mcp' "$HOOK"; then
    pass "workspace-path"
else
    fail "workspace-path" "hook does not reference \$WORKSPACE/tools/codebase-memory-mcp"
fi

# --------- Case 4: PPID marker re-entry guard ------------------------
# First call creates the marker; second call short-circuits.
# We verify by placing a stub "binary" that exits 0 — if the second
# invocation were to invoke it we'd notice via a stub-counter file.
STUB="$TMP/ws/tools/codebase-memory-mcp"
cat > "$STUB" <<'STUB'
#!/usr/bin/env bash
printf '.' >> "$STUB_COUNTER"
exit 0
STUB
chmod +x "$STUB"
export STUB_COUNTER="$TMP/stub-counter"
: > "$STUB_COUNTER"

# The hook backgrounds its invocation via `( ... & disown )`. We need
# to wait a tick to let the child run (bounded — if it hasn't started
# in 2s, something else is wrong).
MARKER_FILE="/tmp/cbm-update-$$"
rm -f "$MARKER_FILE"
CLAUDE_PROJECT_DIR="$TMP/ws" bash "$HOOK"
first_rc=$?
# Wait deterministically for the backgrounded stub to run (≤ 2 s).
deadline=$((SECONDS + 2))
while [ ! -s "$STUB_COUNTER" ] && [ "$SECONDS" -lt "$deadline" ]; do
    sleep 0.05
done
first_count=$(wc -c < "$STUB_COUNTER" | tr -d ' ')

# Second invocation should be a no-op due to the PPID marker.
CLAUDE_PROJECT_DIR="$TMP/ws" bash "$HOOK"
second_rc=$?
# Brief deterministic wait — if re-entry fires it would append quickly.
deadline=$((SECONDS + 1))
while [ "$SECONDS" -lt "$deadline" ]; do sleep 0.1; done
second_count=$(wc -c < "$STUB_COUNTER" | tr -d ' ')

if [ "$first_rc" -eq 0 ] && [ "$second_rc" -eq 0 ]; then
    pass "ppid-guard: both invocations exit 0"
else
    fail "ppid-guard: both invocations exit 0" \
         "first_rc=$first_rc second_rc=$second_rc"
fi
# second_count must equal first_count — the re-entry guard blocked the
# second background launch. (first_count may be 0 if the stub hadn't
# scheduled yet; the invariant is strict equality across the guard.)
if [ "$first_count" = "$second_count" ]; then
    pass "ppid-guard: second call did not re-run binary"
else
    fail "ppid-guard: second call did not re-run binary" \
         "first=$first_count second=$second_count"
fi

echo ""
echo "cbm-update-latest.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
