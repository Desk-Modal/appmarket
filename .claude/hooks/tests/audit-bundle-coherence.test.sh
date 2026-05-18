#!/usr/bin/env bash
#
# .claude/hooks/tests/audit-bundle-coherence.test.sh
#
# Regression coverage for scripts/audit-bundle-coherence.sh.
# Auto-discovered by `scripts/local-ci.sh --fast`'s hooks:* gate.
#
# Authority: specs/148-architecture-sota/spec.md §12.3 (F148 W3) +
#            .claude/rules/architecture.md §20 #5.
#
# The audit reads:
#   $CLAUDE_PROJECT_DIR/specs/148-architecture-sota/bundles.toml  (registry)
#   $CLAUDE_PROJECT_DIR/plugins/**/plugin.toml                    (manifests)
#
# We build synthetic registry + plugins/ trees under TMPDIR to exercise
# every failure mode declared in the audit source header.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AUDIT="$ROOT_DIR/scripts/audit-bundle-coherence.sh"

[ -x "$AUDIT" ] || { echo "FAIL: $AUDIT not executable" >&2; exit 1; }

TMP=$(mktemp -d -t dm-bundle-coherence.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*" >&2; }

# Helper: scaffold a fixture rooted at $1 with a given registry body + N
# plugin.toml files passed as "<relpath>:<contents>" args.
scaffold() {
    local root="$1"
    local registry="$2"
    shift 2
    mkdir -p "$root/specs/148-architecture-sota" "$root/plugins"
    printf '%s\n' "$registry" >"$root/specs/148-architecture-sota/bundles.toml"
    for spec in "$@"; do
        local rel="${spec%%::*}"
        local body="${spec#*::}"
        mkdir -p "$root/plugins/$(dirname "$rel")"
        printf '%s\n' "$body" >"$root/plugins/$rel"
    done
}

REGISTRY_BASE='[[bundles]]
id = "alpha-bundle"
name = "Alpha"
tier = "required"
description = "Alpha bundle"
lead_plugin = "deskmodal.alpha-lead"
members = ["deskmodal.alpha-lead", "deskmodal.alpha-helper"]

[[bundles]]
id = "beta-bundle"
name = "Beta"
tier = "optional"
description = "Beta bundle"
lead_plugin = "deskmodal.beta-lead"
members = ["deskmodal.beta-lead"]'

# ── Case 1: clean fixture — registry + 2 manifests bundle-coherent.
C1="$TMP/case1"
scaffold "$C1" "$REGISTRY_BASE" \
"alpha-lead/plugin.toml::[plugin]
id = \"deskmodal.alpha-lead\"

[bundle]
member_of = [\"alpha-bundle\"]
lead = true" \
"alpha-helper/plugin.toml::[plugin]
id = \"deskmodal.alpha-helper\"

[bundle]
member_of = [\"alpha-bundle\"]" \
"beta-lead/plugin.toml::[plugin]
id = \"deskmodal.beta-lead\"

[bundle]
member_of = [\"beta-bundle\"]
lead = true"

out=$(CLAUDE_PROJECT_DIR="$C1" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$out" | grep -q "OK"; then
    pass "case 1 — clean fixture rc=0 with OK summary"
else
    fail "case 1 — expected rc=0 OK, got rc=$rc out=$out"
fi

# ── Case 2: unknown bundle id in member_of → rc=1 (Check A).
C2="$TMP/case2"
scaffold "$C2" "$REGISTRY_BASE" \
"alpha-lead/plugin.toml::[plugin]
id = \"deskmodal.alpha-lead\"

[bundle]
member_of = [\"alpha-bundle\"]
lead = true" \
"alpha-helper/plugin.toml::[plugin]
id = \"deskmodal.alpha-helper\"

[bundle]
member_of = [\"alpha-bundle\"]" \
"orphan/plugin.toml::[plugin]
id = \"deskmodal.orphan\"

[bundle]
member_of = [\"ghost-bundle\"]" \
"beta-lead/plugin.toml::[plugin]
id = \"deskmodal.beta-lead\"

[bundle]
member_of = [\"beta-bundle\"]
lead = true"

out=$(CLAUDE_PROJECT_DIR="$C2" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "ghost-bundle"; then
    pass "case 2 — unknown bundle id detected (Check A)"
else
    fail "case 2 — expected rc=1 naming ghost-bundle, got rc=$rc out=$out"
fi

# ── Case 3: multiple plugins claim lead for same bundle → rc=1 (Check B).
C3="$TMP/case3"
scaffold "$C3" "$REGISTRY_BASE" \
"alpha-lead/plugin.toml::[plugin]
id = \"deskmodal.alpha-lead\"

[bundle]
member_of = [\"alpha-bundle\"]
lead = true" \
"alpha-imposter/plugin.toml::[plugin]
id = \"deskmodal.alpha-lead\"

[bundle]
member_of = [\"alpha-bundle\"]
lead = true" \
"beta-lead/plugin.toml::[plugin]
id = \"deskmodal.beta-lead\"

[bundle]
member_of = [\"beta-bundle\"]
lead = true"

out=$(CLAUDE_PROJECT_DIR="$C3" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "multiple plugins claim lead"; then
    pass "case 3 — duplicate lead detected (Check B)"
else
    fail "case 3 — expected rc=1 duplicate-lead, got rc=$rc out=$out"
fi

# ── Case 4: [bundle].lead = true but plugin id not lead_plugin of any
# bundle in registry → rc=1 (Check B variant — orphan lead claim).
C4="$TMP/case4"
scaffold "$C4" "$REGISTRY_BASE" \
"alpha-lead/plugin.toml::[plugin]
id = \"deskmodal.alpha-lead\"

[bundle]
member_of = [\"alpha-bundle\"]
lead = true" \
"beta-lead/plugin.toml::[plugin]
id = \"deskmodal.beta-lead\"

[bundle]
member_of = [\"beta-bundle\"]
lead = true" \
"rogue/plugin.toml::[plugin]
id = \"deskmodal.rogue\"

[bundle]
member_of = [\"alpha-bundle\"]
lead = true"

out=$(CLAUDE_PROJECT_DIR="$C4" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "not.*declared as lead_plugin"; then
    pass "case 4 — orphan lead claim detected (Check B)"
else
    fail "case 4 — expected rc=1 orphan-lead, got rc=$rc out=$out"
fi

# ── Case 5: [bundle.unlocks].partner_present references unknown plugin →
# rc=1 (Check D).
C5="$TMP/case5"
scaffold "$C5" "$REGISTRY_BASE" \
"alpha-lead/plugin.toml::[plugin]
id = \"deskmodal.alpha-lead\"

[bundle]
member_of = [\"alpha-bundle\"]
lead = true

[bundle.unlocks]
partner_present = \"deskmodal.does-not-exist\"" \
"alpha-helper/plugin.toml::[plugin]
id = \"deskmodal.alpha-helper\"

[bundle]
member_of = [\"alpha-bundle\"]" \
"beta-lead/plugin.toml::[plugin]
id = \"deskmodal.beta-lead\"

[bundle]
member_of = [\"beta-bundle\"]
lead = true"

out=$(CLAUDE_PROJECT_DIR="$C5" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "does-not-exist"; then
    pass "case 5 — unknown partner_present detected (Check D)"
else
    fail "case 5 — expected rc=1 partner-unknown, got rc=$rc out=$out"
fi

# ── Case 6: plugin.toml missing [bundle] block entirely → rc=1
# (header invariant — must opt-in explicitly, member_of = [] permitted).
C6="$TMP/case6"
scaffold "$C6" "$REGISTRY_BASE" \
"alpha-lead/plugin.toml::[plugin]
id = \"deskmodal.alpha-lead\"

[bundle]
member_of = [\"alpha-bundle\"]
lead = true" \
"alpha-helper/plugin.toml::[plugin]
id = \"deskmodal.alpha-helper\"

# No [bundle] block at all — must reject." \
"beta-lead/plugin.toml::[plugin]
id = \"deskmodal.beta-lead\"

[bundle]
member_of = [\"beta-bundle\"]
lead = true"

out=$(CLAUDE_PROJECT_DIR="$C6" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "missing \[bundle\] block"; then
    pass "case 6 — missing [bundle] block detected"
else
    fail "case 6 — expected rc=1 missing-bundle-block, got rc=$rc out=$out"
fi

# ── Case 7: current repo HEAD state — audit rc=0 against real tree.
# This is the BLOCKING-promotion smoke test: if landed manifests drift,
# the test surfaces it before local-ci.sh --fast does.
out=$("$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$out" | grep -q "OK.*bundle-coherent"; then
    pass "case 7 — live repo tree bundle-coherent (rc=0)"
else
    fail "case 7 — live repo expected rc=0 OK, got rc=$rc"
fi

echo ""
echo "audit-bundle-coherence.test: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
