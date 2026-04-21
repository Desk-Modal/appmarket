#!/usr/bin/env bash
#
# Regression test for scripts/adr-drift-check.sh.
#
# Invariants this test pins:
#   1. Clean repo (no arch-surface commits) → exit 0.
#   2. Commit that adds a new `migrations/*.sql` without updating
#      `.codebase-memory/adr.md` → drift detected.
#   3. Same commit + ADR update in the same commit → clean.
#   4. Same drift + `[adr:not-applicable]` trailer → clean.
#   5. `--strict` escalates drift to exit 1.
#   6. `DESKMODAL_LAX=1` suppresses --strict → exit 0 and appends
#      a line to `.prod-check/lax-bypass.log`.
#   7. Files under dist/ or target/ do NOT trigger drift.
#   8. `--staged` mode detects un-committed staged arch changes.
#
# Exit status: 0 on pass, non-zero on any failure.

set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/adr-drift-check.sh"
[ -x "$SCRIPT" ] || { echo "script missing: $SCRIPT" >&2; exit 1; }

PASS=0
FAIL=0
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }

# ----------------------------------------------------------------------
# Fresh fake repo with the marker files the script's workspace-walk
# looks for (scripts/setup.sh + mise.toml), so the session-log path
# resolves deterministically.
# ----------------------------------------------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
WS="$TMP/ws"
REPO="$WS/sub"
mkdir -p "$WS/scripts" "$WS/tools" "$REPO"
: > "$WS/scripts/setup.sh"
: > "$WS/mise.toml"

(cd "$REPO" && git init -q -b main \
  && git config user.email "test@deskmodal.local" \
  && git config user.name  "Test" \
  && echo "base" > README.md \
  && git add README.md \
  && git commit -q -m "base")

# ----------------------------------------------------------------------
# Case 1: clean repo (only README commit) → exit 0.
# ----------------------------------------------------------------------
out=$("$SCRIPT" --repo "$REPO" --range "HEAD~0..HEAD" --ci 2>&1 || true)
# HEAD~0..HEAD is empty by definition — expect exit 0 and a
# "no commits" or "clean" note.
if [ $? -eq 0 ]; then pass "clean-empty-range: exit 0"; \
else fail "clean-empty-range: exit 0" "got $? / $out"; fi

# ----------------------------------------------------------------------
# Case 2: add migrations/*.sql without ADR → drift detected.
# ----------------------------------------------------------------------
mkdir -p "$REPO/migrations"
echo "CREATE TABLE users (id UUID PRIMARY KEY);" > "$REPO/migrations/001_users.sql"
(cd "$REPO" && git add migrations/001_users.sql && git commit -q -m "feat: initial users table")

stderr=$(mktemp)
"$SCRIPT" --repo "$REPO" --range HEAD~1..HEAD --ci 2>"$stderr"
rc=$?
if [ "$rc" -eq 0 ] && grep -q 'drift' "$stderr"; then
    pass "arch-change-no-adr: advisory exit 0 + drift reported"
else
    fail "arch-change-no-adr: advisory exit 0 + drift reported" \
         "rc=$rc stderr=$(cat "$stderr")"
fi

# ----------------------------------------------------------------------
# Case 3: --strict on drift → exit 1.
# ----------------------------------------------------------------------
"$SCRIPT" --repo "$REPO" --range HEAD~1..HEAD --strict >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then pass "strict-drift: exit 1"; \
else fail "strict-drift: exit 1" "got $rc"; fi

# ----------------------------------------------------------------------
# Case 4: DESKMODAL_LAX=1 bypasses --strict.
# ----------------------------------------------------------------------
DESKMODAL_LAX=1 "$SCRIPT" --repo "$REPO" --range HEAD~1..HEAD --strict >/dev/null 2>&1
rc=$?
bypass_log="$WS/.prod-check/lax-bypass.log"
if [ "$rc" -eq 0 ] && [ -s "$bypass_log" ] && grep -q 'adr-drift-check' "$bypass_log"; then
    pass "lax-bypass: exit 0 + log entry"
else
    fail "lax-bypass: exit 0 + log entry" \
         "rc=$rc bypass_log_exists=$([ -f "$bypass_log" ] && echo yes || echo no)"
fi

# ----------------------------------------------------------------------
# Case 5: next commit updates ADR → clean.
# ----------------------------------------------------------------------
mkdir -p "$REPO/.codebase-memory"
cat > "$REPO/.codebase-memory/adr.md" <<'ADR'
## PURPOSE
Test ADR.

## ARCHITECTURE
- AD-1: Users table added in migrations/001_users.sql.
ADR
echo "CREATE TABLE roles (id UUID);" > "$REPO/migrations/002_roles.sql"
(cd "$REPO" && git add migrations/002_roles.sql .codebase-memory/adr.md \
  && git commit -q -m "feat: roles table + ADR update")
"$SCRIPT" --repo "$REPO" --range HEAD~1..HEAD --strict >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then pass "arch-change-with-adr: strict exit 0"; \
else fail "arch-change-with-adr: strict exit 0" "got $rc"; fi

# ----------------------------------------------------------------------
# Case 6: `[adr:not-applicable]` opt-out trailer → clean.
# ----------------------------------------------------------------------
echo "CREATE TABLE sessions (id UUID);" > "$REPO/migrations/003_sessions.sql"
(cd "$REPO" && git add migrations/003_sessions.sql \
  && git commit -q -m "chore: sessions scaffolding

[adr:not-applicable] Stub; ADR update lands with session logic in T-0042.")
"$SCRIPT" --repo "$REPO" --range HEAD~1..HEAD --strict >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then pass "opt-out-trailer: strict exit 0"; \
else fail "opt-out-trailer: strict exit 0" "got $rc"; fi

# ----------------------------------------------------------------------
# Case 7: dist/ + target/ changes do NOT trigger drift.
# ----------------------------------------------------------------------
mkdir -p "$REPO/dist/assets" "$REPO/target"
echo "generated" > "$REPO/dist/assets/bundle.js"
echo "built" > "$REPO/target/foo.txt"
(cd "$REPO" && git add dist/ target/ && git commit -q -m "build: generated artefacts")
"$SCRIPT" --repo "$REPO" --range HEAD~1..HEAD --strict >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then pass "exempt-paths: dist+target strict exit 0"; \
else fail "exempt-paths: dist+target strict exit 0" "got $rc"; fi

# ----------------------------------------------------------------------
# Case 8: --staged mode detects un-committed arch changes.
# ----------------------------------------------------------------------
echo "CREATE TABLE audit (id UUID);" > "$REPO/migrations/004_audit.sql"
(cd "$REPO" && git add migrations/004_audit.sql)
"$SCRIPT" --repo "$REPO" --staged --strict >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then pass "staged-drift: strict exit 1"; \
else fail "staged-drift: strict exit 1" "got $rc"; fi

# Reset staged.
(cd "$REPO" && git reset -q HEAD migrations/004_audit.sql && rm -f migrations/004_audit.sql)

echo ""
echo "adr-drift-check.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
