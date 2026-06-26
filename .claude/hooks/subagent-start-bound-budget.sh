#!/usr/bin/env bash
# F157 Layer 4 SubagentStart hook: MODEL-AWARE concurrent-agent cap.
#
# The empirical 3-cap (feedback_api_load_concurrent_agents, 2026-05-18) is for
# LARGE-CONTEXT OPUS specifically — 2-of-3 returns got harness-rejected. Lighter
# models (sonnet/haiku) do not hit that pressure, so capping ALL agents flatly at
# 3 wasted the machine's throughput (12 cores → the Workflow runtime allows
# min(16, cores-2) concurrent). This hook scales to throughput via model-tiering:
#   total in-flight   ≤ MAX_AGENTS   (default 8 — throughput-scaled)
#   heavy in-flight   ≤ MAX_OPUS     (default 3 — the empirical opus/fable limit)
# "heavy" = opus/fable OR unknown model (conservative — unknown degrades to the
# safe 3-cap, so there is never a regression vs the old flat behaviour).
# Per F157 Layer 12 cost-control: scale to throughput, not unbounded.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0

MAX_AGENTS="${DESKMODAL_MAX_CONCURRENT_AGENTS_PER_SESSION:-8}"
MAX_OPUS="${DESKMODAL_MAX_CONCURRENT_OPUS_PER_SESSION:-3}"
LOG_FILE="${CWD}/.session-state/subagent-log.md"
mkdir -p "${CWD}/.session-state"
touch "$LOG_FILE"

# Read JSON input from stdin
input=$(cat)
agent_type=$(printf '%s' "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('agent_type','unknown'))" 2>/dev/null || echo unknown)
agent_id=$(printf '%s' "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('agent_id','unknown'))" 2>/dev/null || echo unknown)
model=$(printf '%s' "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('model','') or '')" 2>/dev/null || echo "")
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Classify: heavy = large-context opus/fable, OR unknown model (conservative).
case "$model" in
  *opus*|*fable*|"") heavy=1 ;;
  *) heavy=0 ;;
esac

# Count in-flight (IN-FLIGHT markers not yet matched by STOP). Use `wc -l`-style
# single-integer capture (bare `grep -c || echo 0` yields "0\n0" on zero match).
in_flight=$(grep -c '^- IN-FLIGHT' "$LOG_FILE" 2>/dev/null | head -1)
[ -z "$in_flight" ] && in_flight=0
heavy_in_flight=$(grep -c '^- IN-FLIGHT.*heavy=1' "$LOG_FILE" 2>/dev/null | head -1)
[ -z "$heavy_in_flight" ] && heavy_in_flight=0

block_reason=""
if [ "$in_flight" -ge "$MAX_AGENTS" ]; then
  block_reason="total ${in_flight}/${MAX_AGENTS} agents already in flight"
elif [ "$heavy" -eq 1 ] && [ "$heavy_in_flight" -ge "$MAX_OPUS" ]; then
  block_reason="heavy(opus/fable) ${heavy_in_flight}/${MAX_OPUS} already in flight — dispatch a sonnet/haiku lane instead, or wait"
fi

if [ -n "$block_reason" ]; then
  cat <<EOF
{
  "decision": "block",
  "reason": "F157 model-aware cap: ${block_reason} (dispatching '${agent_type}' model='${model}'). Model-tiering: ≤${MAX_OPUS} concurrent opus/fable, ≤${MAX_AGENTS} total per session."
}
EOF
  exit 2
fi

# Allow + log (carry model + heavy so the heavy sub-cap is countable).
echo "- IN-FLIGHT [${ts}] agent_id=${agent_id} type=${agent_type} model=${model} heavy=${heavy}" >> "$LOG_FILE"
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "F157 model-aware: in-flight=${in_flight}/${MAX_AGENTS} (heavy=${heavy_in_flight}/${MAX_OPUS}) after dispatching ${agent_type} model='${model}'"
  }
}
EOF
exit 0
