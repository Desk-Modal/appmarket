#!/usr/bin/env bash
#
# Regression test for scripts/audit-verify-discipline.sh.
#
# Pins (per specs/tasks/queue/015-enforce-canonical-verification-discipline/spec.md):
#   1. Known-clean workspace → exits 0.
#   2. Scratch spec with `cargo test` in Verification section → exits 1,
#      prints violation + suggestion when run with --fix-suggest.
#   3. Same spec rewritten with `scripts/local-ci.sh --full` → exits 0.
#   4. Allowlisted file containing `cargo test` → exits 0 (passthrough).
#   5. Adversarial cases (backtick-quoted, line-continuation, whitespace
#      normalisation, right-boundary non-whitespace) all fire.
#   6. Escape hatch (`<!-- audit:allow -->`) suppresses a single line.
#   7. Word-boundary: `cargo-fmt`, `some_cargo_test.sh`, `cargo` inside
#      an identifier — all PASS.
#   8. Section scoping: forbidden command OUTSIDE the Verification
#      section is ignored.
#
# Calibration: ESLint-strict / clippy-pedantic — lint rules that can't
# be silently satisfied by rewording.
#
# Exit 0 if every case passes; exit 1 with summary on any miss.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$HERE/../../.." && pwd)"
GATE="$ROOT_DIR/scripts/audit-verify-discipline.sh"

if [ ! -x "$GATE" ]; then
    echo "FAIL: $GATE is not executable" >&2
    exit 1
fi

PASS=0
FAIL=0
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# -------------------------------------------------------------------
# Case 1: clean workspace scan exits 0.
# -------------------------------------------------------------------
# We run the audit with its default target set against the CURRENT
# workspace. The whole queue has been engineered against
# .claude/rules/verification.md so this must exit 0.
out=$(bash "$GATE" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "known-clean workspace (default target set) → rc=0"
else
    fail "known-clean workspace" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 2: scratch spec with cargo test → rc=1, suggestion printed.
# -------------------------------------------------------------------
bad="$tmpdir/bad-spec.md"
printf '# Bad\n\n## Verification commands\n\n```bash\ncargo test --workspace\n```\n' > "$bad"
out=$(bash "$GATE" --fix-suggest "$bad" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden "cargo test"' && echo "$out" | grep -q 'suggest: scripts/local-ci.sh'; then
    pass "cargo test in Verification section → rc=1 with suggestion"
else
    fail "cargo test in Verification section" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 3: same spec with canonical command → rc=0.
# -------------------------------------------------------------------
good="$tmpdir/good-spec.md"
printf '# Good\n\n## Verification commands\n\n```bash\nscripts/local-ci.sh --full\n```\n' > "$good"
out=$(bash "$GATE" "$good" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "scripts/local-ci.sh --full in Verification → rc=0"
else
    fail "canonical command accepted" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 4: allowlist passthrough. We synthesise a fake ROOT_DIR layout
# so the audit sees `scripts/local-ci.sh` with cargo test inside it.
# The allowlist keys off the path relative to ROOT_DIR — so we
# replicate CLAUDE.md + scripts/ + the audit script under $tmpdir and
# invoke the audit from there. (The audit resolves its own ROOT_DIR
# from its own script path, so we symlink/copy accordingly.)
# -------------------------------------------------------------------
fakeroot="$tmpdir/fake-workspace"
mkdir -p "$fakeroot/scripts"
mkdir -p "$fakeroot/.claude/rules"
cp "$GATE" "$fakeroot/scripts/audit-verify-discipline.sh"
chmod +x "$fakeroot/scripts/audit-verify-discipline.sh"
# Minimal CLAUDE.md so ROOT_DIR detection passes.
echo "# CLAUDE.md" > "$fakeroot/CLAUDE.md"
# Allowlisted script contains a Verification commands section with
# cargo test — must be ignored because local-ci.sh is allowlisted.
cat > "$fakeroot/scripts/local-ci.sh" <<'LCI'
#!/usr/bin/env bash
# scripts/local-ci.sh (fixture) — implements the verification pipeline.

## Verification commands

cargo test --workspace
pnpm nx run @foo:build
LCI
chmod +x "$fakeroot/scripts/local-ci.sh"
out=$(bash "$fakeroot/scripts/audit-verify-discipline.sh" "$fakeroot/scripts/local-ci.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "allowlisted scripts/local-ci.sh with cargo test → rc=0 (passthrough)"
else
    fail "allowlist passthrough" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 5a: backtick-quoted command fires.
# -------------------------------------------------------------------
bt="$tmpdir/bt.md"
printf '## Verification commands\n\n- Run `cargo test --workspace`.\n' > "$bt"
out=$(bash "$GATE" "$bt" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden "cargo test"'; then
    pass "backtick-quoted cargo test fires"
else
    fail "backtick fires" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 5b: line continuation fires.
# -------------------------------------------------------------------
cont="$tmpdir/cont.md"
printf '%s\n' "## Verification commands" "" "cargo \\" "    test --workspace" > "$cont"
out=$(bash "$GATE" "$cont" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden "cargo'; then
    pass "line-continuation cargo \\<newline>test fires"
else
    fail "line-continuation" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 5c: pnpm nx build fires.
# -------------------------------------------------------------------
nx="$tmpdir/nx.md"
printf '## Verification commands\n\npnpm nx run @deskmodal/app-chart:build\n' > "$nx"
out=$(bash "$GATE" "$nx" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden "pnpm nx run"'; then
    pass "pnpm nx run fires"
else
    fail "pnpm nx run" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 5d: running target/DeskModal directly fires.
# -------------------------------------------------------------------
tgt="$tmpdir/tgt.md"
printf '## Verification commands\n\n./target/debug/DeskModal\n' > "$tgt"
out=$(bash "$GATE" "$tgt" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden ".*target/debug/DeskModal"'; then
    pass "./target/debug/DeskModal direct run fires"
else
    fail "target/DeskModal" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 5e: npx vitest direct invocation fires.
# -------------------------------------------------------------------
npx="$tmpdir/npx.md"
printf '## Verification commands\n\nnpx vitest run\n' > "$npx"
out=$(bash "$GATE" "$npx" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden "npx vitest"'; then
    pass "npx vitest fires"
else
    fail "npx vitest" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 6: JUSTIFIED escape hatch form `<!-- audit:allow: <reason> -->`
# at column 0 suppresses the line AND appends an audit log entry
# (H-sec-1). Bare markers (no reason) are rejected in Case 6b below.
# -------------------------------------------------------------------
esc="$tmpdir/esc.md"
# The marker must be at column 0 (H-sec-4) with a non-empty reason
# (H-sec-1). Put the marker on its own line above the forbidden
# command to cover that shape too — the current implementation skips
# the WHOLE line containing the marker; authors wrap the annotation
# onto the same line as the command.
printf '## Verification commands\n\n<!-- audit:allow: documents the forbidden pattern for regression test --> cargo test\n' > "$esc"
# Verify the audit-log file is written inside a controllable ROOT_DIR
# replica so we can assert the append.
fakeroot_audit="$tmpdir/audit-root"
mkdir -p "$fakeroot_audit/scripts" "$fakeroot_audit/specs/tasks/queue"
cp "$GATE" "$fakeroot_audit/scripts/audit-verify-discipline.sh"
chmod +x "$fakeroot_audit/scripts/audit-verify-discipline.sh"
echo "# CLAUDE.md" > "$fakeroot_audit/CLAUDE.md"
esc_in_root="$fakeroot_audit/specs/tasks/queue/esc.md"
printf '## Verification commands\n\n<!-- audit:allow: documents the forbidden pattern for regression test --> cargo test\n' > "$esc_in_root"
out=$(bash "$fakeroot_audit/scripts/audit-verify-discipline.sh" "$esc_in_root" 2>&1)
rc=$?
log_file="$fakeroot_audit/.prod-check/audit-allow-bypasses.log"
if [ "$rc" -eq 0 ] && [ -f "$log_file" ] && grep -q 'reason=documents the forbidden pattern' "$log_file"; then
    pass "justified <!-- audit:allow: <reason> --> suppresses and logs to .prod-check/audit-allow-bypasses.log"
else
    fail "justified audit:allow escape hatch" "rc=$rc out=$out log=$( [ -f "$log_file" ] && cat "$log_file" || echo '<missing>' )"
fi

# Case 6b: bare `<!-- audit:allow -->` (no reason) does NOT suppress
# (H-sec-1 — every bypass must carry a justification).
esc_bare="$tmpdir/esc-bare.md"
printf '## Verification commands\n\ncargo test <!-- audit:allow -->\n' > "$esc_bare"
out=$(bash "$GATE" "$esc_bare" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -qE '(ALLOW-BARE|without reason|bare <!-- audit:allow --> )'; then
    pass "bare <!-- audit:allow --> (no reason) is REJECTED and surfaced as meta-violation"
else
    fail "bare audit:allow rejection" "rc=$rc out=$out"
fi

# Case 6c: audit:allow inside backticks does NOT suppress (H-sec-4).
esc_bt="$tmpdir/esc-bt.md"
printf '## Verification commands\n\nRun `cargo test <!-- audit:allow: reason -->` from repo root.\n' > "$esc_bt"
out=$(bash "$GATE" "$esc_bt" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -qE '(ALLOW-INVALID|not at column 0)'; then
    pass "<!-- audit:allow: reason --> inside backticks is REJECTED (must be at column 0)"
else
    fail "backtick-wrapped audit:allow rejection" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 7: word-boundary false-positive guards.
# -------------------------------------------------------------------
wb="$tmpdir/wb.md"
printf '## Verification commands\n\ncargo-fmt --check\nsome_cargo_test_runner.sh\ncargotest\n' > "$wb"
out=$(bash "$GATE" "$wb" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "cargo-fmt / some_cargo_test_runner.sh / cargotest do NOT fire (word-boundary)"
else
    fail "word-boundary guards" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 8: forbidden command OUTSIDE Verification section is ignored.
# -------------------------------------------------------------------
oscope="$tmpdir/out-of-scope.md"
cat > "$oscope" <<'OS'
# Spec

## Problem

Today, developers sometimes run `cargo test --workspace` to check
builds locally. This is fine — per-crate dev commands are not
verification. But this paragraph contains the exact forbidden
string and must NOT trigger the audit because it's out of scope.

## Verification commands

scripts/local-ci.sh --full

## Open questions

Another mention of `pnpm nx run foo:build` — also out of scope.
OS
out=$(bash "$GATE" "$oscope" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "forbidden command outside Verification section → rc=0 (section-scoped)"
else
    fail "section scoping" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 9: file with no Verification section → rc=0 (nothing to gate).
# -------------------------------------------------------------------
nosec="$tmpdir/no-section.md"
cat > "$nosec" <<'NS'
# Random doc

## Overview

Mentions `cargo test --workspace` in prose but has no Verification
section. Must pass.
NS
out=$(bash "$GATE" "$nosec" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "file with no Verification section → rc=0"
else
    fail "no-section file" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 10: multiple violations in one section are all reported.
# -------------------------------------------------------------------
multi="$tmpdir/multi.md"
cat > "$multi" <<'MU'
## Verification commands

cargo test --workspace
pnpm nx run @foo:build
./target/release/DeskModal
MU
out=$(bash "$GATE" "$multi" 2>&1)
rc=$?
count=$(echo "$out" | grep -c 'forbidden ' || true)
if [ "$rc" -eq 1 ] && [ "$count" -eq 3 ]; then
    pass "3 distinct violations in one section all reported (count=$count)"
else
    fail "multi-violation reporting" "rc=$rc count=$count out=$out"
fi

# -------------------------------------------------------------------
# Case 11: --fix-suggest output contains "suggest:" marker.
# -------------------------------------------------------------------
fs="$tmpdir/fs.md"
printf '## Verification commands\n\ncargo test\n' > "$fs"
out=$(bash "$GATE" --fix-suggest "$fs" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'suggest: '; then
    pass "--fix-suggest prints replacement command"
else
    fail "--fix-suggest output" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 12: --help prints usage and exits 0.
# -------------------------------------------------------------------
out=$(bash "$GATE" --help 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'Usage:'; then
    pass "--help prints usage, exits 0"
else
    fail "--help" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 13: unknown flag rejected with rc=2.
# -------------------------------------------------------------------
out=$(bash "$GATE" --nope 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    pass "unknown flag rejected with rc=2"
else
    fail "unknown flag" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 14 (H-sec-2): Unicode homoglyph evasion.
# `сargo test --workspace` with Cyrillic U+0441 (с) instead of Latin
# U+0063 (c) must FAIL closed. The cycle-0 regex accepted it because
# awk is byte-oriented and the Cyrillic byte sequence didn't match
# `cargo`. Fix: non-ASCII bytes in Verification commands fail.
# -------------------------------------------------------------------
homoglyph="$tmpdir/homoglyph.md"
printf '## Verification commands\n\n\xd1\x81argo test --workspace\n' > "$homoglyph"
out=$(bash "$GATE" "$homoglyph" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'non-ASCII bytes\|homoglyph'; then
    pass "Cyrillic homoglyph (сargo) → rc=1 (H-sec-2)"
else
    fail "Unicode homoglyph evasion" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 15 (H-sec-3): inline HTML comment evasion.
# `cargo <!-- anything --> test --workspace` must FAIL — the cycle-0
# implementation stripped only `<!-- audit:allow -->` markers and
# matched patterns against the raw line, so an innocuous-looking
# HTML comment broke the left-boundary regex. Fix: strip all
# non-audit HTML comments BEFORE pattern match.
# -------------------------------------------------------------------
inline="$tmpdir/inline-comment.md"
printf '## Verification commands\n\ncargo <!-- non-audit comment --> test --workspace\n' > "$inline"
out=$(bash "$GATE" "$inline" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden "cargo'; then
    pass "inline HTML comment between cargo and subcommand → rc=1 (H-sec-3)"
else
    fail "inline HTML comment evasion" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 16 (H-sec-5): multi-violation on a single line — all reported.
# Cycle-0 `break` in the awk pattern loop stopped at the first match,
# so `cargo test && pnpm nx build` reported only cargo. Fix: remove
# break; every matching pattern emits a record.
# -------------------------------------------------------------------
multiline="$tmpdir/multi-single.md"
printf '## Verification commands\n\ncargo test && pnpm nx build my-app\n' > "$multiline"
out=$(bash "$GATE" "$multiline" 2>&1)
rc=$?
count=$(echo "$out" | grep -c 'forbidden ' || true)
# Expect 2: one for cargo test, one for pnpm nx build.
if [ "$rc" -eq 1 ] && [ "$count" -ge 2 ]; then
    pass "multi-violation on one line → 2 records emitted (count=$count) (H-sec-5)"
else
    fail "multi-violation on one line" "rc=$rc count=$count out=$out"
fi

# -------------------------------------------------------------------
# Case 17 (H-bd-1): variable-substitution evasion.
# `$BUILDER test --workspace` must FAIL — indirection defeats the
# direct-command literal match.
# -------------------------------------------------------------------
var_sub="$tmpdir/var-sub.md"
printf '## Verification commands\n\n$BUILDER test --workspace\n' > "$var_sub"
out=$(bash "$GATE" "$var_sub" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden '; then
    pass "\$BUILDER test variable-substitution evasion → rc=1 (H-bd-1)"
else
    fail "variable substitution evasion" "rc=$rc out=$out"
fi

# Case 17b: `${CARGO} test` form.
var_sub_brace="$tmpdir/var-brace.md"
printf '## Verification commands\n\n${CARGO} test --workspace\n' > "$var_sub_brace"
out=$(bash "$GATE" "$var_sub_brace" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden '; then
    pass "\${CARGO} test brace-variable evasion → rc=1 (H-bd-1)"
else
    fail "brace-variable evasion" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 18 (H-bd-1): command-substitution evasion.
# `$(echo cargo) test` must FAIL.
# -------------------------------------------------------------------
cmd_sub="$tmpdir/cmd-sub.md"
printf '## Verification commands\n\n$(echo cargo) test --workspace\n' > "$cmd_sub"
out=$(bash "$GATE" "$cmd_sub" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden '; then
    pass "\$(echo cargo) test command-substitution evasion → rc=1 (H-bd-1)"
else
    fail "command substitution evasion" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 19 (H-bd-1): `eval "..."` with quoted argument.
# Conservative smell-flag per task prompt — not a hard-forbidden
# command per se, but direct eval in a Verification section is a
# smell.
# -------------------------------------------------------------------
eval_case="$tmpdir/eval.md"
printf '## Verification commands\n\neval "ca""rgo test"\n' > "$eval_case"
out=$(bash "$GATE" "$eval_case" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -qE 'forbidden "eval|eval.*smell'; then
    pass "eval \"...\" in Verification → rc=1 (H-bd-1)"
else
    fail "eval smell detection" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 20 (M-clippy): cargo clippy is forbidden.
# -------------------------------------------------------------------
clippy_case="$tmpdir/clippy.md"
printf '## Verification commands\n\ncargo clippy --workspace --all-targets\n' > "$clippy_case"
out=$(bash "$GATE" --fix-suggest "$clippy_case" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden "cargo clippy"' && echo "$out" | grep -q 'local-ci.sh'; then
    pass "cargo clippy → rc=1 with suggestion to local-ci.sh --fast (M-clippy)"
else
    fail "cargo clippy detection" "rc=$rc out=$out"
fi

# Case 20b: cargo fmt.
fmt_case="$tmpdir/fmt.md"
printf '## Verification commands\n\ncargo fmt --all -- --check\n' > "$fmt_case"
out=$(bash "$GATE" "$fmt_case" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden "cargo fmt"'; then
    pass "cargo fmt → rc=1 (M-clippy)"
else
    fail "cargo fmt detection" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Case 21 (M-output): control chars in matched token sanitised.
# Inject a BEL character into the trailing args of a matched command
# and confirm the output doesn't contain the raw BEL byte (the
# displayed matched token must have the control char replaced with
# '?'). The awk pattern matches `cargo test` first; the trailing
# BEL is inside the right-boundary char class, so sanitisation must
# strip it from any part of the matched token that captures it.
# -------------------------------------------------------------------
ctrl_case="$tmpdir/ctrl.md"
# `cargo test\x07` — trailing BEL after the matched token body.
printf '## Verification commands\n\ncargo test\x07workspace\n' > "$ctrl_case"
out=$(bash "$GATE" "$ctrl_case" 2>&1)
rc=$?
# The BEL byte must not appear in the output at all.
if [ "$rc" -eq 1 ] && ! printf '%s' "$out" | grep -q $'\x07'; then
    pass "control-char (BEL) in matched token is sanitised in output (M-output)"
else
    fail "control-char sanitisation" "rc=$rc out=$(printf '%q' "$out")"
fi

# -------------------------------------------------------------------
# Case 22 (M-allowlist): tools/*.md with violation triggers audit.
# Cycle-0 allowlist exempted all of tools/*, letting markdown docs
# through. Fix: extension-whitelist — only *.sh/*.rs/*.toml/*.py/
# *.ps1/*.cmd exempt. tools/foo.md must now fail.
# -------------------------------------------------------------------
fakeroot_aw="$tmpdir/aw-root"
mkdir -p "$fakeroot_aw/scripts" "$fakeroot_aw/tools/x"
cp "$GATE" "$fakeroot_aw/scripts/audit-verify-discipline.sh"
chmod +x "$fakeroot_aw/scripts/audit-verify-discipline.sh"
echo "# CLAUDE.md" > "$fakeroot_aw/CLAUDE.md"
printf '## Verification commands\n\ncargo test --workspace\n' > "$fakeroot_aw/tools/x/README.md"
out=$(bash "$fakeroot_aw/scripts/audit-verify-discipline.sh" "$fakeroot_aw/tools/x/README.md" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden "cargo test"'; then
    pass "tools/x/README.md with cargo test → rc=1 (extension-tightened allowlist, M-allowlist)"
else
    fail "tools/*.md not exempt from audit" "rc=$rc out=$out"
fi

# Case 22b: tools/x/helper.sh WITH cargo test → PASS (extension whitelist).
printf '#!/usr/bin/env bash\n# helper\n## Verification commands\ncargo test --workspace\n' > "$fakeroot_aw/tools/x/helper.sh"
out=$(bash "$fakeroot_aw/scripts/audit-verify-discipline.sh" "$fakeroot_aw/tools/x/helper.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "tools/x/helper.sh (shell script) still exempt → rc=0 (extension whitelist honoured)"
else
    fail "tools/*.sh still allowlisted" "rc=$rc out=$out"
fi

# Case 22c: scripts/quality-gates/NOTES.md triggers audit.
mkdir -p "$fakeroot_aw/scripts/quality-gates"
printf '## Verification commands\n\ncargo test\n' > "$fakeroot_aw/scripts/quality-gates/NOTES.md"
out=$(bash "$fakeroot_aw/scripts/audit-verify-discipline.sh" "$fakeroot_aw/scripts/quality-gates/NOTES.md" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'forbidden "cargo test"'; then
    pass "scripts/quality-gates/NOTES.md → rc=1 (tightened allowlist, M-allowlist)"
else
    fail "quality-gates/*.md not exempt" "rc=$rc out=$out"
fi

# -------------------------------------------------------------------
# Summary.
# -------------------------------------------------------------------
echo
printf "Passed: %d    Failed: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
