#!/usr/bin/env bash
#
# Regression test for scripts/quality-gates/latency-budget.sh.
#
# Pins:
#   1. --if-touched with no hot-path files touched → PASS (skipped).
#   2. Missing latency-budgets.yml → BLOCKED (exit 2).
#   3. Malformed latency-budgets.yml (missing budgets list) → FAIL.
#   4. Valid YAML with 4 budgets + clean tree → PASS when no bench
#      outputs exist (criterion not run yet is not a failure unless
#      --full with a hot path touched; in --if-touched nothing touched
#      short-circuits first).
#   5. (B9 regression — cycle-1 fix) --full with valid YAML + ALL
#      declared bench files MISSING on disk → BLOCKED (exit 2). The
#      outer BLOC triggers via sys.exit(3) on missing_bench_for_touched,
#      not silent-PASS. Proves "zero measurements across all budgets
#      must not silently pass".
#   6. (H11 regression — cycle-2 fix) --full with valid YAML + one
#      bench file PRESENT but its criterion run produces NO
#      estimates.json (empty bench harness `fn main() {}` with
#      harness=false) → BLOCKED (exit 2). Proves "per-budget
#      silent-skip must not silently pass either".
#
# Cases 1-4 do not require cargo. Cases 5-6 need cargo on PATH; case 6
# additionally requires the ability to compile a tiny crate. Cases
# that need cargo auto-skip with a SKIP line when the toolchain is
# unavailable — the end-to-end path is covered by local-ci --full in
# CI either way.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../../../scripts/quality-gates/latency-budget.sh"
REAL_BUDGETS="$HERE/../../../specs/latency-budgets.yml"
REAL_SCHEMA="$HERE/../../../specs/schemas/latency-budgets.schema.json"

PASS=0
FAIL=0
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

mk_repo() {
    local tmp
    tmp=$(mktemp -d)
    (
        cd "$tmp" || exit 1
        git init --quiet
        git config user.email "t@t"
        git config user.name "t"
        mkdir -p scripts/quality-gates/lib specs/schemas
        cp "$GATE" scripts/quality-gates/latency-budget.sh
        cp "$(dirname "$GATE")/lib/common.sh" scripts/quality-gates/lib/common.sh
        chmod +x scripts/quality-gates/latency-budget.sh
        echo "# placeholder" >README.md
        git add . && git commit -q -m "init"
    )
    echo "$tmp"
}

# 1. if-touched with no hot-path files touched → PASS
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    cp "$REAL_BUDGETS" specs/latency-budgets.yml
    cp "$REAL_SCHEMA" specs/schemas/latency-budgets.schema.json
    git add -A && git commit -q -m "add budgets"
    # Change an unrelated file (README only).
    echo "more" >>README.md
    git add README.md && git commit -q -m "docs update"
    bash scripts/quality-gates/latency-budget.sh --if-touched HEAD
) >/tmp/qg-lat-1-$$.out 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -q "skipped" /tmp/qg-lat-1-$$.out; then
    pass "if-touched without hot-path change skips"
else
    fail "if-touched without hot-path change skips" "rc=$rc out=$(cat /tmp/qg-lat-1-$$.out)"
fi
rm -rf "$repo" /tmp/qg-lat-1-$$.out

# 2. Missing latency-budgets.yml → BLOCKED (rc=2)
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    bash scripts/quality-gates/latency-budget.sh --full
) >/tmp/qg-lat-2-$$.out 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then
    pass "missing budgets.yml → BLOCKED"
else
    fail "missing budgets.yml → BLOCKED" "rc=$rc out=$(cat /tmp/qg-lat-2-$$.out)"
fi
rm -rf "$repo" /tmp/qg-lat-2-$$.out

# 3. Malformed YAML (missing budgets list)
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    cat >specs/latency-budgets.yml <<'YML'
version: 1
# no budgets field!
YML
    git add -A && git commit -q -m "bad yaml"
    bash scripts/quality-gates/latency-budget.sh --full
) >/tmp/qg-lat-3-$$.out 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then
    pass "malformed yaml → FAIL"
else
    fail "malformed yaml → FAIL" "rc=$rc out=$(cat /tmp/qg-lat-3-$$.out)"
fi
rm -rf "$repo" /tmp/qg-lat-3-$$.out

# 4. Well-formed, clean tree, if-touched → PASS (no changes since
#    last commit match benches, so skipped)
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    cp "$REAL_BUDGETS" specs/latency-budgets.yml
    cp "$REAL_SCHEMA" specs/schemas/latency-budgets.schema.json
    git add -A && git commit -q -m "budgets in"
    bash scripts/quality-gates/latency-budget.sh --if-touched HEAD
) >/tmp/qg-lat-4-$$.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "well-formed + clean tree → PASS"
else
    fail "well-formed + clean tree → PASS" "rc=$rc out=$(cat /tmp/qg-lat-4-$$.out)"
fi
rm -rf "$repo" /tmp/qg-lat-4-$$.out

# 5. (B9 regression) --full with valid YAML but ALL declared bench
#    files missing on disk → BLOCKED (rc=2). The YAML points at
#    platform/crates/.../*.rs bench files that don't exist in the
#    scratch repo, so every budget hits the missing-bench BLOC path
#    and sys.exit(3) rolls up to outer exit 2.
if ! command -v cargo >/dev/null 2>&1; then
    printf "  skip: --full with all benches missing (cargo not on PATH)\n"
else
    repo=$(mk_repo)
    (
        cd "$repo" || exit 1
        cp "$REAL_BUDGETS" specs/latency-budgets.yml
        cp "$REAL_SCHEMA" specs/schemas/latency-budgets.schema.json
        git add -A && git commit -q -m "budgets, no benches"
        bash scripts/quality-gates/latency-budget.sh --full
    ) >/tmp/qg-lat-5-$$.out 2>&1
    rc=$?
    # Expect BLOC (exit 2) and a "bench file declared ... does not exist"
    # diagnostic — proves we didn't silently PASS despite zero measurements.
    if [ "$rc" -eq 2 ] && grep -q "budget unenforceable" /tmp/qg-lat-5-$$.out \
            && grep -q "does not exist" /tmp/qg-lat-5-$$.out; then
        pass "--full with all benches missing → BLOCKED (B9 regression)"
    else
        fail "--full with all benches missing → BLOCKED (B9 regression)" \
             "rc=$rc out=$(cat /tmp/qg-lat-5-$$.out)"
    fi
    rm -rf "$repo" /tmp/qg-lat-5-$$.out
fi

# 6. (H11 regression) --full with valid YAML + one bench file PRESENT
#    but its criterion harness is an empty `fn main() {}` with
#    harness=false — cargo bench exits 0 but no estimates.json is
#    written. Per-budget silent-skip must route to BLOC, not PASS.
#
#    Construction: build a minimal cargo workspace with a single crate
#    "fakebench" containing a `benches/noop.rs` whose harness is a
#    custom empty main. Write a budgets.yml with 4 entries — one
#    pointing at this real bench, three pointing at nonexistent paths.
#    All 4 will BLOC (3 for missing, 1 for empty-harness), and the
#    H11-specific diagnostic must appear for the empty-harness case.
if ! command -v cargo >/dev/null 2>&1; then
    printf "  skip: --full with empty bench harness (cargo not on PATH)\n"
else
    repo=$(mk_repo)
    (
        cd "$repo" || exit 1

        # Minimal Cargo workspace with one crate that has a no-op bench.
        mkdir -p crates/fakebench/benches crates/fakebench/src
        cat >Cargo.toml <<'TOML'
[workspace]
resolver = "2"
members = ["crates/fakebench"]
TOML
        cat >crates/fakebench/Cargo.toml <<'TOML'
[package]
name = "fakebench"
version = "0.0.0"
edition = "2021"

[lib]
path = "src/lib.rs"

[[bench]]
name = "noop"
harness = false
path = "benches/noop.rs"
TOML
        printf "// empty\n" >crates/fakebench/src/lib.rs
        # Empty harness: exits 0, writes nothing to target/criterion.
        printf "fn main() {}\n" >crates/fakebench/benches/noop.rs

        # Budgets: one real bench pointing at our no-op, three
        # deliberately-missing paths so the gate still sees the
        # minimum 4-budget count.
        cat >specs/latency-budgets.yml <<'YML'
version: 1
budgets:
  - path: "fake::noop"
    description: "empty bench harness — H11 regression"
    p99_us: 1000
    benchmark: crates/fakebench/benches/noop.rs
  - path: "fake::missing_a"
    description: "placeholder to meet min budget count"
    p99_us: 1000
    benchmark: crates/nonexistent_a/benches/missing.rs
  - path: "fake::missing_b"
    description: "placeholder to meet min budget count"
    p99_us: 1000
    benchmark: crates/nonexistent_b/benches/missing.rs
  - path: "fake::missing_c"
    description: "placeholder to meet min budget count"
    p99_us: 1000
    benchmark: crates/nonexistent_c/benches/missing.rs
YML
        # Provide a permissive schema so validation doesn't trip.
        cp "$REAL_SCHEMA" specs/schemas/latency-budgets.schema.json

        git add -A && git commit -q -m "fakebench workspace + h11 budgets"

        bash scripts/quality-gates/latency-budget.sh --full
    ) >/tmp/qg-lat-6-$$.out 2>&1
    rc=$?
    # Expect BLOC (exit 2) AND the H11-specific per-budget diagnostic
    # for the empty-harness case: either "no criterion estimates_dir"
    # or "no estimates.json" — whichever branch criterion lands in for
    # a no-op harness on this host.
    if [ "$rc" -eq 2 ] \
            && grep -q "fake::noop" /tmp/qg-lat-6-$$.out \
            && grep -qE "no criterion estimates_dir|no estimates.json" \
                /tmp/qg-lat-6-$$.out; then
        pass "--full with empty bench harness → BLOCKED (H11 regression)"
    else
        fail "--full with empty bench harness → BLOCKED (H11 regression)" \
             "rc=$rc out=$(cat /tmp/qg-lat-6-$$.out)"
    fi
    rm -rf "$repo" /tmp/qg-lat-6-$$.out
fi

echo
printf "Passed: %d    Failed: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
