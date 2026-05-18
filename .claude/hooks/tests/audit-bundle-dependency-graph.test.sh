#!/usr/bin/env bash
#
# .claude/hooks/tests/audit-bundle-dependency-graph.test.sh
#
# Regression coverage for scripts/audit-bundle-dependency-graph.sh.
# Auto-discovered by `scripts/local-ci.sh --fast`'s hooks:* gate.
#
# Authority: specs/148-architecture-sota/spec.md §12.4 + §14.5 W4 +
#            .claude/rules/architecture.md §27.10 (graceful degradation
#            `[dependencies]` schema) + §27.13 BLOCKING audit gates.
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
AUDIT="$ROOT_DIR/scripts/audit-bundle-dependency-graph.sh"

[ -x "$AUDIT" ] || { echo "FAIL: $AUDIT not executable" >&2; exit 1; }

TMP=$(mktemp -d -t dm-bundle-dep-graph.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*" >&2; }

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

# Registry — three bundles spanning all three tiers so tier-matrix
# enforcement can be exercised.
REGISTRY_BASE='[[bundles]]
id = "core-bundle"
name = "Core"
tier = "required"
description = "REQUIRED tier"
lead_plugin = "deskmodal.core-lead"
members = ["deskmodal.core-lead", "deskmodal.core-helper"]

[[bundles]]
id = "default-bundle"
name = "Default"
tier = "recommended"
description = "RECOMMENDED tier"
lead_plugin = "deskmodal.default-lead"
members = ["deskmodal.default-lead"]

[[bundles]]
id = "extra-bundle"
name = "Extra"
tier = "optional"
description = "OPTIONAL tier"
lead_plugin = "deskmodal.extra-lead"
members = ["deskmodal.extra-lead"]'

# ── Case 1: clean DAG — every manifest has [dependencies]; valid edges.
C1="$TMP/case1"
scaffold "$C1" "$REGISTRY_BASE" \
"core-lead/plugin.toml::[plugin]
id = \"deskmodal.core-lead\"
marketplace_tier = \"required\"

[bundle]
tier = \"required\"
member_of = [\"core-bundle\"]
lead = true

[dependencies]
required = []
recommended = []
optional = []" \
"default-lead/plugin.toml::[plugin]
id = \"deskmodal.default-lead\"
marketplace_tier = \"recommended\"

[bundle]
tier = \"recommended\"
member_of = [\"default-bundle\"]
lead = true

[dependencies]
required = [\"deskmodal.core-lead\"]
recommended = []
optional = [\"deskmodal.extra-lead\"]" \
"extra-lead/plugin.toml::[plugin]
id = \"deskmodal.extra-lead\"
marketplace_tier = \"optional\"

[bundle]
tier = \"optional\"
member_of = [\"extra-bundle\"]
lead = true

[dependencies]
required = [\"deskmodal.core-lead\"]
recommended = [\"deskmodal.default-lead\"]
optional = []"

out=$(CLAUDE_PROJECT_DIR="$C1" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$out" | grep -q "OK — dependency DAG coherent"; then
    pass "case 1 — clean DAG rc=0 with OK summary"
else
    fail "case 1 — expected rc=0 OK, got rc=$rc out=$out"
fi

# ── Case 2: cycle across `required` edges → rc=1.
C2="$TMP/case2"
scaffold "$C2" "$REGISTRY_BASE" \
"core-lead/plugin.toml::[plugin]
id = \"deskmodal.core-lead\"
[bundle]
tier = \"required\"
member_of = [\"core-bundle\"]
lead = true
[dependencies]
required = [\"deskmodal.core-helper\"]
recommended = []
optional = []" \
"core-helper/plugin.toml::[plugin]
id = \"deskmodal.core-helper\"
[bundle]
tier = \"required\"
member_of = [\"core-bundle\"]
[dependencies]
required = [\"deskmodal.core-lead\"]
recommended = []
optional = []" \
"default-lead/plugin.toml::[plugin]
id = \"deskmodal.default-lead\"
[bundle]
tier = \"recommended\"
member_of = [\"default-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []" \
"extra-lead/plugin.toml::[plugin]
id = \"deskmodal.extra-lead\"
[bundle]
tier = \"optional\"
member_of = [\"extra-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []"

out=$(CLAUDE_PROJECT_DIR="$C2" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "required-edge cycle detected"; then
    pass "case 2 — required-edge cycle detected (Check D)"
else
    fail "case 2 — expected rc=1 cycle, got rc=$rc out=$out"
fi

# ── Case 3: REQUIRED-tier consumer with `required` dep on OPTIONAL → rc=1.
C3="$TMP/case3"
scaffold "$C3" "$REGISTRY_BASE" \
"core-lead/plugin.toml::[plugin]
id = \"deskmodal.core-lead\"
[bundle]
tier = \"required\"
member_of = [\"core-bundle\"]
lead = true
[dependencies]
required = [\"deskmodal.extra-lead\"]
recommended = []
optional = []" \
"default-lead/plugin.toml::[plugin]
id = \"deskmodal.default-lead\"
[bundle]
tier = \"recommended\"
member_of = [\"default-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []" \
"extra-lead/plugin.toml::[plugin]
id = \"deskmodal.extra-lead\"
[bundle]
tier = \"optional\"
member_of = [\"extra-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []"

out=$(CLAUDE_PROJECT_DIR="$C3" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "tier violation — REQUIRED-tier"; then
    pass "case 3 — REQUIRED→OPTIONAL required dep rejected (Check C)"
else
    fail "case 3 — expected rc=1 tier-violation, got rc=$rc out=$out"
fi

# ── Case 4: `required` dep references unknown capability id → rc=1.
C4="$TMP/case4"
scaffold "$C4" "$REGISTRY_BASE" \
"core-lead/plugin.toml::[plugin]
id = \"deskmodal.core-lead\"
[bundle]
tier = \"required\"
member_of = [\"core-bundle\"]
lead = true
[dependencies]
required = [\"deskmodal.ghost-capability\"]
recommended = []
optional = []" \
"default-lead/plugin.toml::[plugin]
id = \"deskmodal.default-lead\"
[bundle]
tier = \"recommended\"
member_of = [\"default-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []" \
"extra-lead/plugin.toml::[plugin]
id = \"deskmodal.extra-lead\"
[bundle]
tier = \"optional\"
member_of = [\"extra-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []"

out=$(CLAUDE_PROJECT_DIR="$C4" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "ghost-capability"; then
    pass "case 4 — unknown capability dep detected (Check B)"
else
    fail "case 4 — expected rc=1 unknown-cap, got rc=$rc out=$out"
fi

# ── Case 5: missing [dependencies] block → rc=1 (Option B).
C5="$TMP/case5"
scaffold "$C5" "$REGISTRY_BASE" \
"core-lead/plugin.toml::[plugin]
id = \"deskmodal.core-lead\"
[bundle]
tier = \"required\"
member_of = [\"core-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []" \
"default-lead/plugin.toml::[plugin]
id = \"deskmodal.default-lead\"
[bundle]
tier = \"recommended\"
member_of = [\"default-bundle\"]
lead = true

# no [dependencies] block — Option B says rc=1." \
"extra-lead/plugin.toml::[plugin]
id = \"deskmodal.extra-lead\"
[bundle]
tier = \"optional\"
member_of = [\"extra-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []"

out=$(CLAUDE_PROJECT_DIR="$C5" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "missing \[dependencies\] block"; then
    pass "case 5 — missing [dependencies] block detected (Check A / Option B)"
else
    fail "case 5 — expected rc=1 missing-deps-block, got rc=$rc out=$out"
fi

# ── Case 6: empty [dependencies] block with all three arrays empty → rc=0.
# (All-empty is the legitimate "no cross-capability deps" declaration.)
C6="$TMP/case6"
scaffold "$C6" "$REGISTRY_BASE" \
"core-lead/plugin.toml::[plugin]
id = \"deskmodal.core-lead\"
[bundle]
tier = \"required\"
member_of = [\"core-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []" \
"default-lead/plugin.toml::[plugin]
id = \"deskmodal.default-lead\"
[bundle]
tier = \"recommended\"
member_of = [\"default-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []" \
"extra-lead/plugin.toml::[plugin]
id = \"deskmodal.extra-lead\"
[bundle]
tier = \"optional\"
member_of = [\"extra-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []"

out=$(CLAUDE_PROJECT_DIR="$C6" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$out" | grep -q "OK — dependency DAG coherent"; then
    pass "case 6 — empty [dependencies] arrays accepted (rc=0)"
else
    fail "case 6 — expected rc=0 with empty-deps OK, got rc=$rc out=$out"
fi

# ── Case 7: legacy [[dependencies]] array-of-tables shape → rc=1.
C7="$TMP/case7"
scaffold "$C7" "$REGISTRY_BASE" \
"core-lead/plugin.toml::[plugin]
id = \"deskmodal.core-lead\"
[bundle]
tier = \"required\"
member_of = [\"core-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []" \
"default-lead/plugin.toml::[plugin]
id = \"deskmodal.default-lead\"
[bundle]
tier = \"recommended\"
member_of = [\"default-bundle\"]
lead = true

[[dependencies]]
plugin = \"deskmodal.core-lead\"
version = \"*\"
reason = \"legacy semver-shape\"" \
"extra-lead/plugin.toml::[plugin]
id = \"deskmodal.extra-lead\"
[bundle]
tier = \"optional\"
member_of = [\"extra-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []"

out=$(CLAUDE_PROJECT_DIR="$C7" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "legacy \[\[dependencies\]\] array-of-tables shape"; then
    pass "case 7 — legacy [[dependencies]] array-of-tables detected"
else
    fail "case 7 — expected rc=1 legacy-array, got rc=$rc out=$out"
fi

# ── Case 8: recommended-edge cycle → rc=0 (WARN-only; graceful degradation).
C8="$TMP/case8"
scaffold "$C8" "$REGISTRY_BASE" \
"core-lead/plugin.toml::[plugin]
id = \"deskmodal.core-lead\"
[bundle]
tier = \"required\"
member_of = [\"core-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []" \
"default-lead/plugin.toml::[plugin]
id = \"deskmodal.default-lead\"
[bundle]
tier = \"recommended\"
member_of = [\"default-bundle\"]
lead = true
[dependencies]
required = []
recommended = [\"deskmodal.extra-lead\"]
optional = []" \
"extra-lead/plugin.toml::[plugin]
id = \"deskmodal.extra-lead\"
[bundle]
tier = \"optional\"
member_of = [\"extra-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = [\"deskmodal.default-lead\"]"

out=$(CLAUDE_PROJECT_DIR="$C8" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ] && echo "$out" | grep -q "soft-edge cycle"; then
    pass "case 8 — recommended/optional cycle WARN-only (rc=0)"
else
    fail "case 8 — expected rc=0 with soft-cycle WARN, got rc=$rc out=$out"
fi

# ── Case 9: dot-format DAG emitted to stderr.
C9="$TMP/case9"
scaffold "$C9" "$REGISTRY_BASE" \
"core-lead/plugin.toml::[plugin]
id = \"deskmodal.core-lead\"
[bundle]
tier = \"required\"
member_of = [\"core-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []" \
"default-lead/plugin.toml::[plugin]
id = \"deskmodal.default-lead\"
[bundle]
tier = \"recommended\"
member_of = [\"default-bundle\"]
lead = true
[dependencies]
required = [\"deskmodal.core-lead\"]
recommended = []
optional = []" \
"extra-lead/plugin.toml::[plugin]
id = \"deskmodal.extra-lead\"
[bundle]
tier = \"optional\"
member_of = [\"extra-bundle\"]
lead = true
[dependencies]
required = []
recommended = []
optional = []"

out=$(CLAUDE_PROJECT_DIR="$C9" "$AUDIT" 2>&1); rc=$?
if [ "$rc" = "0" ] \
   && echo "$out" | grep -q "digraph deskmodal_capability_dependencies" \
   && echo "$out" | grep -q '"deskmodal.default-lead" -> "deskmodal.core-lead"'; then
    pass "case 9 — graphviz dot DAG emitted on stderr"
else
    fail "case 9 — expected dot output, got rc=$rc out=$out"
fi

echo ""
echo "audit-bundle-dependency-graph.test: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
