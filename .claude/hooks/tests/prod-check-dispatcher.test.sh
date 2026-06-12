#!/usr/bin/env bash
#
# .claude/hooks/tests/prod-check-dispatcher.test.sh
#
# Regression coverage for scripts/prod-check.sh (domain dispatcher).
# Auto-discovered by `scripts/local-ci.sh --fast`'s hooks:* gate.
#
# Scope: the CLI contract, unknown-input handling, exit-code
# propagation, legacy back-compat mirror shape, and the single-writer
# handoff guarantee. Uses fixture domain modules inside a temp
# directory so real `specs/prod-check-gates/*.sh` isn't required
# to exercise every branch.
#
# Cases (all operate on a sandboxed ROOT_DIR):
#
#   1. Unknown domain → exit 2 with an actionable error.
#   2. No args → exit 2 with usage.
#   3. `--all` + `<domain>` (mutually exclusive) → exit 2.
#   4. `--only <unknown-gate>` on a valid domain → exit 2 (QA-H1).
#   5. `--only <unknown-gate>` does NOT stale-overwrite the previous
#      run's status.json (QA-H1 regression vector).
#   6. `--all` with one PASS + one FAIL domain → exit 1; handoff
#      lists the FAILing domain; workspace.json totals accurate.
#   7. `--all` with TWO FAILing domains → ONE handoff listing BOTH
#      (INT-H2 single-writer, multi-domain aggregation).
#   8. Back-compat: `.claude/scripts/optiscript-prod-check.sh` still
#      forwards to the dispatcher with `optiscript`; the root
#      `.prod-check/status.json` it produces has NO `domain` key
#      (QA-M1 byte-exact parity).
#   9. `--all` produces root `.prod-check/status.json` mirroring the
#      optiscript domain (byte-exact, no `domain` key).
#  10. workspace.json schema fields match the documented contract
#      (INT-M3): totals.{pass,fail,blocked,skip}, domains[].{name,rc,
#      pass,fail,blocked,skip,status_path},
#      blocked_review[].{domain,gate,expected_path}.
#  11. A gate returning rc=3 → SKIP: single-domain run exits 0 (SKIP is
#      not a FAIL), per-domain status.json records skip=1 with a
#      results[] row state="SKIP" (2026-06-10 SKIP-state plumbing).
#  12. --all aggregates SKIP into workspace.json totals.skip and the
#      legacy root mirror carries a `skip` counter (internal consistency
#      with the verbatim-copied SKIP results[] rows).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/scripts/prod-check.sh"
LIB="$REPO_ROOT/scripts/lib/prod-check-lib.sh"
BACK_COMPAT="$REPO_ROOT/.claude/scripts/optiscript-prod-check.sh"

if [ ! -x "$DISPATCHER" ]; then
    chmod +x "$DISPATCHER" 2>/dev/null || {
        echo "FAIL: $DISPATCHER not executable and chmod failed" >&2
        exit 1
    }
fi

TMPDIR_BASE=$(mktemp -d -t dm-prodcheck-dispatcher.XXXXXX)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0
report_pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
report_fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*" >&2; }

# ─── Sandbox factory ───────────────────────────────────────────────────
# Builds an isolated ROOT_DIR/ scaffolding that mimics the repo layout
# the dispatcher expects: scripts/prod-check.sh, scripts/lib/prod-check-lib.sh,
# and specs/prod-check-gates/*.sh for domain modules. The dispatcher
# derives ROOT_DIR from its own path, so we drop symlinks to the real
# dispatcher and lib, and compose synthetic gate modules inside the
# sandboxed specs/prod-check-gates/.
make_sandbox() {
    local sandbox="$1"
    mkdir -p "$sandbox/scripts/lib" \
             "$sandbox/specs/prod-check-gates" \
             "$sandbox/.prod-check" \
             "$sandbox/.session-state" \
             "$sandbox/.claude/scripts"
    cp "$DISPATCHER" "$sandbox/scripts/prod-check.sh"
    cp "$LIB" "$sandbox/scripts/lib/prod-check-lib.sh"
    cp "$BACK_COMPAT" "$sandbox/.claude/scripts/optiscript-prod-check.sh"
    chmod +x "$sandbox/scripts/prod-check.sh" \
             "$sandbox/.claude/scripts/optiscript-prod-check.sh"
}

# Write a synthetic gate module.
#   $1 = sandbox root
#   $2 = domain name
#   $3 = "pass"|"fail"|"blocked"|"mix"  — the gate's behaviour
make_module() {
    local sandbox="$1" domain="$2" mode="$3"
    local f="$sandbox/specs/prod-check-gates/$domain.sh"
    case "$mode" in
        pass)
            cat >"$f" <<'EOS'
DOMAIN_TASK_DESC="synthetic pass domain"
GATES=(alpha)
FAST_SKIP=""
check_alpha() { echo "alpha ok"; return 0; }
EOS
            ;;
        fail)
            cat >"$f" <<'EOS'
DOMAIN_TASK_DESC="synthetic fail domain"
GATES=(alpha)
FAST_SKIP=""
check_alpha() { echo "alpha fail detail"; return 1; }
EOS
            ;;
        mix)
            cat >"$f" <<'EOS'
DOMAIN_TASK_DESC="synthetic mix domain"
GATES=(alpha beta gamma)
FAST_SKIP=""
check_alpha() { echo "alpha ok"; return 0; }
check_beta()  { echo "beta fail"; return 1; }
check_gamma() { echo "gamma blocked"; return 2; }
EOS
            ;;
        blocked)
            cat >"$f" <<'EOS'
DOMAIN_TASK_DESC="synthetic blocked domain"
GATES=(alpha)
FAST_SKIP=""
check_alpha() { echo "alpha blocked"; return 2; }
EOS
            ;;
        skip)
            cat >"$f" <<'EOS'
DOMAIN_TASK_DESC="synthetic skip domain"
GATES=(alpha)
FAST_SKIP=""
check_alpha() { echo "alpha N/A on this host"; return 3; }
EOS
            ;;
    esac
    chmod +x "$f"
}

# Run the sandboxed dispatcher with args and capture stdout+stderr+rc.
# ROOT_DIR is derived by the dispatcher from its own path.
dispatch() {
    local sandbox="$1"; shift
    local out rc
    out=$("$sandbox/scripts/prod-check.sh" "$@" 2>&1)
    rc=$?
    printf '%s\n' "$out"
    return $rc
}

# ─── Case 1: unknown domain → exit 2 ───────────────────────────────────
SB=$TMPDIR_BASE/c1
make_sandbox "$SB"
make_module "$SB" "alpha" "pass"
if out=$(dispatch "$SB" "bogus-domain" 2>&1); then
    report_fail "case 1 — unknown domain did not fail"
else
    rc=$?
    if [ "$rc" = "2" ] && printf '%s' "$out" | grep -qi "no module for domain"; then
        report_pass "case 1 — unknown domain → rc=2 with clear error"
    else
        report_fail "case 1 — expected rc=2 with 'no module for domain', got rc=$rc, out=$out"
    fi
fi

# ─── Case 2: no args → exit 2 ──────────────────────────────────────────
SB=$TMPDIR_BASE/c2
make_sandbox "$SB"
make_module "$SB" "alpha" "pass"
if out=$(dispatch "$SB" 2>&1); then
    report_fail "case 2 — no args did not fail"
else
    rc=$?
    if [ "$rc" = "2" ] && printf '%s' "$out" | grep -qi "must provide a domain"; then
        report_pass "case 2 — no args → rc=2 with usage hint"
    else
        report_fail "case 2 — expected rc=2 with usage, got rc=$rc, out=$out"
    fi
fi

# ─── Case 3: --all + <domain> mutually exclusive → exit 2 ──────────────
SB=$TMPDIR_BASE/c3
make_sandbox "$SB"
make_module "$SB" "alpha" "pass"
if out=$(dispatch "$SB" "--all" "alpha" 2>&1); then
    report_fail "case 3 — --all + domain did not fail"
else
    rc=$?
    if [ "$rc" = "2" ] && printf '%s' "$out" | grep -qi "mutually exclusive"; then
        report_pass "case 3 — --all + domain → rc=2 mutually exclusive"
    else
        report_fail "case 3 — expected rc=2 'mutually exclusive', got rc=$rc, out=$out"
    fi
fi

# ─── Case 4: --only <unknown-gate> → exit 2 (QA-H1) ────────────────────
SB=$TMPDIR_BASE/c4
make_sandbox "$SB"
make_module "$SB" "alpha" "pass"
if out=$(dispatch "$SB" "alpha" "--only" "nonexistent_gate" 2>&1); then
    report_fail "case 4 — unknown gate did not fail"
else
    rc=$?
    if [ "$rc" = "2" ] \
        && printf '%s' "$out" | grep -qi "not in domain 'alpha'" \
        && printf '%s' "$out" | grep -qi "valid gates:"; then
        report_pass "case 4 — --only unknown → rc=2 with valid-gate list (QA-H1)"
    else
        report_fail "case 4 — expected rc=2 with gate-list, got rc=$rc, out=$out"
    fi
fi

# ─── Case 5: --only unknown does NOT stale-overwrite status.json ───────
# (QA-H1 regression: the bad path previously dropped through to
# render_status_json with an empty RESULTS, silently corrupting the
# previous run's per-domain status file.)
SB=$TMPDIR_BASE/c5
make_sandbox "$SB"
make_module "$SB" "alpha" "pass"
# Prime a good run to produce status.json.
dispatch "$SB" "alpha" >/dev/null 2>&1
good_status="$SB/.prod-check/alpha/status.json"
if [ ! -f "$good_status" ]; then
    report_fail "case 5 — setup failed: no priming status.json"
else
    good_hash=$(python3 -c 'import sys,hashlib; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$good_status")
    dispatch "$SB" "alpha" "--only" "nonexistent_gate" >/dev/null 2>&1 || true
    if [ -f "$good_status" ]; then
        new_hash=$(python3 -c 'import sys,hashlib; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$good_status")
        if [ "$good_hash" = "$new_hash" ]; then
            report_pass "case 5 — --only unknown-gate preserved prior status.json (QA-H1)"
        else
            report_fail "case 5 — --only unknown-gate stale-overwrote status.json"
        fi
    else
        report_fail "case 5 — --only unknown-gate deleted status.json"
    fi
fi

# ─── Case 6: --all with PASS + FAIL — exit 1; workspace.json totals ────
SB=$TMPDIR_BASE/c6
make_sandbox "$SB"
make_module "$SB" "aaaa" "pass"
make_module "$SB" "zzzz" "fail"
rc=0
dispatch "$SB" "--all" >/dev/null 2>&1 || rc=$?
ws="$SB/.prod-check/workspace.json"
if [ "$rc" = "1" ] && [ -f "$ws" ]; then
    totals_fail=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["totals"]["fail"])' "$ws")
    if [ "$totals_fail" = "1" ]; then
        report_pass "case 6 — --all mixed PASS/FAIL → rc=1 with fail=1 total"
    else
        report_fail "case 6 — expected totals.fail=1, got $totals_fail"
    fi
else
    report_fail "case 6 — expected rc=1 and workspace.json, got rc=$rc"
fi

# ─── Case 7: --all TWO FAILing domains → ONE handoff listing BOTH ──────
SB=$TMPDIR_BASE/c7
make_sandbox "$SB"
make_module "$SB" "aaaa" "fail"
make_module "$SB" "zzzz" "fail"
dispatch "$SB" "--all" >/dev/null 2>&1 || true
handoff="$SB/.session-state/handoff.md"
if [ -f "$handoff" ] \
    && grep -q "domain: aaaa" "$handoff" \
    && grep -q "domain: zzzz" "$handoff"; then
    report_pass "case 7 — multi-FAIL --all → ONE handoff lists both domains (INT-H2)"
else
    report_fail "case 7 — expected handoff to list both failing domains
      contents:
$(cat "$handoff" 2>/dev/null | head -40 | sed 's/^/        /')"
fi

# ─── Case 8: back-compat wrapper → optiscript + root mirror NO domain ─
SB=$TMPDIR_BASE/c8
make_sandbox "$SB"
make_module "$SB" "optiscript" "pass"
"$SB/.claude/scripts/optiscript-prod-check.sh" >/dev/null 2>&1 || true
root_status="$SB/.prod-check/status.json"
per_status="$SB/.prod-check/optiscript/status.json"
if [ -f "$root_status" ] && [ -f "$per_status" ]; then
    # Root mirror must NOT contain the "domain" key (QA-M1 byte-parity).
    if grep -q '"domain"' "$root_status"; then
        report_fail "case 8 — root status.json leaks \"domain\" key (QA-M1)"
    else
        # Per-domain status MUST have the domain key (new shape).
        if grep -q '"domain"' "$per_status"; then
            report_pass "case 8 — back-compat: root mirror domain-stripped, per-domain retains domain (QA-M1)"
        else
            report_fail "case 8 — per-domain status.json missing \"domain\" key"
        fi
    fi
else
    report_fail "case 8 — back-compat run did not produce expected files"
fi

# ─── Case 9: --all root mirror set-equal to optiscript per-domain ──────
# Once "domain" is stripped, the root mirror .results[].name ordering
# MUST equal the per-domain file's .results[].name ordering.
SB=$TMPDIR_BASE/c9
make_sandbox "$SB"
make_module "$SB" "optiscript" "mix"
make_module "$SB" "other"      "pass"
dispatch "$SB" "--all" >/dev/null 2>&1 || true
root="$SB/.prod-check/status.json"
per="$SB/.prod-check/optiscript/status.json"
if [ -f "$root" ] && [ -f "$per" ]; then
    names_root=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(",".join(r["name"] for r in d.get("results",[])))' "$root")
    names_per=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(",".join(r["name"] for r in d.get("results",[])))' "$per")
    if [ "$names_root" = "$names_per" ]; then
        report_pass "case 9 — --all root mirror .results set-equal to optiscript per-domain"
    else
        report_fail "case 9 — .results names diverged: root=$names_root per=$names_per"
    fi
else
    report_fail "case 9 — missing root or per-domain status.json"
fi

# ─── Case 10: workspace.json schema matches documented contract (INT-M3)
SB=$TMPDIR_BASE/c10
make_sandbox "$SB"
make_module "$SB" "aaaa" "mix"
make_module "$SB" "zzzz" "blocked"
dispatch "$SB" "--all" >/dev/null 2>&1 || true
ws="$SB/.prod-check/workspace.json"
if [ ! -f "$ws" ]; then
    report_fail "case 10 — workspace.json missing"
else
    schema_ok=$(python3 - "$ws" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ok = True
# totals.{pass,fail,blocked,skip}
for k in ("pass", "fail", "blocked", "skip"):
    if k not in d.get("totals", {}) or not isinstance(d["totals"][k], int):
        ok = False
# domains[] required fields
for entry in d.get("domains", []):
    for k in ("name", "rc", "pass", "fail", "blocked", "skip", "status_path"):
        if k not in entry:
            ok = False
# blocked_review[] required fields (only when present)
for br in d.get("blocked_review", []):
    for k in ("domain", "gate", "expected_path"):
        if k not in br:
            ok = False
print("yes" if ok else "no")
PY
)
    if [ "$schema_ok" = "yes" ]; then
        report_pass "case 10 — workspace.json schema matches documented contract (INT-M3)"
    else
        report_fail "case 10 — workspace.json missing required fields"
    fi
fi

# ─── Case 11: rc=3 → SKIP (not FAIL); per-domain status.json skip=1 ─────
SB=$TMPDIR_BASE/c11
make_sandbox "$SB"
make_module "$SB" "skipdom" "skip"
rc=0
dispatch "$SB" "skipdom" >/dev/null 2>&1 || rc=$?
per="$SB/.prod-check/skipdom/status.json"
if [ "$rc" = "0" ] && [ -f "$per" ]; then
    skip_n=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("skip",-1))' "$per")
    skip_state=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("yes" if any(r.get("state")=="SKIP" for r in d.get("results",[])) else "no")' "$per")
    fail_n=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("fail",-1))' "$per")
    if [ "$skip_n" = "1" ] && [ "$skip_state" = "yes" ] && [ "$fail_n" = "0" ]; then
        report_pass "case 11 — rc=3 → SKIP: status.json skip=1, results[] state=SKIP, not a FAIL"
    else
        report_fail "case 11 — expected skip=1/SKIP-row/fail=0, got skip=$skip_n state=$skip_state fail=$fail_n rc=$rc"
    fi
else
    report_fail "case 11 — expected rc=0 (SKIP is not FAIL) and per-domain status.json, got rc=$rc"
fi

# ─── Case 12: --all aggregates SKIP; root mirror carries skip counter ──
SB=$TMPDIR_BASE/c12
make_sandbox "$SB"
make_module "$SB" "optiscript" "skip"
make_module "$SB" "other"      "pass"
dispatch "$SB" "--all" >/dev/null 2>&1 || true
ws="$SB/.prod-check/workspace.json"
root="$SB/.prod-check/status.json"
if [ -f "$ws" ] && [ -f "$root" ]; then
    ws_skip=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["totals"].get("skip",-1))' "$ws")
    # Root mirror (optiscript domain = skip mode) must carry a `skip`
    # counter for internal consistency with its verbatim SKIP results[] row.
    root_skip=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("skip",-1))' "$root")
    if [ "$ws_skip" = "1" ] && [ "$root_skip" = "1" ]; then
        report_pass "case 12 — --all: workspace totals.skip=1 + legacy mirror skip=1 (internal consistency)"
    else
        report_fail "case 12 — expected workspace skip=1 + mirror skip=1, got ws=$ws_skip mirror=$root_skip"
    fi
else
    report_fail "case 12 — missing workspace.json or root mirror"
fi

# ─── Summary ───────────────────────────────────────────────────────────
echo
echo "prod-check-dispatcher: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
