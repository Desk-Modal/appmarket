#!/usr/bin/env bash
# Back-compat wrapper. Canonical runner is scripts/prod-check.sh.
# Every new call site should target the canonical runner directly;
# this wrapper exists because `.claude/rules/verification.md`,
# `.github/workflows/prod-check.yml`, and the Stop-hook ledger all
# reference the historical path.
exec "$(dirname "$0")/../../scripts/prod-check.sh" optiscript "$@"
