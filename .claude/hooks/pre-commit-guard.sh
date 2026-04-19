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

# Open the lockfile on fd 9 (leaves stdin/stdout/stderr free).
exec 9>"$LOCKFILE"

# Wait up to 30 seconds for the lock. If another agent's hook is running,
# we block here rather than racing on the git index.
if ! flock -w 30 9; then
    echo "pre-commit-guard: lock timeout after 30s (another hook still running?)" >&2
    exit 1
fi

# If arguments were passed, execute them under the lock.
if [ $# -gt 0 ]; then
    "$@"
fi
