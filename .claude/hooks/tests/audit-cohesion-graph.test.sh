#!/usr/bin/env bash
#
# .claude/hooks/tests/audit-cohesion-graph.test.sh
#
# Regression coverage for scripts/audit-cohesion-graph.sh.
# Auto-discovered by `scripts/local-ci.sh --fast`'s hooks:* gate.
#
# The audit walks plugin.toml under $CLAUDE_PROJECT_DIR/plugins/.
# We point it at a synthetic plugins/ tree under TMPDIR to exercise
# both pass and fail paths deterministically.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AUDIT="$ROOT_DIR/scripts/audit-cohesion-graph.sh"

[ -x "$AUDIT" ] || { echo "FAIL: $AUDIT not executable" >&2; exit 1; }

TMP=$(mktemp -d -t dm-cohesion-graph.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*" >&2; }

# ── Case 1: clean fixture — every raise has a matching listener.
P1=$TMP/case1/plugins
mkdir -p "$P1/raiser" "$P1/listener"
cat >"$P1/raiser/plugin.toml" <<'EOF'
[plugin]
name = "fixture.raiser"

[apps.entries.interop.intents.raises]
"deskmodal.DoThing" = ["fdc3.instrument"]
EOF
cat >"$P1/listener/plugin.toml" <<'EOF'
[plugin]
name = "fixture.listener"

[apps.entries.interop.intents.listensFor."deskmodal.DoThing"]
displayName = "Do Thing"
contexts = ["fdc3.instrument"]
EOF
out=$(CLAUDE_PROJECT_DIR="$TMP/case1" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$out" | grep -q "OK"; then
    pass "case 1 — clean fixture passes"
else
    fail "case 1 — expected rc=0, got rc=$rc, out=$out"
fi

# ── Case 2: known-bad — raise without any listener anywhere.
P2=$TMP/case2/plugins
mkdir -p "$P2/raiser"
cat >"$P2/raiser/plugin.toml" <<'EOF'
[plugin]
name = "fixture.raiser"

[apps.entries.interop.intents.raises]
"deskmodal.NoOneListens" = ["fdc3.instrument"]
EOF
out=$(CLAUDE_PROJECT_DIR="$TMP/case2" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "deskmodal.NoOneListens"; then
    pass "case 2 — silent broadcast detected (C-4 class)"
else
    fail "case 2 — expected rc=1 naming intent, got rc=$rc, out=$out"
fi

# ── Case 3: allowlist marker permits broadcast-only intent.
P3=$TMP/case3/plugins
mkdir -p "$P3/raiser"
cat >"$P3/raiser/plugin.toml" <<'EOF'
[plugin]
name = "fixture.raiser"

[apps.entries.interop.intents.raises]
# audit:allow-cohesion-graph:broadcast-only
"deskmodal.FireAndForget" = ["fdc3.instrument"]
EOF
out=$(CLAUDE_PROJECT_DIR="$TMP/case3" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$out" | grep -q "broadcast-only allowlisted"; then
    pass "case 3 — allowlist marker honoured"
else
    fail "case 3 — expected rc=0 with allowlist, got rc=$rc, out=$out"
fi

# ── Case 4: service-side raise + service-side handle resolves.
P4=$TMP/case4/plugins
mkdir -p "$P4/svc-a" "$P4/svc-b"
cat >"$P4/svc-a/plugin.toml" <<'EOF'
[plugin]
name = "fixture.svc-a"

[services.security]
intents_raise = ["deskmodal.PublishX"]
intents_handle = []
EOF
cat >"$P4/svc-b/plugin.toml" <<'EOF'
[plugin]
name = "fixture.svc-b"

[services.security]
intents_raise = []
intents_handle = ["deskmodal.PublishX"]
EOF
out=$(CLAUDE_PROJECT_DIR="$TMP/case4" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ]; then
    pass "case 4 — service raise/handle pair resolves"
else
    fail "case 4 — expected rc=0, got rc=$rc, out=$out"
fi

echo ""
echo "audit-cohesion-graph.test: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
