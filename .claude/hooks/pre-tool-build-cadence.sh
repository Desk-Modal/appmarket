#!/usr/bin/env bash
# PreToolUse hook: mechanically enforce the build-cadence + incremental-cache
# policies so they stop being passive memory (the recurring drift root cause).
# Wired into settings.json PreToolUse → fires for EVERY session + agent across
# the mesh (settings.json is in the sync-specs canonical mirror).
#
# Authority: architecture.md §29 (incremental-only / no-duplicate-builds) +
# quality.md §18.7.1 (Tier cadence) + feedback_no_duplicate_builds_share_cache +
# feedback_reverify_changed_gate_not_full_rebuild.
#
# Policy:
#   HARD-BLOCK (decision:block, exit 2) — the unambiguous §29 cache-destroyers
#   that have ZERO legitimate mid-loop use (warm-cache discipline). The §29
#   permitted reset points (setup.sh --reset / cleanup-build-assets.sh --apply /
#   build-dist --release) invoke these INSIDE a script, so the top-level command
#   the hook sees is the script name, not the bare destroyer — those pass.
#
#   ADVISE (stderr + log, exit 0, non-blocking) — cadence smells: a release/full
#   build mid-iteration, or --full when --fast (affected) would do. Advisory
#   because a phase-boundary / ship build legitimately needs them.

set -uo pipefail
CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOG="${CWD}/.session-state/build-cadence.log"
mkdir -p "${CWD}/.session-state" 2>/dev/null || true

input=$(cat 2>/dev/null || echo '{}')
tool=$(printf '%s' "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo '')
cmd=$(printf '%s'  "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo '')

# Only police Bash commands.
[ "$tool" = "Bash" ] || exit 0
[ -n "$cmd" ] || exit 0

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

block() {
    printf '{"decision":"block","reason":%s}\n' "$(python3 -c "import json,sys;print(json.dumps(sys.argv[1]))" "$1")"
    echo "$ts BLOCK: $1 :: cmd=[$cmd]" >> "$LOG" 2>/dev/null || true
    exit 2
}
advise() {
    echo "build-cadence advisory: $1" >&2
    echo "$ts ADVISE: $1 :: cmd=[$cmd]" >> "$LOG" 2>/dev/null || true
}

# ── HARD-BLOCK: §29 cache-destroyers (no legit mid-loop use) ──────────────────
# Strip quoted substrings FIRST so a destroyer string mentioned inside a quoted
# argument (e.g. git commit -m "... cargo clean ...", echo "...") is NOT matched
# as an actual invocation — only bare/unquoted commands are policed.
scan=$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
case "$scan" in
    *"cargo clean"*)
        block "architecture.md §29: cargo-clean destroys the warm incremental cache (defeats incremental builds). If you genuinely need a reset, use scripts/setup.sh --reset or scripts/cleanup-build-assets.sh --apply (the §29-permitted reset points)." ;;
    *"nx reset"*)
        block "architecture.md §29: nx-reset wipes the Nx build cache. Use the §29-permitted reset points if a reset is truly required." ;;
    *"pnpm install --force"*)
        block "architecture.md §29: pnpm-install-force forces a cold node_modules rebuild. Avoid mid-loop." ;;
esac
# rm -rf targeting a build cache dir (target/ or node_modules) inside the workspace
if printf '%s' "$scan" | grep -Eq 'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f?[[:space:]].*(/target([[:space:]/]|$)|/node_modules([[:space:]/]|$)|[[:space:]]target([[:space:]/]|$))'; then
    block "architecture.md §29: deleting a target/ or node_modules cache dir destroys the warm incremental cache. Disk-space resets go through scripts/cleanup-build-assets.sh --apply (which preserves the policy)."
fi

# ── ADVISE: cadence smells (non-blocking) ────────────────────────────────────
# Release / full build mid-iteration — reserve for phase boundary / ship.
if printf '%s' "$cmd" | grep -Eq 'build-dist(\.sh)?'; then
    if ! printf '%s' "$cmd" | grep -Eq '\-\-debug'; then
        advise "build-dist defaults to --release (lto, incremental=false → cold). For per-batch launch-health use --debug (warm, CARGO_INCREMENTAL=1); reserve --release --sign for an actual ship/phase-boundary. Stay on ONE profile per loop — flipping debug<->release rebuilds a whole tree."
    fi
fi
if printf '%s' "$cmd" | grep -Eq 'local-ci(\.sh)?[^|]*--full'; then
    advise "local-ci --full disables affected-scope (~15min). Per-batch use --fast (affected since last-green.sha). Run --full --sign only at a phase boundary / pre-push (quality.md §18.7.1 Tier-C)."
fi

exit 0
