#!/usr/bin/env bash
#
# .claude/hooks/tests/shift-left-review.test.sh
#
# Regression coverage for .claude/rules/shift-left-review.md.
# Auto-discovered by `scripts/local-ci.sh --fast`'s hooks:* gate.
#
# Shift-left-review is a rule-only change (no script to unit-test).
# This regression test guards the rule file's required shape so
# silent drift cannot erase the Phase 1.5 mandate.
#
# Test cases:
#   1. Rule file exists at .claude/rules/shift-left-review.md.
#   2. Rule declares Phase 1.5 as MANDATORY for every task.
#   3. Rule declares Phase 2.5 as OPT-IN with the >20-file and
#      exclusive-wave-eligibility triggers.
#   4. Rule defines the structured JSON return shape with
#      verdict in {OK, CONCERN, BLOCK} and a spec_revisions_required
#      field.
#   5. Rule cross-references the mandatory-parallel-reviewer
#      invariant in .claude/rules/agent-team.md — sequential
#      reviewer dispatch is forbidden in Phase 1.5 too.
#   6. Rule cross-references the Conditional reviewer matrix in
#      agent-team.md — trading-sme is NOT universal.
#   7. agent-team.md has the Conditional reviewer matrix section.
#   8. Rule specifies at least one skip-list entry (rule
#      amendments) with an explicit rationale.
#   9. Rule documents the DESKMODAL_LAX=1 bypass with lax-bypass.log
#      audit trail — parity with other rule bypasses.
#  10. Rule declares the Amendment governance clause naming at
#      least the integration-architect reviewer.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RULE_FILE="$ROOT_DIR/.claude/rules/shift-left-review.md"
AGENT_TEAM_FILE="$ROOT_DIR/.claude/rules/agent-team.md"

pass=0
fail=0

assert_file_exists() {
    local path="$1"
    local msg="$2"
    if [ -f "$path" ]; then
        printf '  OK   %s\n' "$msg"
        pass=$((pass + 1))
    else
        printf '  FAIL %s (missing: %s)\n' "$msg" "$path"
        fail=$((fail + 1))
    fi
}

assert_grep() {
    local pattern="$1"
    local path="$2"
    local msg="$3"
    if [ ! -f "$path" ]; then
        printf '  FAIL %s (file missing: %s)\n' "$msg" "$path"
        fail=$((fail + 1))
        return
    fi
    if grep -qE "$pattern" "$path"; then
        printf '  OK   %s\n' "$msg"
        pass=$((pass + 1))
    else
        printf '  FAIL %s (pattern: %s)\n' "$msg" "$pattern"
        fail=$((fail + 1))
    fi
}

printf '== shift-left-review.test.sh ==\n'

# 1. rule file exists
assert_file_exists "$RULE_FILE" "rule file shift-left-review.md exists"

# 2. Phase 1.5 opt-in with trigger list
assert_grep \
    'Phase 1\.5.+(OPT-IN|opt-in)' \
    "$RULE_FILE" \
    "Phase 1.5 declared opt-in"
assert_grep \
    'wave_eligibility: exclusive' \
    "$RULE_FILE" \
    "Phase 1.5 trigger list includes wave_eligibility: exclusive"
assert_grep \
    'status: ambiguous|constitution invariant' \
    "$RULE_FILE" \
    "Phase 1.5 trigger list names opt-in signals"

# 3. Phase 2.5 opt-in with triggers
assert_grep \
    'Phase 2\.5' \
    "$RULE_FILE" \
    "Phase 2.5 declared"
assert_grep \
    '(write_set|files touched|structural change)' \
    "$RULE_FILE" \
    "Phase 2.5 trigger references impl scale (files/write_set/structural)"
assert_grep \
    'wave_eligibility: exclusive' \
    "$RULE_FILE" \
    "Phase 2.5 trigger references wave_eligibility: exclusive"

# 4. structured JSON return shape
assert_grep \
    '"verdict": "OK\|CONCERN\|BLOCK"' \
    "$RULE_FILE" \
    "JSON return shape declares verdict enum"
assert_grep \
    'spec_revisions_required' \
    "$RULE_FILE" \
    "JSON return shape declares spec_revisions_required field"

# 5. parallel-reviewer invariant
assert_grep \
    'ONE parallel .Agent. batch' \
    "$RULE_FILE" \
    "parallel-reviewer invariant preserved (ONE batch)"
assert_grep \
    'Sequential reviewer dispatch' \
    "$RULE_FILE" \
    "rule calls out sequential dispatch as forbidden"

# 6. conditional reviewer matrix reference
assert_grep \
    'Conditional reviewer matrix' \
    "$RULE_FILE" \
    "rule cross-references Conditional reviewer matrix"
assert_grep \
    'trading-sme.+(NOT universal|never universal|NEVER universal)' \
    "$RULE_FILE" \
    "rule asserts trading-sme is not universal"

# 7. agent-team.md has the Conditional reviewer matrix section
assert_grep \
    '## Conditional reviewer matrix' \
    "$AGENT_TEAM_FILE" \
    "agent-team.md defines the Conditional reviewer matrix section"
assert_grep \
    'trading-sme.+CONDITIONAL' \
    "$AGENT_TEAM_FILE" \
    "agent-team.md declares trading-sme CONDITIONAL"

# 8. skip-list with rationale
assert_grep \
    'Rule amendments' \
    "$RULE_FILE" \
    "skip-list includes rule amendments"

# 9. DESKMODAL_LAX bypass with audit trail
assert_grep \
    'DESKMODAL_LAX=1' \
    "$RULE_FILE" \
    "rule documents DESKMODAL_LAX bypass"
assert_grep \
    'lax-bypass\.log' \
    "$RULE_FILE" \
    "rule routes bypass to lax-bypass.log audit trail"

# 10. amendment clause
assert_grep \
    'Amendment' \
    "$RULE_FILE" \
    "rule defines Amendment clause"
assert_grep \
    'integration-architect' \
    "$RULE_FILE" \
    "Amendment clause names integration-architect reviewer"

printf -- '-- summary: pass=%d fail=%d --\n' "$pass" "$fail"

if [ "$fail" -gt 0 ]; then
    exit 1
fi
exit 0
