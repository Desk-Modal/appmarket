#!/usr/bin/env bash
# Pre-commit serialization guard for parallel agent sessions (#135).
#
# When multiple Claude agents run in parallel against the same repo,
# their pre-commit hooks can race on shared state (index, worktree).
# This script acquires an exclusive flock on a per-repo lockfile before
# running the actual pre-commit logic, serializing concurrent hook runs.
#
# Usage: source this at the top of .git/hooks/pre-commit, or invoke it
# as a wrapper:
#   .claude/hooks/pre-commit-guard.sh <original-hook-command>

set -euo pipefail

REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"
LOCKFILE="${TMPDIR:-/tmp}/.claude-precommit-${REPO_NAME}.lock"

# macOS ships no flock; Homebrew provides it via keg-only util-linux, which is
# OFF the default PATH. Login shells get it from a profile export, but non-
# interactive shells (agents, CI, fresh clones) do not — without this the lock
# silently fails and blocks every commit. Make the keg-only binary findable.
for _d in /opt/homebrew/opt/util-linux/bin /usr/local/opt/util-linux/bin; do
    if [ -x "$_d/flock" ]; then
        case ":$PATH:" in *":$_d:"*) ;; *) PATH="$_d:$PATH" ;; esac
    fi
done

if command -v flock >/dev/null 2>&1; then
    # Open the lockfile on fd 9 (leaves stdin/stdout/stderr free) and wait up
    # to 30s for the exclusive lock — serialises concurrent agent hook runs.
    exec 9>"$LOCKFILE"
    if ! flock -w 30 9; then
        echo "pre-commit-guard: lock timeout after 30s (another hook still running?)" >&2
        exit 1
    fi
else
    # No flock anywhere (e.g. stock Windows Git Bash). Proceed WITHOUT the
    # inter-agent lock rather than hard-blocking the commit — the single-
    # session default (parallel-sessions.md) makes index races unlikely there.
    echo "pre-commit-guard: flock unavailable — proceeding without inter-agent lock" >&2
fi

# If arguments were passed, execute them under the lock.
if [ $# -gt 0 ]; then
    "$@"
fi
