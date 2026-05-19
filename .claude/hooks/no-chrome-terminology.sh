#!/usr/bin/env bash
# no-chrome-terminology — commit-msg hook
#
# User directive 2026-05-16 (reiterated several times): "we are not using
# chrome it is all tauri" + "you keep forgetting". This hook enforces
# the vocabulary rule from `.claude/rules/core.md` §17 by rejecting any
# commit message that uses the word "chrome" to describe DeskModal's
# window-decoration layer.
#
# Use one of: "Tauri-native window decorations", "OS-native title bar",
# "native traffic lights" (macOS), or "native min/max/close" (Windows).
#
# Exempted contexts (allowed because the word genuinely refers to
# something else):
#   - `Chrome DevTools Protocol` / `CDP` references.
#   - References to Google Chrome the browser (rare, but legitimate).
#   - Legacy file names cited in rename/history commits — the allowlist
#     below sanitises historical references to `AppShellChrome.tsx` and
#     `audit-no-custom-chrome.sh` so rename commits don't false-fail.
#
# Wired via git's `.git/hooks/commit-msg` (which `exec`s this script).
# Claude Code's settings.json hook events (SessionStart/PreToolUse/Stop/etc.)
# do NOT include commit-msg — that's a git-level event, not a Claude Code
# event — so installation lives in `.git/hooks/commit-msg`, not settings.json.
# Bypass: `DESKMODAL_LAX=1 git commit` (audit-logged per core.md §11).

set -euo pipefail

msg_file="${1:-}"
if [[ -z "$msg_file" || ! -f "$msg_file" ]]; then
  # No commit-msg file — nothing to check.
  exit 0
fi

if [[ "${DESKMODAL_LAX:-}" == "1" ]]; then
  printf "[no-chrome-terminology] DESKMODAL_LAX=1 — bypassing terminology check.\n" >&2
  exit 0
fi

# Strip allowlisted tokens before scanning.
sanitised=$(
  sed -E \
    -e 's/Chrome DevTools Protocol//g' \
    -e 's/\bCDP\b//g' \
    -e 's/Google Chrome//g' \
    -e 's/AppShellChrome[A-Za-z._-]*//g' \
    -e 's/audit-no-custom-chrome\.sh//g' \
    -e 's/quality:no-custom-chrome//g' \
    -e 's/window-chrome[A-Za-z._-]*\.json//g' \
    -e 's/no-chrome-terminology[A-Za-z._-]*//g' \
    -e 's/window-chrome\.module\.css//g' \
    "$msg_file"
)

if printf "%s" "$sanitised" | grep -iE '\bchrome\b' >/dev/null; then
  cat >&2 <<'EOF'
[no-chrome-terminology] Commit message contains "chrome".

DeskModal is all Tauri — window decorations are OS-native.
Per `.claude/rules/core.md` §17 (Tauri-native window decorations —
Vocabulary rule), don't call DeskModal's window-decoration layer "chrome".

Use instead:
  - "Tauri-native window decorations"
  - "OS-native title bar"
  - "native traffic lights" (macOS)
  - "native min/max/close" (Windows / Linux GTK)

Edit the commit message and retry. To bypass (only when "chrome" genuinely
refers to Chrome DevTools Protocol or the Google Chrome browser, and
the allowlist didn't catch it):
  DESKMODAL_LAX=1 git commit ...

The rule exists because "chrome" is overloaded with Chromium-browser
connotation and conceals the architectural decision. The user has
flagged this terminology slip multiple times.
EOF
  exit 1
fi

exit 0
