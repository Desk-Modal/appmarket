#!/usr/bin/env bash
#
# .claude/hooks/tests/audit-manifest-coverage.test.sh
#
# Regression coverage for scripts/audit-manifest-coverage.sh.
# Auto-discovered by `scripts/local-ci.sh --fast`'s hooks:* gate.
#
# Drives the audit against synthetic plugins/tradesurface/{apps,plugins}/
# trees under TMPDIR to exercise pass + fail paths deterministically.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AUDIT="$ROOT_DIR/scripts/audit-manifest-coverage.sh"

[ -x "$AUDIT" ] || { echo "FAIL: $AUDIT not executable" >&2; exit 1; }

TMP=$(mktemp -d -t dm-manifest-cov.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*" >&2; }

mk_fixture() {
    # mk_fixture <case> <manifest-body> <src-file> <src-body>
    local case="$1" manifest_body="$2" src_file="$3" src_body="$4"
    local app_dir="$TMP/$case/plugins/tradesurface/apps/widget"
    mkdir -p "$app_dir/src"
    printf '%s\n' "$manifest_body" >"$app_dir/plugin.toml"
    printf '%s\n' "$src_body" >"$app_dir/src/$src_file"
}

# ── Case 1: clean fixture — every source-side raise/listener is declared.
mk_fixture case1 '[plugin]
name = "fixture.widget"

[[apps.entries]]
appId = "deskmodal.widget"
path = "."

[apps.entries.interop.intents.raises]
"deskmodal.DoThing" = ["fdc3.instrument"]

[apps.entries.interop.intents.listensFor."deskmodal.HearThing"]
displayName = "Hear Thing"
contexts = ["fdc3.instrument"]

[apps.entries.security]
intents_raise = ["deskmodal.DoThing"]
intents_handle = ["deskmodal.HearThing"]' \
    App.tsx 'import { fdc3 } from "x";
fdc3.raiseIntent("deskmodal.DoThing", ctx);
fdc3.addIntentListener("deskmodal.HearThing", handler);'
out=$(CLAUDE_PROJECT_DIR="$TMP/case1" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$out" | grep -q "OK"; then
    pass "case 1 — clean fixture passes"
else
    fail "case 1 — expected rc=0 OK, got rc=$rc, out=$out"
fi

# ── Case 2: known-bad — raise of an undeclared intent fails.
mk_fixture case2 '[plugin]
name = "fixture.widget"

[[apps.entries]]
appId = "deskmodal.widget"
path = "."

[apps.entries.interop.intents.raises]
"deskmodal.DoThing" = ["fdc3.instrument"]

[apps.entries.security]
intents_raise = ["deskmodal.DoThing"]
intents_handle = []' \
    App.tsx 'import { fdc3 } from "x";
fdc3.raiseIntent("deskmodal.UndeclaredIntent", ctx);'
out=$(CLAUDE_PROJECT_DIR="$TMP/case2" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "deskmodal.UndeclaredIntent"; then
    pass "case 2 — undeclared raise detected (C-3/C-5/C-10 class)"
else
    fail "case 2 — expected rc=1 naming intent, got rc=$rc, out=$out"
fi

# ── Case 3: known-bad — listener for an undeclared intent fails.
mk_fixture case3 '[plugin]
name = "fixture.widget"

[[apps.entries]]
appId = "deskmodal.widget"
path = "."

[apps.entries.security]
intents_raise = []
intents_handle = []' \
    App.tsx 'import { fdc3 } from "x";
fdc3.addIntentListener("deskmodal.ListenForGhost", handler);'
out=$(CLAUDE_PROJECT_DIR="$TMP/case3" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "deskmodal.ListenForGhost"; then
    pass "case 3 — undeclared listener detected"
else
    fail "case 3 — expected rc=1 naming intent, got rc=$rc, out=$out"
fi

# ── Case 4: allowlist marker permits the call.
mk_fixture case4 '[plugin]
name = "fixture.widget"

[[apps.entries]]
appId = "deskmodal.widget"
path = "."

[apps.entries.security]
intents_raise = []
intents_handle = []' \
    App.tsx 'import { fdc3 } from "x";
// audit:allow-manifest-coverage: runtime-only diagnostic intent
fdc3.raiseIntent("deskmodal.RuntimeProbe", ctx);'
out=$(CLAUDE_PROJECT_DIR="$TMP/case4" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ]; then
    pass "case 4 — allowlist marker (line above) honoured"
else
    fail "case 4 — expected rc=0 with allowlist, got rc=$rc, out=$out"
fi

echo ""
echo "audit-manifest-coverage.test: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
