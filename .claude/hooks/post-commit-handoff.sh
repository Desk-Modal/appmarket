#!/usr/bin/env bash
#
# PostToolUse hook — fires after every `Bash(git commit*)` tool call.
# Appends (or creates) a brief entry in `.session-state/handoff.md`
# summarizing the commit that just landed. The agent is expected to
# flesh out the handoff further on the next turn; this hook guarantees
# the commit SHA + message never goes undocumented.
#
# Wired in .claude/settings.json under hooks.PostToolUse with matcher
# `Bash` — the hook itself filters for `git commit` commands via tool
# input inspection. Non-blocking: always exits 0.

set -u

ROOT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
HANDOFF="$ROOT_DIR/.session-state/handoff.md"

# Claude Code passes tool-use payload as JSON on stdin. We only fire
# for git commit commands; everything else exits silently.
payload="$(cat)"
if ! printf '%s' "$payload" | grep -qE '"command"[[:space:]]*:[[:space:]]*"[^"]*git[[:space:]]+commit'; then
    exit 0
fi

# Read the latest commit on HEAD. If git HEAD moved back (rebase etc.)
# this still captures the top commit — which is the durable checkpoint
# we want to record.
cd "$ROOT_DIR" 2>/dev/null || exit 0
sha=$(git rev-parse --short HEAD 2>/dev/null) || exit 0
subject=$(git log -1 --format='%s' 2>/dev/null) || exit 0
branch=$(git branch --show-current 2>/dev/null || echo '(detached)')
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$(dirname "$HANDOFF")"

if [ ! -f "$HANDOFF" ]; then
    cat > "$HANDOFF" <<EOF
# Session handoff — $ts

## Task
_(fill in on next turn — the agent should summarize what the user asked for)_

## Commits landed this session
- \`$sha\` on \`$branch\` — $subject

## Files modified
$(git status --short 2>/dev/null | head -20)

## Open work
_(fill in on next turn)_
EOF
    exit 0
fi

# Handoff exists — append the commit line under a stable section.
# Idempotent: if the SHA is already recorded, do nothing.
if grep -qF "\`$sha\`" "$HANDOFF" 2>/dev/null; then
    exit 0
fi

# Find or create the "## Commits landed this session" section.
if grep -q '^## Commits landed this session' "$HANDOFF"; then
    # Append under the section, preserving the rest of the file. Use a
    # portable approach that works on BSD + GNU sed: rewrite via python
    # if available, else awk.
    tmp="$(mktemp)"
    awk -v line="- \`$sha\` on \`$branch\` — $subject" '
        /^## Commits landed this session/ { print; in_section=1; next }
        in_section && /^## / { print line; print ""; in_section=0 }
        { print }
        END { if (in_section) { print line } }
    ' "$HANDOFF" > "$tmp" && mv "$tmp" "$HANDOFF"
else
    # Section doesn't exist — append it at the end.
    cat >> "$HANDOFF" <<EOF

## Commits landed this session
- \`$sha\` on \`$branch\` — $subject
EOF
fi

exit 0
