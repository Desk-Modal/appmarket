#!/usr/bin/env bash
# Walk up from a starting directory to find the DeskModal workspace root.
#
# The workspace root is identified by `scripts/session-mesh/` — that path
# exists only at /Users/adrian/deskmodal/ (the outer-workspace root), NOT
# in any of the 7 sub-repos. Each sub-repo has its OWN `scripts/` directory
# with repo-local scripts, but never `scripts/session-mesh/`. So walking up
# until we find that sentinel always lands at the right place from any depth.
#
# Used by canonical skills that need to invoke `scripts/session-mesh/*.sh`
# or read `specs/`/`wiki/` from the root. Avoids hard-coded `../../../`
# relative paths that break in sub-repo mirrors at different depths.
#
# Usage:
#   ROOT=$(bash "${CLAUDE_SKILL_DIR}/../_lib/dm-root.sh") || exit 1
#   bash "$ROOT/scripts/session-mesh/list-findings.sh" ...
#
# Arg 1 (optional): starting dir. Defaults to $CLAUDE_SKILL_DIR if set,
# else $PWD.

set -e
start="${1:-${CLAUDE_SKILL_DIR:-$PWD}}"
d="$start"
while [ "$d" != "/" ]; do
  if [ -d "$d/scripts/session-mesh" ]; then
    echo "$d"
    exit 0
  fi
  d=$(dirname "$d")
done
echo "ERROR: DeskModal workspace root not found (walked up from $start; expected scripts/session-mesh/ at some ancestor)" >&2
exit 1
