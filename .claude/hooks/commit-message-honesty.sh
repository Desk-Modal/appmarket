#!/usr/bin/env bash
#
# commit-msg honesty hook — rejects commit messages that use the banned
# phrases enumerated in `.claude/rules/honesty.md` §2 / §Cardinal Rule
# without an accompanying **evidence citation** anywhere in the same
# message body.
#
# Contract (per specs/tasks/queue/007-commit-message-honesty-hook/spec.md):
#   - Reads the commit-msg file path from $1 per git's commit-msg contract.
#   - Strips `#` comment lines (git auto-adds them) before scanning.
#   - Auto-exempts merge commits (`Merge …`) and reverts (`Revert …`).
#   - Auto-exempts empty / whitespace-only messages — git already rejects
#     those, we don't need to double-reject.
#   - Banned-phrase regex is a case-insensitive extended regex matching
#     the enumerated phrases from honesty.md. The list must stay aligned
#     with that rule; drift is a defect.
#   - If any banned phrase fires, the hook searches the same body for
#     at least ONE citation form (file:line, .prod-check/<path>,
#     .session-state/<path>, a 7–40 hex commit SHA, a URL, or an
#     `exit=N` assertion). One citation anywhere in the body satisfies
#     all banned phrases in the same body — the hook is checking for
#     evidence **culture**, not per-phrase pairing.
#   - `DESKMODAL_LAX=1` (or true/yes/on) bypasses enforcement but the
#     bypass is appended to `.prod-check/lax-bypass.log` in the same
#     shape used by `scripts/quality-gates/lib/common.sh:180-206`
#     (task 013). The commit proceeds and an advisory is printed to
#     stderr.
#
# Security posture: commit-msg content is user-controlled. The regex is
# **auditable, not foolproof** — a determined violator can paste a fake
# `exit=0` or fake path to satisfy the citation predicate. This is
# deliberate. The hook's job is to make laziness costly, not to prevent
# malicious bypass. Reviewers still read commit messages.
#
# Exit codes:
#   0 — message accepted (or LAX bypass honoured)
#   1 — message rejected with diagnostic on stderr

set -u

MSG_FILE="${1:-}"
if [ -z "$MSG_FILE" ] || [ ! -f "$MSG_FILE" ]; then
    # git always passes the path; absence means we were invoked out-of-
    # band. Don't block the commit — that would be a different kind of
    # bug than a banned phrase.
    exit 0
fi

# ---------------------------------------------------------------------------
# Locate ROOT_DIR without depending on a git call — the commit-msg hook
# runs inside `.git/hooks/` on the main repo *or* a worktree. Walk up
# from the hook script's real location until we find a repository root
# marker (CLAUDE.md at the workspace root), then fall back to the
# commit-msg file's parent tree, then finally the cwd.
# ---------------------------------------------------------------------------
resolve_root_dir() {
    local candidate
    # $0 is usually .git/hooks/commit-msg; its parent is .git/hooks,
    # grandparent is .git, great-grandparent is the worktree root.
    candidate="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd || true)"
    if [ -n "$candidate" ] && [ -f "$candidate/CLAUDE.md" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    # Fallback: the commit-msg file is usually under <root>/.git/COMMIT_EDITMSG
    # (or <worktree>/.git/worktrees/<name>/COMMIT_EDITMSG). Walk up from
    # its parent looking for CLAUDE.md.
    candidate="$(cd "$(dirname "$MSG_FILE")" 2>/dev/null && pwd || true)"
    while [ -n "$candidate" ] && [ "$candidate" != "/" ]; do
        if [ -f "$candidate/CLAUDE.md" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
        candidate="$(dirname "$candidate")"
    done
    # Last resort: cwd.
    pwd
}

ROOT_DIR="$(resolve_root_dir)"

# ---------------------------------------------------------------------------
# Strip comment lines (`#` prefix, git adds these) and collapse to body
# content we actually want to scan. Preserve blank-line separation so
# regexes that key on \b still behave.
# ---------------------------------------------------------------------------
msg_body="$(sed -e 's/\r$//' -e '/^#/d' "$MSG_FILE")"

# Empty / whitespace-only → accept (git will reject on its own).
if [ -z "$(printf '%s' "$msg_body" | tr -d '[:space:]')" ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Auto-exempt merge / revert commits — git generates these without human
# authorship, so the banned-phrase surface is zero. Match the SUBJECT
# line (first non-comment line).
# ---------------------------------------------------------------------------
subject="$(printf '%s\n' "$msg_body" | sed -n '1p')"
case "$subject" in
    Merge\ *|Revert\ *)
        exit 0
        ;;
esac

# ---------------------------------------------------------------------------
# Banned-phrase list — drawn from `.claude/rules/honesty.md` §Cardinal
# Rule ("It works") and `.claude/rules/context-discipline.md` §2
# ("I believe / I think / probably", "should work / ought to",
# "the tests pass", "it's fixed", "it works").
#
# Each pattern is a POSIX extended regex; case is ignored via grep -i.
# Patterns use word boundaries where false positives would otherwise
# fire (`\bought\b` would otherwise match "thought", "brought").
# ---------------------------------------------------------------------------
BANNED_PATTERNS=(
    '\bI[[:space:]]+believe\b'
    '\bI[[:space:]]+think\b'
    '\bprobably\b'
    '\bshould[[:space:]]+work\b'
    '\bought[[:space:]]+to\b'
    '\bthe[[:space:]]+tests[[:space:]]+pass\b'
    '\btests[[:space:]]+pass\b'
    "\bit'?s[[:space:]]+fixed\b"
    '\bit[[:space:]]+works\b'
)

# ---------------------------------------------------------------------------
# Citation regex — any ONE match in the body satisfies the evidence
# predicate. Documented in spec §Approach step 2.
# ---------------------------------------------------------------------------
CITATION_PATTERNS=(
    '[A-Za-z0-9._/-]+\.(rs|ts|tsx|py|go|java|c|cpp|h|hpp|toml|md|json|yml|yaml|sh):[0-9]+(-[0-9]+)?'
    '\.prod-check/[A-Za-z0-9._/-]+'
    '\.session-state/[A-Za-z0-9._/-]+'
    '\b[a-f0-9]{7,40}\b'
    'https?://[^[:space:])]+'
    'exit=[0-9]+'
)

has_citation() {
    local body="$1" pat
    for pat in "${CITATION_PATTERNS[@]}"; do
        if printf '%s' "$body" | grep -Eq "$pat"; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Scan for banned phrases. We record the FIRST offender (phrase + line)
# for a helpful diagnostic. Line numbers refer to the scrubbed body
# (comment lines removed), which is what the user will re-edit.
# ---------------------------------------------------------------------------
first_banned=""
first_banned_line=""
first_banned_text=""
while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    # grep -n returns `<line>:<text>` — first match only.
    hit="$(printf '%s\n' "$msg_body" | grep -niE "$pat" | head -n1 || true)"
    if [ -n "$hit" ]; then
        first_banned="$pat"
        first_banned_line="${hit%%:*}"
        first_banned_text="${hit#*:}"
        break
    fi
done <<EOF
$(printf '%s\n' "${BANNED_PATTERNS[@]}")
EOF

if [ -z "$first_banned" ]; then
    # No banned phrase → accept unconditionally.
    exit 0
fi

# Banned phrase present. Does the body cite evidence?
if has_citation "$msg_body"; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Banned phrase WITHOUT citation — honour DESKMODAL_LAX escape hatch
# (pattern aligned with qg_honor_lax in
# scripts/quality-gates/lib/common.sh:180-206) before failing.
# ---------------------------------------------------------------------------
honor_lax_bypass() {
    case "${DESKMODAL_LAX:-}" in
        1|true|yes|on) ;;
        *) return 1 ;;
    esac
    local log_dir="$ROOT_DIR/.prod-check"
    local log_file="$log_dir/lax-bypass.log"
    local ts user sha reason
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'unknown-ts')
    user=$(id -un 2>/dev/null || printf 'unknown-user')
    sha=$( (cd "$ROOT_DIR" && git rev-parse --short HEAD 2>/dev/null) || printf 'unknown-sha')
    reason="banned-phrase-without-citation: ${first_banned_text//	/ }"
    local line
    line="$ts	user=$user	sha=$sha	gate=commit-message-honesty	reason=$reason"
    if ! mkdir -p "$log_dir" 2>/dev/null; then
        printf 'WARN: commit-message-honesty: could not mkdir %s; bypass not audited\n' "$log_dir" >&2
    elif ! printf '%s\n' "$line" >> "$log_file" 2>/dev/null; then
        printf 'WARN: commit-message-honesty: could not append to %s; bypass not audited\n' "$log_file" >&2
    fi
    printf 'commit-msg ADVISORY: DESKMODAL_LAX=1 honoured — banned phrase accepted without citation. Audit: %s\n' "$log_file" >&2
    return 0
}

if honor_lax_bypass; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Reject with the diagnostic shape documented in spec §Acceptance.
# ---------------------------------------------------------------------------
# Extract the human-readable phrase from first_banned_text (strip leading
# whitespace) for the diagnostic. Keep it short (first 80 chars).
banned_excerpt="$(printf '%s' "$first_banned_text" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | cut -c1-80)"

cat >&2 <<EOF

commit-msg REJECTED: banned phrase detected at line ${first_banned_line:-?} without
evidence citation.

  offending line: ${banned_excerpt}

Add a reference in the same commit message to ONE of:
  - a file path with line number  (e.g. platform/src/main.rs:42)
  - a .prod-check/* log path      (e.g. .prod-check/cargo_tests.log)
  - a .session-state/* path       (e.g. .session-state/handoff.md)
  - a commit SHA (7–40 hex chars)
  - a URL (https://…)
  - an exit-code assertion        (e.g. exit=0)

Reference: .claude/rules/honesty.md §Cardinal Rule,
           .claude/rules/context-discipline.md §2.

Bypass (emergencies only, logged): DESKMODAL_LAX=1 git commit …

EOF
exit 1
