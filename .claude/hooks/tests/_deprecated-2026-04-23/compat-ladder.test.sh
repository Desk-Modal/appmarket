#!/usr/bin/env bash
#
# Regression test for the compat-ladder scaffolding (task 014).
#
# Pins:
#   1. Shipped `specs/compat-ladder.yml` parses and declares >= 2 SDKs.
#   2. update-consumers.sh FAILs on consumer pin drift (scratch fixture).
#   3. update-consumers.sh PASSes when every consumer pin matches.
#   4. fdc3-sync.sh FAILs when tracked_version drifts from
#      FDC3_CURRENT_STABLE (dry-run mode so no `gh` side effects).
#   5. fdc3-sync.sh PASSes when tracked_version matches.
#   6. check-surface.sh BLOCKED (rc=2) when neither cargo-semver-checks
#      nor cargo-public-api is on PATH and there's nothing to audit.
#   7. sdk-surface-audit.sh (quality gate) accepts a ladder that uses
#      the `sdks:` key (task 014 shape) in addition to the older
#      `entries:` key.
#
# All scratch fixtures live under mktemp — no real repo touched.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$HERE/../../.." && pwd)"

PASS=0
FAIL=0
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# ---------------------------------------------------------------------
# Case 1: shipped ladder parses and has >= 2 sdks.
# ---------------------------------------------------------------------
if python3 -c "
import yaml, sys
d = yaml.safe_load(open('$ROOT_DIR/specs/compat-ladder.yml'))
assert 'sdks' in d, 'missing sdks key'
assert len(d['sdks']) >= 2, 'need at least 2 sdks'
assert any(s.get('name') == 'fdc3' for s in d['sdks']), 'missing fdc3 entry'
" 2>/dev/null; then
    pass "shipped ladder parses and has >= 2 sdks (incl fdc3)"
else
    fail "shipped ladder parse" "python yaml assertion failed"
fi

# ---------------------------------------------------------------------
# Helpers — build a scratch workspace with a ladder + script tree.
# ---------------------------------------------------------------------
mk_scratch() {
    local dir="$1"
    mkdir -p "$dir/scripts/compat" "$dir/specs" "$dir/plugins/fake-consumer"
    cp "$ROOT_DIR/scripts/compat/check-surface.sh"    "$dir/scripts/compat/"
    cp "$ROOT_DIR/scripts/compat/update-consumers.sh" "$dir/scripts/compat/"
    cp "$ROOT_DIR/scripts/compat/fdc3-sync.sh"        "$dir/scripts/compat/"
    chmod +x "$dir/scripts/compat/"*.sh
}

write_ladder() {
    local file="$1" sdk_ver="$2" pin_ver="$3" fdc3_ver="$4"
    cat > "$file" <<YAML
version: 1
sdks:
  - name: deskmodal-service-sdk
    language: rust
    current_version: "$sdk_ver"
    manifest_path: platform/crates/deskmodal-service-sdk/Cargo.toml
    consumers:
      - path: plugins/fake-consumer
        version_pin: "$pin_ver"
        last_updated: "2026-03-01"
  - name: fdc3
    language: protocol
    tracked_version: "$fdc3_ver"
    conformance_suite: finos/fdc3-api-bindings@$fdc3_ver
deprecations: []
YAML
}

# ---------------------------------------------------------------------
# Case 2: consumer pin drift → update-consumers FAIL.
# ---------------------------------------------------------------------
scratch="$tmpdir/case2"
mk_scratch "$scratch"
write_ladder "$scratch/specs/compat-ladder.yml" "0.3.0" "0.1.0" "2.2.0"
out=$(bash "$scratch/scripts/compat/update-consumers.sh" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "FAIL"; then
    pass "update-consumers FAIL on pin drift"
else
    fail "update-consumers drift" "rc=$rc out=$out"
fi

# ---------------------------------------------------------------------
# Case 3: matching pins → update-consumers PASS.
# ---------------------------------------------------------------------
scratch="$tmpdir/case3"
mk_scratch "$scratch"
write_ladder "$scratch/specs/compat-ladder.yml" "0.3.0" "0.3.0" "2.2.0"
out=$(bash "$scratch/scripts/compat/update-consumers.sh" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q "FAIL"; then
    pass "update-consumers PASS when pins match"
else
    fail "update-consumers match" "rc=$rc out=$out"
fi

# ---------------------------------------------------------------------
# Case 4: FDC3 tracked_version drift → fdc3-sync FAIL (dry-run).
# ---------------------------------------------------------------------
scratch="$tmpdir/case4"
mk_scratch "$scratch"
write_ladder "$scratch/specs/compat-ladder.yml" "0.3.0" "0.3.0" "2.1.0"
out=$(DESKMODAL_DRY_RUN=1 FDC3_CURRENT_STABLE=2.2.0 \
    bash "$scratch/scripts/compat/fdc3-sync.sh" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "drift"; then
    pass "fdc3-sync FAIL on tracked_version drift (dry-run)"
else
    fail "fdc3-sync drift" "rc=$rc out=$out"
fi

# ---------------------------------------------------------------------
# Case 5: FDC3 tracked_version matches → fdc3-sync PASS.
# ---------------------------------------------------------------------
scratch="$tmpdir/case5"
mk_scratch "$scratch"
write_ladder "$scratch/specs/compat-ladder.yml" "0.3.0" "0.3.0" "2.2.0"
out=$(DESKMODAL_DRY_RUN=1 FDC3_CURRENT_STABLE=2.2.0 \
    bash "$scratch/scripts/compat/fdc3-sync.sh" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
    pass "fdc3-sync PASS when tracked_version matches"
else
    fail "fdc3-sync match" "rc=$rc out=$out"
fi

# ---------------------------------------------------------------------
# Case 6: check-surface BLOCKED when no audit tool is installed and
# the manifest_path isn't reachable from the scratch dir.
# We force PATH to /usr/bin:/bin so cargo-semver-checks / cargo-public-api
# binaries installed in ~/.cargo/bin are invisible.
# ---------------------------------------------------------------------
scratch="$tmpdir/case6"
mk_scratch "$scratch"
write_ladder "$scratch/specs/compat-ladder.yml" "0.1.0" "0.1.0" "2.2.0"
# The ladder declares manifest_path platform/crates/... relative to
# the scratch root. That path does NOT exist under $scratch, so
# check-surface must report BLOCKED (all SDKs unreachable).
out=$(env -i PATH=/usr/bin:/bin HOME="$scratch" \
    bash "$scratch/scripts/compat/check-surface.sh" 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then
    pass "check-surface BLOCKED when no SDK manifest is reachable"
else
    fail "check-surface BLOCKED" "rc=$rc out=$out"
fi

# ---------------------------------------------------------------------
# Case 7: sdk-surface-audit (quality gate) accepts `sdks:` key.
# Build a scratch git repo where we touch an SDK src/lib.rs and
# ship a ladder using the task-014 shape. The gate must accept
# the ladder (rc=0 because `sdks:` has entries).
# ---------------------------------------------------------------------
scratch="$tmpdir/case7"
mkdir -p "$scratch/scripts/quality-gates/lib"
mkdir -p "$scratch/platform/crates/deskmodal-service-sdk/src"
mkdir -p "$scratch/specs"
cp "$ROOT_DIR/scripts/quality-gates/sdk-surface-audit.sh" "$scratch/scripts/quality-gates/"
cp "$ROOT_DIR/scripts/quality-gates/lib/common.sh"        "$scratch/scripts/quality-gates/lib/"
chmod +x "$scratch/scripts/quality-gates/sdk-surface-audit.sh"
cat > "$scratch/platform/crates/deskmodal-service-sdk/Cargo.toml" <<'TOML'
[package]
name = "deskmodal-service-sdk"
version = "0.1.0"
edition = "2021"
TOML
(
    cd "$scratch"
    git init --quiet
    git config user.email t@t
    git config user.name t
    echo 'pub fn existing() {}' > platform/crates/deskmodal-service-sdk/src/lib.rs
    cat > specs/compat-ladder.yml <<'YAML'
version: 1
sdks:
  - name: deskmodal-service-sdk
    language: rust
    current_version: "0.1.0"
deprecations: []
YAML
    git add -A && git commit -q -m "init"
    echo 'pub fn new_export() {}' >> platform/crates/deskmodal-service-sdk/src/lib.rs
    git add -A && git commit -q -m "add surface"
)
out=$(cd "$scratch" && bash scripts/quality-gates/sdk-surface-audit.sh --diff-only HEAD 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qE "accepting delta|no public-surface delta"; then
    pass "sdk-surface-audit accepts 'sdks:' key ladder (task 014 shape)"
else
    fail "sdk-surface-audit sdks key" "rc=$rc out=$out"
fi

# ---------------------------------------------------------------------
echo
printf "Passed: %d    Failed: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
