#!/usr/bin/env bash
#
# DeskModal Developer Setup — first-time machine bootstrap.
#
# Clones every Desk-Modal sub-repo into the workspace layout, installs
# every prerequisite toolchain (rust, node, pnpm, python, protoc), and
# builds a runnable dist/ so `./dist/DeskModal` works immediately.
#
# Idempotent — safe to re-run. Already-cloned sub-repos are `git fetch`ed,
# already-installed toolchains are left alone.
#
# Prerequisites you must install manually BEFORE running this script:
#   - git  (macOS: `xcode-select --install` or bundled with Xcode CLI)
#   - gh   (macOS: `brew install gh` then `gh auth login`)
#
# Everything else the script handles itself.
#
# Usage (fresh macOS machine):
#
#     # 1. Install gh + authenticate (one-time per machine)
#     brew install gh
#     gh auth login   # follow the prompts, GitHub.com + HTTPS + browser
#
#     # 2. Clone the workspace and run setup
#     gh repo clone Desk-Modal/deskmodal-workspace ~/deskmodal
#     cd ~/deskmodal
#     bash scripts/setup.sh
#
# After setup completes the dist/ directory is populated and you can:
#     ./dist/DeskModal                    # Launch the agent
#     ./scripts/local-ci.sh --fast        # Quick gate run
#     ./scripts/local-ci.sh --full        # Full CI gates (pre-push)
#     ./scripts/release.sh <target>       # Cut a release

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Vendored toolchain binary — must be defined before any function refers
# to it (install_uv/install_protoc/install_cbm_binary run from --config-only
# before the full toolchain install path would otherwise set this).
MISE_BIN="$ROOT_DIR/tools/mise"

# ---------------------------------------------------------------------------
# Flags
#
# --config-only   Skip toolchain install, cargo builds, and dist assembly.
#                 Runs only the Claude Code / MCP / scaffold steps so the
#                 drift-detector hook can apply config updates after a
#                 `git pull` without forcing a full rebuild.
# --quiet         Silence non-error output.
# --with-gui-tests Opt-in: install the cross-platform GUI test harness
#                 at tests/gui/ (Appium + XCUITest on macOS, WinAppDriver
#                 on Windows, WebKitGTK Inspector on Linux). Vendored in
#                 tools/gui/ — nothing lands globally. Without this flag
#                 every GUI prod-check gate stays BLOCKED.
# ---------------------------------------------------------------------------
CONFIG_ONLY=0
QUIET=0
REQUIRE_GITHUB=0
CI_MODE=0
WITH_GUI_TESTS=0
for arg in "$@"; do
    case "$arg" in
        --config-only)    CONFIG_ONLY=1 ;;
        -q|--quiet)       QUIET=1 ;;
        --require-github) REQUIRE_GITHUB=1 ;;
        # --ci: shorthand for GH Actions / headless runners. Implies
        # --quiet --require-github and turns off the interactive Xcode
        # installer launch. Does NOT imply --config-only — CI typically
        # wants the full toolchain install.
        --ci)             CI_MODE=1; QUIET=1; REQUIRE_GITHUB=1 ;;
        --with-gui-tests) WITH_GUI_TESTS=1 ;;
    esac
done
if [ "$CONFIG_ONLY" = 1 ]; then
    # In config-only mode we expose the same step for the CBM / scaffold
    # logic and jump straight to it after a minimal preamble.
    :
fi

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
OS_KIND=""
case "$(uname -s)" in
    Linux*)              OS_KIND=linux ;;
    Darwin*)             OS_KIND=darwin ;;
    MINGW*|MSYS*|CYGWIN*) OS_KIND=windows ;;
    *)                   OS_KIND=unknown ;;
esac

cat <<EOF
============================================
  DeskModal Developer Setup
  OS:   $OS_KIND
  Root: $ROOT_DIR
============================================
EOF

ERRORS=0

err() {
    echo "  ERROR: $*" >&2
    ERRORS=$((ERRORS + 1))
}

have() {
    command -v "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Helper functions
#
# Every install_* helper is idempotent — calling it when the artefact is
# already installed at the expected version is a no-op (it prints a
# status line and returns 0). Helpers that reach the network degrade
# gracefully on offline machines: they print a WARN and return 0 so
# setup.sh can still complete the steps that don't need connectivity.
# ---------------------------------------------------------------------------

# uv (https://astral.sh/uv) — Python package + tool manager. Preferred
# install path is mise (so the version pin in mise.toml is authoritative);
# fall back to pipx, then to the official installer. The workspace
# install lives at $ROOT_DIR/tools/uv so every developer runs the same
# binary without touching $HOME. Non-fatal if install fails — phases
# that need uv will surface their own errors.
install_uv() {
    local dest_dir="$1"
    local pinned_version="${DESKMODAL_UV_VERSION:-0.5.4}"
    mkdir -p "$dest_dir"

    if [ -x "$MISE_BIN" ] && "$MISE_BIN" which uv >/dev/null 2>&1; then
        local current
        current=$("$MISE_BIN" which uv 2>/dev/null)
        if [ -n "$current" ] && [ -x "$current" ]; then
            echo "  uv: already installed via mise ($("$current" --version 2>/dev/null | head -1))"
            return 0
        fi
    fi
    if [ -x "$dest_dir/uv" ] && "$dest_dir/uv" --version 2>/dev/null | grep -q "$pinned_version"; then
        echo "  uv: already pinned at $pinned_version in tools/"
        return 0
    fi
    if have uv; then
        echo "  uv: found on PATH ($(uv --version 2>/dev/null | head -1))"
        return 0
    fi
    if have pipx; then
        echo "  uv: installing via pipx..."
        if pipx install "uv==$pinned_version" 2>&1 | tail -3; then
            return 0
        fi
        echo "  uv: pipx install failed, falling back to installer"
    fi
    if have curl; then
        echo "  uv: installing via official installer (pinned $pinned_version)..."
        local tmp; tmp=$(mktemp -d)
        if curl -fsSL --max-time 120 -o "$tmp/uv-install.sh" "https://astral.sh/uv/$pinned_version/install.sh" 2>/dev/null; then
            UV_INSTALL_DIR="$dest_dir" UV_UNMANAGED_INSTALL="$dest_dir" sh "$tmp/uv-install.sh" >"$dest_dir/uv-install.log" 2>&1 || \
                echo "  uv: installer returned non-zero — see tools/uv-install.log"
        else
            echo "  uv: installer download failed (offline?) — skipped"
        fi
        rm -rf "$tmp"
    else
        echo "  uv: curl missing — cannot install"
    fi
}

# Spec Kit (https://github.com/github/spec-kit) — `specify-cli` Python
# package. Installed as a uv tool so it lives in $ROOT_DIR/tools and its
# dependencies never leak into the developer's global Python. If the
# scaffold is already present at `.specify/` and every `.claude/skills/
# speckit-*/SKILL.md` is intact, this is a no-op — `specify init --here`
# would overwrite those files with the upstream templates, so we only
# run init when `.specify/` is missing.
install_spec_kit() {
    local root_dir="$1"
    local tools_dir="$root_dir/tools"
    if [ ! -x "$tools_dir/uv" ] && ! have uv; then
        echo "  spec-kit: uv missing, skipping"
        return 0
    fi
    local uv_bin
    if [ -x "$tools_dir/uv" ]; then uv_bin="$tools_dir/uv"; else uv_bin="uv"; fi

    mkdir -p "$tools_dir"
    export UV_TOOL_DIR="$tools_dir/uv-tools"
    export UV_TOOL_BIN_DIR="$tools_dir"
    mkdir -p "$UV_TOOL_DIR"

    if [ ! -x "$tools_dir/specify" ]; then
        echo "  spec-kit: installing specify-cli via uv tool..."
        if ! "$uv_bin" tool install --force specify-cli >"$tools_dir/spec-kit-install.log" 2>&1; then
            echo "  spec-kit: install failed — see tools/spec-kit-install.log"
            return 0
        fi
    else
        echo "  spec-kit: specify-cli already installed in tools/"
    fi

    # Snapshot SKILL.md hashes BEFORE init so we can prove re-running the
    # installer doesn't mutate them. Speckit-git skills in particular are
    # vendored in this repo and must not be overwritten by upstream
    # templates on every setup.sh run.
    local skills_dir="$root_dir/.claude/skills"
    local pre_hash_file; pre_hash_file=$(mktemp)
    if [ -d "$skills_dir" ]; then
        find "$skills_dir" -maxdepth 2 -name SKILL.md -type f 2>/dev/null | while read -r f; do
            if have md5; then md5 -q "$f"; elif have md5sum; then md5sum "$f" | awk '{print $1}'; else echo "no-md5"; fi
            printf '\t%s\n' "$f"
        done > "$pre_hash_file"
    fi

    if [ ! -d "$root_dir/.specify" ]; then
        echo "  spec-kit: running specify init --here (scaffold missing)..."
        (cd "$root_dir" && "$tools_dir/specify" init --here --ai claude --script sh --no-git --force >"$tools_dir/spec-kit-init.log" 2>&1) || \
            echo "  spec-kit: init failed — see tools/spec-kit-init.log"
    else
        echo "  spec-kit: scaffold already present at .specify/ (skipping init)"
    fi

    # Verify SKILL.md files are byte-identical post-init.
    if [ -s "$pre_hash_file" ]; then
        local post_hash_file; post_hash_file=$(mktemp)
        find "$skills_dir" -maxdepth 2 -name SKILL.md -type f 2>/dev/null | while read -r f; do
            if have md5; then md5 -q "$f"; elif have md5sum; then md5sum "$f" | awk '{print $1}'; else echo "no-md5"; fi
            printf '\t%s\n' "$f"
        done > "$post_hash_file"
        if ! diff -q "$pre_hash_file" "$post_hash_file" >/dev/null 2>&1; then
            echo "  spec-kit: WARN — SKILL.md hashes changed post-init. Review diff:"
            diff "$pre_hash_file" "$post_hash_file" | head -10
        fi
        rm -f "$post_hash_file"
    fi
    rm -f "$pre_hash_file"
}

# Require GITHUB_PERSONAL_ACCESS_TOKEN. Exit non-zero if --require-github
# is set AND the token is missing. Otherwise prints a warning + proceeds.
# Required scopes (minimum):
#   - repo            (read/write issues, PRs, commits)
#   - project         (read/write GH Projects board used by task workflow)
#   - read:org        (resolve Desk-Modal/* repo visibility)
check_github_token() {
    local require="${1:-0}"
    if [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
        echo "  github-token: present (scopes required: repo, project, read:org)"
        return 0
    fi
    if [ "$require" = "1" ]; then
        err "GITHUB_PERSONAL_ACCESS_TOKEN is required (--require-github). Export with scopes: repo, project, read:org."
        return 1
    fi
    echo "  github-token: not set — github-mcp-server and task workflow will be dormant"
    return 0
}

# Record a SHA-256 hash over the environment contract (setup.sh, hooks,
# mise.toml, .mcp.json, .claude/settings.json). The SessionStart
# `drift-check.sh` hook reads this and re-runs setup.sh --config-only
# when any of those files change, so every developer's next Claude
# session after a `git pull` self-heals.
record_drift_hash() {
    local root_dir="$1"
    local out="$root_dir/.session-state/setup-hash.txt"
    mkdir -p "$(dirname "$out")"

    local sha_cmd=""
    if have sha256sum; then sha_cmd="sha256sum"
    elif have shasum; then sha_cmd="shasum -a 256"
    else
        echo "  drift-hash: no sha256 tool available, skipping"
        return 0
    fi

    local files=(
        "$root_dir/scripts/setup.sh"
        "$root_dir/mise.toml"
        "$root_dir/.mcp.json"
        "$root_dir/.claude/settings.json"
    )
    local hook
    if [ -d "$root_dir/.claude/hooks" ]; then
        while IFS= read -r hook; do files+=("$hook"); done < \
            <(find "$root_dir/.claude/hooks" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | sort)
    fi

    local present=()
    for f in "${files[@]}"; do [ -f "$f" ] && present+=("$f"); done
    if [ ${#present[@]} -eq 0 ]; then
        echo "  drift-hash: no contract files found, skipping"
        return 0
    fi

    $sha_cmd "${present[@]}" > "$out"
    local combined
    combined=$($sha_cmd "${present[@]}" | $sha_cmd | awk '{print $1}')
    printf '# combined: %s\n' "$combined" >> "$out"
    echo "  drift-hash: recorded ${#present[@]} files -> .session-state/setup-hash.txt ($combined)"
}

# rust-analyzer-mcp (https://github.com/zeenix/rust-analyzer-mcp) — MCP
# bridge over the rust-analyzer LSP. Gives Claude Code semantic Rust
# queries (hover, references, workspace diagnostics, code actions) that
# the tree-sitter-based codebase-memory-mcp can't answer — trait
# dispatch, generic monomorphization, macro expansion. Installed via
# `cargo install --root $ROOT_DIR/tools` so the binary lands at
# $ROOT_DIR/tools/bin/rust-analyzer-mcp and the rest of the workspace
# never touches $HOME or the developer's global cargo install set.
# Requires `rust-analyzer` (the LSP itself) on PATH — step 3 above
# adds it via `rustup component add rust-analyzer`.
install_rust_analyzer_mcp() {
    local root_dir="$1"
    local pinned_version="${DESKMODAL_RUST_ANALYZER_MCP_VERSION:-0.2.0}"
    local tools_dir="$root_dir/tools"
    local bin_name="rust-analyzer-mcp"
    case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) bin_name="rust-analyzer-mcp.exe" ;; esac
    local out_bin="$tools_dir/bin/$bin_name"

    if ! have cargo; then
        echo "  rust-analyzer-mcp: cargo missing — skipped"
        return 0
    fi
    if ! have rust-analyzer; then
        echo "  rust-analyzer-mcp: rust-analyzer not on PATH — skipped (rustup component add rust-analyzer)"
        return 0
    fi

    mkdir -p "$tools_dir/bin"

    # The rust-analyzer-mcp binary does not honour --version; it ignores
    # the flag and begins serving on stdio. Use cargo's own install
    # manifest at $tools_dir/.crates.toml via `cargo install --list`.
    if [ -x "$out_bin" ] && \
       cargo install --list --root "$tools_dir" 2>/dev/null | \
            grep -Fq "rust-analyzer-mcp v$pinned_version"; then
        echo "  rust-analyzer-mcp: already pinned v$pinned_version"
        return 0
    fi

    echo "  rust-analyzer-mcp: installing v$pinned_version via cargo..."
    if ! cargo install --quiet --locked --root "$tools_dir" \
            --version "$pinned_version" rust-analyzer-mcp \
            >"$tools_dir/rust-analyzer-mcp-install.log" 2>&1
    then
        echo "  rust-analyzer-mcp: install failed — see tools/rust-analyzer-mcp-install.log"
        return 0
    fi
    echo "  rust-analyzer-mcp: installed -> tools/bin/$bin_name"
}

# github-mcp-server — the official GitHub MCP binary. Pinned at v1.0.0
# (checksums verified against the release's checksums.txt manifest,
# which GitHub signs via its release pipeline). Kept pinned intentionally
# — auto-updating would drift across developers.
install_github_mcp_server() {
    local dest_dir="$1"
    local tag="${DESKMODAL_GITHUB_MCP_TAG:-v1.0.0}"
    local out_bin="$dest_dir/github-mcp-server"
    case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) out_bin="$dest_dir/github-mcp-server.exe" ;; esac

    mkdir -p "$dest_dir"
    if [ -x "$out_bin" ] && "$out_bin" --version 2>/dev/null | grep -q "${tag#v}"; then
        echo "  github-mcp-server: already pinned at $tag"
        return 0
    fi

    local os arch asset
    case "$(uname -s)" in
        Darwin*)              os="Darwin" ;;
        Linux*)               os="Linux" ;;
        MINGW*|MSYS*|CYGWIN*) os="Windows" ;;
        *) echo "  github-mcp-server: unsupported OS — skipped"; return 0 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64)  arch="x86_64" ;;
        arm64|aarch64) arch="arm64" ;;
        *) echo "  github-mcp-server: unsupported arch — skipped"; return 0 ;;
    esac
    local ext="tar.gz"
    [ "$os" = "Windows" ] && ext="zip"
    asset="github-mcp-server_${tag#v}_${os}_${arch}.${ext}"

    local tmp; tmp=$(mktemp -d)
    if ! curl -sfL --max-time 120 -o "$tmp/$asset" \
        "https://github.com/github/github-mcp-server/releases/download/${tag}/${asset}"
    then
        echo "  github-mcp-server: download failed (offline?) — skipped"
        rm -rf "$tmp"; return 0
    fi
    if ! curl -sfL --max-time 30 -o "$tmp/checksums.txt" \
        "https://github.com/github/github-mcp-server/releases/download/${tag}/github-mcp-server_${tag#v}_checksums.txt"
    then
        echo "  github-mcp-server: checksum manifest fetch failed — aborting"
        rm -rf "$tmp"; return 0
    fi
    local sha_cmd=""
    have sha256sum && sha_cmd="sha256sum"
    [ -z "$sha_cmd" ] && have shasum && sha_cmd="shasum -a 256"
    if [ -n "$sha_cmd" ]; then
        local expected actual
        expected=$(awk -v a="$asset" '$2==a {print $1}' "$tmp/checksums.txt" | head -1)
        actual=$(cd "$tmp" && $sha_cmd "$asset" | awk '{print $1}')
        if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
            echo "  github-mcp-server: checksum mismatch — aborting (expected '$expected', got '$actual')"
            rm -rf "$tmp"; return 0
        fi
    fi
    if [ "$ext" = "zip" ]; then
        (cd "$tmp" && unzip -q "$asset")
    else
        (cd "$tmp" && tar -xzf "$asset")
    fi
    local bin_in_archive="github-mcp-server"
    [ "$os" = "Windows" ] && bin_in_archive="github-mcp-server.exe"
    local src; src=$(find "$tmp" -type f -name "$bin_in_archive" | head -1)
    [ -n "$src" ] || { echo "  github-mcp-server: binary not found in archive"; rm -rf "$tmp"; return 0; }
    install -m 755 "$src" "$out_bin" 2>/dev/null || { cp "$src" "$out_bin" && chmod 755 "$out_bin"; }
    rm -rf "$tmp"
    echo "  github-mcp-server: installed ${tag} -> tools/$(basename "$out_bin")"
}

# ---------------------------------------------------------------------------
# 0. Sub-repo clone map
#
# This is the single source of truth for how the Desk-Modal org maps onto
# the workspace directory layout. Change it here and nothing else needs to
# know — the rest of the script iterates this list.
#
# Format: "<target-path-relative-to-root>\t<Desk-Modal-repo-name>"
# ---------------------------------------------------------------------------
clones=(
    "platform                deskmodal"
    "plugins/tradesurface    tradesurface"
    "plugins/optiscript      optiscript"
    "plugin-tools            plugin-tools"
    "marketplace/appmarket   appmarket"
    "marketplace/plugin-index plugin-index"
    "core-server-api         core-server-api"
    "deploy-infra            deskmodal-deploy"
    "website                 deskmodal-website"
)

# ---------------------------------------------------------------------------
# 1. Bootstrap prerequisites (git + gh CLI must already be installed)
# ---------------------------------------------------------------------------
echo ""
echo "[1/10] Bootstrap prerequisites..."
if ! have git; then
    err "git not found. Install it first."
    if [ "$OS_KIND" = "darwin" ]; then
        echo "        macOS: xcode-select --install"
    fi
fi
if ! have gh; then
    err "gh (GitHub CLI) not found — required to clone private Desk-Modal repos."
    if [ "$OS_KIND" = "darwin" ]; then
        echo "        macOS: brew install gh && gh auth login"
    elif [ "$OS_KIND" = "linux" ]; then
        echo "        Linux: https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
    fi
fi
if have gh; then
    if ! gh auth status >/dev/null 2>&1; then
        err "gh is installed but not authenticated. Run: gh auth login"
    else
        echo "  gh: authenticated ($(gh api user --jq .login 2>/dev/null))"
    fi
fi
if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "Cannot continue until the errors above are fixed. Re-run this script after."
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Clone every sub-repo into the workspace layout
# ---------------------------------------------------------------------------
echo ""
echo "[2/10] Cloning Desk-Modal sub-repos..."
for entry in "${clones[@]}"; do
    # shellcheck disable=SC2086
    set -- $entry
    target_path="$1"
    repo_name="$2"
    full_path="$ROOT_DIR/$target_path"

    if [ -d "$full_path/.git" ]; then
        current_url=$(git -C "$full_path" remote get-url origin 2>/dev/null || echo "")
        expected="https://github.com/Desk-Modal/${repo_name}.git"
        if [[ "$current_url" == *"$repo_name"* ]]; then
            printf "  %-28s already cloned, fetching...\n" "$target_path"
            git -C "$full_path" fetch origin --quiet 2>&1 | sed 's/^/    /' || true
        else
            echo "  $target_path: directory exists but is NOT the expected repo"
            echo "    expected: $expected"
            echo "    found:    ${current_url:-<no origin>}"
            err "refusing to touch an unexpected repo at $full_path — resolve manually"
        fi
    else
        if [ -e "$full_path" ] && [ "$(find "$full_path" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
            err "$full_path exists and is non-empty but has no .git — resolve manually"
            continue
        fi
        printf "  %-28s cloning Desk-Modal/%s...\n" "$target_path" "$repo_name"
        mkdir -p "$(dirname "$full_path")"
        if ! gh repo clone "Desk-Modal/${repo_name}" "$full_path" -- --quiet; then
            err "failed to clone Desk-Modal/${repo_name}"
        fi
    fi
done
if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "Clone step hit errors. Fix and re-run."
    exit 1
fi

if [ "$CONFIG_ONLY" = 1 ]; then
    echo ""
    echo "(config-only) skipping steps 3-7; jumping to Claude Code tooling + scaffolding."
fi

# ---------------------------------------------------------------------------
# 3. Rust toolchain
# ---------------------------------------------------------------------------
if [ "$CONFIG_ONLY" = 0 ]; then
echo ""
echo "[3/10] Rust toolchain..."
if ! have rustup; then
    if [ "$OS_KIND" = "darwin" ] || [ "$OS_KIND" = "linux" ]; then
        echo "  Installing rustup (non-interactive)..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain none
        # shellcheck disable=SC1090
        . "$HOME/.cargo/env"
    else
        err "rustup not found. Install from https://rustup.rs"
    fi
fi

if have rustup; then
    REQUIRED_RUST="1.94.0"
    rustup install "$REQUIRED_RUST" --no-self-update 2>&1 | tail -2 || true
    # rust-analyzer is the component the rust-analyzer MCP server drives
    # over stdio. Every developer needs it on PATH for semantic queries
    # (hover, references, workspace diagnostics) that tree-sitter-based
    # CBM can't answer (trait dispatch, generic monomorphization, macros).
    # Every rust-toolchain.toml in this workspace declares `rust-analyzer`
    # in `components = [...]`, so rustup installs it automatically on
    # toolchain activation — this call is the safety-net. Failures are
    # LOUD (stderr + tools/rustup-components.log) so an offline machine
    # or a rustup-registry miss doesn't silently degrade the Rust dev
    # experience for an entire session.
    mkdir -p "$ROOT_DIR/tools"
    if ! rustup component add clippy rustfmt rust-analyzer --toolchain "$REQUIRED_RUST" \
            >"$ROOT_DIR/tools/rustup-components.log" 2>&1; then
        echo "  WARN: 'rustup component add clippy rustfmt rust-analyzer' failed" >&2
        echo "        (see tools/rustup-components.log). The rust-analyzer MCP will be degraded" >&2
        echo "        until a re-run succeeds (offline? try \`rustup update && scripts/setup.sh --config-only\`)" >&2
    fi
    rustup target add wasm32-unknown-unknown --toolchain "$REQUIRED_RUST" 2>/dev/null || true
    echo "  rustc: $(rustc --version 2>/dev/null || echo 'missing')"
    echo "  cargo: $(cargo --version 2>/dev/null || echo 'missing')"
    echo "  rust-analyzer: $(rust-analyzer --version 2>/dev/null || echo 'missing')"
fi

# ---------------------------------------------------------------------------
# 4. Node.js + pnpm
# ---------------------------------------------------------------------------
echo ""
echo "[4/10] Node.js + pnpm..."
if ! have node; then
    if [ "$OS_KIND" = "darwin" ] && have brew; then
        echo "  Installing node via Homebrew..."
        brew install node 2>&1 | tail -2 || true
    else
        err "Node.js not found. Install Node 20+ from https://nodejs.org"
    fi
fi
if have node; then
    echo "  node: $(node --version)"
fi

if ! have pnpm; then
    if have corepack; then
        echo "  Enabling pnpm via corepack..."
        corepack enable 2>&1 | tail -2 || true
        corepack prepare pnpm@latest --activate 2>&1 | tail -2 || true
    elif have npm; then
        echo "  Installing pnpm via npm..."
        npm install -g pnpm 2>&1 | tail -2 || true
    fi
fi
if have pnpm; then
    echo "  pnpm: $(pnpm --version)"
else
    err "pnpm not installed. Install manually: npm install -g pnpm"
fi

# ---------------------------------------------------------------------------
# 5. Python + protoc (build-time + CDP testing)
# ---------------------------------------------------------------------------
echo ""
echo "[5/10] Python + protoc..."
PYTHON=""
if have python3; then
    PYTHON=python3
elif have python; then
    PYTHON=python
fi

if [ -n "$PYTHON" ]; then
    echo "  python: $($PYTHON --version 2>&1)"
    # Install deps used by CDP verification scripts. Non-fatal.
    # pyyaml is required by scripts/quality-gates/latency-budget.sh +
    # sdk-surface-audit.sh; jsonschema is used to validate
    # specs/latency-budgets.yml against its schema.
    $PYTHON -m pip install --quiet --user websocket-client cryptography toml pyyaml jsonschema websockets 2>/dev/null || true
else
    err "python3 not found. macOS: brew install python3"
fi

if ! have protoc; then
    if [ "$OS_KIND" = "darwin" ] && have brew; then
        echo "  Installing protoc via Homebrew..."
        brew install protobuf 2>&1 | tail -2 || true
    elif [ "$OS_KIND" = "linux" ]; then
        echo "  WARN: protoc missing. Ubuntu: sudo apt-get install -y protobuf-compiler"
    fi
fi
if have protoc; then
    echo "  protoc: $(protoc --version)"
fi

# Semgrep — required by the claude-plugins-official/semgrep plugin's
# SessionStart hook (real-time security pattern scan). Without it, the
# plugin's hook prints "Semgrep not found" on every session start.
# See .claude/plugins.md for the plugin rationale.
if ! have semgrep; then
    if [ "$OS_KIND" = "darwin" ] && have brew; then
        echo "  Installing semgrep via Homebrew..."
        brew install semgrep 2>&1 | tail -2 || true
    elif [ -n "$PYTHON" ] && "$PYTHON" -m pip --version >/dev/null 2>&1; then
        echo "  Installing semgrep via pip..."
        "$PYTHON" -m pip install --quiet --user semgrep 2>&1 | tail -2 || true
    else
        echo "  WARN: semgrep not installed. macOS: brew install semgrep; Linux: python3 -m pip install --user semgrep"
    fi
fi
if have semgrep; then
    echo "  semgrep: $(semgrep --version 2>/dev/null | head -1)"
fi

# ---------------------------------------------------------------------------
# 6. Platform-specific system tools
# ---------------------------------------------------------------------------
echo ""
echo "[6/10] Platform system tools..."
if [ "$OS_KIND" = "darwin" ]; then
    if ! xcode-select -p >/dev/null 2>&1; then
        echo "  Xcode Command Line Tools not installed. Launching installer..."
        xcode-select --install 2>&1 | tail -2 || true
        echo "  Re-run this script once the CLT installer finishes."
        exit 1
    fi
    echo "  Xcode CLI tools: $(xcode-select -p)"
    # WebView is provided by WebKit on macOS — no separate install.
    echo "  WebKit: bundled with macOS"
elif [ "$OS_KIND" = "linux" ]; then
    echo "  Linux: ensure libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev libsoup-3.0-dev are installed"
elif [ "$OS_KIND" = "windows" ]; then
    echo "  Windows: WebView2 (bundled with Win11) + Visual Studio Build Tools 2022 C++ workload required"
fi

# ---------------------------------------------------------------------------
# 7. Cargo auxiliary tools (best-effort, non-fatal)
# ---------------------------------------------------------------------------
echo ""
echo "[7/10] Developer tools — cargo-deny / cargo-audit / mise..."

# Cargo tools: dep-graph auditing + CVE scanning. Cargo's own registry is
# authoritative; no version pin needed.
for tool in cargo-deny cargo-audit; do
    if have "$tool"; then
        echo "  $tool: $(command -v "$tool")"
    else
        echo "  Installing $tool..."
        cargo install "$tool" 2>&1 | tail -2 || echo "  WARN: $tool install failed (non-fatal)"
    fi
done

# mise — project-local tool version manager. Installs the exact Node,
# pnpm, Python, protoc versions declared in <workspace>/mise.toml.  The
# mise binary itself lives under <workspace>/tools/ so nothing leaks to
# $HOME or shell rc files; developers source `./activate.sh` (also in the
# workspace) when they want the pinned tools on PATH for a shell.
# ($MISE_BIN is defined at the top of the script so helper functions can
# reference it even under --config-only.)
mkdir -p "$ROOT_DIR/tools"
if [ ! -x "$MISE_BIN" ]; then
    echo "  Installing mise into tools/..."
    # The official installer honours MISE_INSTALL_PATH and never touches
    # shell rc when we don't pass --activate.
    MISE_INSTALL_PATH="$MISE_BIN" \
        curl -fsSL https://mise.run | sh >"$ROOT_DIR/tools/mise-install.log" 2>&1 || {
        echo "  WARN: mise install failed (non-fatal) — see tools/mise-install.log"
    }
fi
if [ -x "$MISE_BIN" ]; then
    echo "  mise: $("$MISE_BIN" --version 2>&1 | head -1)"
    (cd "$ROOT_DIR" && "$MISE_BIN" install --yes 2>&1 | tail -5) || \
        echo "  WARN: 'mise install' failed (non-fatal) — pinned versions unavailable"
else
    echo "  WARN: mise unavailable — pinned tool versions in mise.toml are not enforced"
fi

fi  # end "if [ \"$CONFIG_ONLY\" = 0 ]" — steps 3-7 run only in full mode

# ---------------------------------------------------------------------------
# 8. Claude Code tooling — codebase-memory-mcp + sub-repo scaffolding
#
# ALWAYS RUNS, even in --config-only mode: this is the target of
# drift-driven re-runs. The steps below are idempotent; the CBM binary
# self-updates and sub-repo scaffolds re-apply cleanly.
# ---------------------------------------------------------------------------
echo ""
echo "[8/10] Claude Code tooling — codebase-memory-mcp + knowledge graph..."

# ---------------------------------------------------------------------------
# 8. Claude Code integration — codebase-memory-mcp
#
# codebase-memory-mcp (CBM) builds a persistent tree-sitter knowledge graph
# of every repo in the workspace and serves it to Claude Code over stdio.
# search_graph / trace_path / get_code_snippet replace dozens of grep+read
# cycles with single structural queries, reducing context-window burn by
# ~99% on typical dev flows.
#
# The MCP binary is a self-contained static binary — no Rust / Node / Python
# runtime required. Installed into <workspace>/tools/ so every developer
# runs the exact same binary and every config can reference it via a
# workspace-relative path. Works identically on macOS, Linux, and Git Bash
# on Windows.
# ---------------------------------------------------------------------------
CBM_BIN_NAME="codebase-memory-mcp"
case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*) CBM_BIN_NAME="codebase-memory-mcp.exe" ;;
esac
CBM_BIN="$ROOT_DIR/tools/$CBM_BIN_NAME"

mkdir -p "$ROOT_DIR/tools"

# Defensively (re)apply exec bit on every workspace hook script. Git
# preserves 100755 in the index but some checkout paths (Windows clones
# with core.fileMode=false, tarball restores, Archive.zip downloads)
# drop it, which causes `/bin/sh: ...: Permission denied` on session
# start. Settings also use `bash <script>` invocation as a belt-and-
# braces fallback, but chmod is the right fix where possible.
if [ -d "$ROOT_DIR/.claude/hooks" ]; then
    chmod +x "$ROOT_DIR/.claude/hooks/"*.sh 2>/dev/null || true
fi

# Install or self-update CBM into the workspace tools dir. Idempotent —
# the binary self-updates when present, bootstraps from GitHub releases
# when not.
if [ -x "$SCRIPT_DIR/install-codebase-memory-mcp.sh" ]; then
    "$SCRIPT_DIR/install-codebase-memory-mcp.sh" --quiet "--dir=$ROOT_DIR/tools" || \
        err "codebase-memory-mcp install failed"
else
    err "scripts/install-codebase-memory-mcp.sh missing — cannot install CBM"
fi

# uv is needed by install_spec_kit. Install it
# before the Python-tool installers fire. On a fresh machine mise will
# not have hydrated uv yet, so install_uv also handles that bootstrap.
install_uv "$ROOT_DIR/tools"

# Spec Kit — specify-cli + the .specify/ scaffold. Idempotent: once
# .specify/ is present the init call is skipped. Speckit skills in
# .claude/skills/speckit-*/ are verified byte-stable across re-runs.
install_spec_kit "$ROOT_DIR"

# rust-analyzer MCP — unconditional (every Rust dev session benefits).
# Requires cargo + rust-analyzer from phase 3; the helper no-ops if
# either is missing, so config-only re-runs on partial machines are safe.
install_rust_analyzer_mcp "$ROOT_DIR"

# Conditional MCPs — gated on the developer having a relevant API token in
# their environment. The entries are pinned in .mcp.json unconditionally;
# Claude Code just logs a warning and moves on if the binary is missing.
if [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    install_github_mcp_server "$ROOT_DIR/tools"
else
    echo "  github-mcp-server: skipped — export GITHUB_PERSONAL_ACCESS_TOKEN to enable"
fi
# Announce GitHub token state. Non-fatal by default; pass
# --require-github to setup.sh to make it fail hard.
check_github_token "$REQUIRE_GITHUB"

# Index each sub-repo so Claude Code sessions opened in any directory have
# a live graph. auto_index picks up changes afterwards; we seed explicitly
# so the first Claude session doesn't pay the indexing cost synchronously.
if [ -x "$CBM_BIN" ]; then
    "$CBM_BIN" config set auto_index true >/dev/null 2>&1 || true
    "$CBM_BIN" config set auto_index_limit 100000 >/dev/null 2>&1 || true

    for repo in \
        "$ROOT_DIR" \
        "$ROOT_DIR/platform" \
        "$ROOT_DIR/plugins/tradesurface" \
        "$ROOT_DIR/plugins/optiscript" \
        "$ROOT_DIR/plugin-tools" \
        "$ROOT_DIR/marketplace/appmarket" \
        "$ROOT_DIR/marketplace/plugin-index" \
        "$ROOT_DIR/core-server-api"
    do
        [ -d "$repo/.git" ] || continue
        name=$(basename "$repo")
        # The CLI requires an absolute path at call time. Emit JSON to a
        # log; only surface errors. The path is used by CBM internally —
        # it's not written into any tracked or shared artefact.
        if "$CBM_BIN" cli index_repository "{\"repo_path\":\"$repo\"}" \
            >>"$ROOT_DIR/tools/cbm-index.log" 2>&1
        then
            echo "  Indexed: $name"
        else
            echo "  WARN: index failed for $name — see tools/cbm-index.log"
        fi
    done
fi

# ---------------------------------------------------------------------------
# 8b. Per-sub-repo Claude Code scaffolding.
#
# Each nested git repo (platform/, plugins/tradesurface/, plugins/optiscript/,
# plugin-tools/, marketplace/*, core-server-api/) is its own Claude "project"
# when the developer opens Claude inside it. Without local scaffolding the
# workspace-root .mcp.json + .claude/ never apply.
#
# Policy:
#   * Never modify tracked files inside sub-repos (they belong to upstream).
#   * Write only git-ignored artefacts: `.claude/settings.local.json` and
#     a `.mcp.json` recorded in `.git/info/exclude` (per-clone exclusion,
#     never committed). This gives every sub-repo the MCP + hooks without
#     polluting its git working tree.
# ---------------------------------------------------------------------------
exclude_in_git() {
    local repo="$1"; shift
    local exclude_file="$repo/.git/info/exclude"
    [ -f "$exclude_file" ] || touch "$exclude_file"
    for pattern in "$@"; do
        grep -qxF "$pattern" "$exclude_file" 2>/dev/null || echo "$pattern" >> "$exclude_file"
    done
}

# install_github_mcp_server() moved to the "Helper functions" section at
# the top of this file so the Phase 8 block below can call it without
# forward-reference bugs. The older duplicate definition lived here.

# Return the relative path prefix from a sub-repo back to the workspace
# root, including a trailing slash. Example: for $ROOT_DIR/plugins/tradesurface
# this returns "../../".  Works on macOS, Linux, and Git Bash — no GNU
# realpath required.
workspace_relative_prefix() {
    local repo="$1"
    local rel depth=0 tail="${repo#"$ROOT_DIR"}"
    tail="${tail#/}"
    # Count path separators in the tail to derive how many levels to ascend.
    if [ -n "$tail" ]; then
        IFS='/' read -r -a parts <<<"$tail"
        depth=${#parts[@]}
    fi
    rel=""
    local i=0
    while [ "$i" -lt "$depth" ]; do
        rel="${rel}../"
        i=$((i + 1))
    done
    echo "$rel"
}

scaffold_sub_repo_claude() {
    local repo="$1"
    [ -d "$repo/.git" ] || return 0

    # Copy (don't symlink — Windows Git Bash without admin rights can't make
    # symlinks) the hook scripts from the workspace into each sub-repo's
    # .claude/hooks/. Each sub-repo becomes a self-contained Claude project
    # whose hooks resolve via $CLAUDE_PROJECT_DIR — no workspace-root
    # reference, no machine-specific absolute paths baked into settings.
    mkdir -p "$repo/.claude/hooks"
    # Propagate EVERY workspace hook (not just CBM/drift). The prior
    # static list missed post-commit-handoff.sh (task 002),
    # commit-message-honesty.sh (task 007), handoff-nudge.sh,
    # push-nudge.sh, pre-commit-guard.sh, session-handoff-load.sh —
    # teammates working in sub-repos then silently skipped those
    # enforcement paths. The dynamic loop copies whatever
    # .claude/hooks/*.sh is committed at the workspace root.
    for src in "$ROOT_DIR"/.claude/hooks/*.sh; do
        [ -f "$src" ] || continue
        local hook
        hook=$(basename "$src")
        cp -f "$src" "$repo/.claude/hooks/$hook"
        chmod +x "$repo/.claude/hooks/$hook" 2>/dev/null || true
    done

    # Propagate workspace SDLC surface into the sub-repo so a Claude session
    # opened inside the sub-repo (cwd != workspace root) has the same 24
    # personas, 7 rules, and Spec Kit constitution available. Sub-repos that
    # git-track their own .claude/<dir>/ (e.g. tradesurface has its own
    # agents/) are left alone on a per-file basis — we never clobber a
    # git-tracked upstream file.
    mkdir -p "$repo/.claude/agents" "$repo/.claude/rules" "$repo/.specify/memory" "$repo/.specify/templates"
    for subdir in agents rules; do
        local src_dir="$ROOT_DIR/.claude/$subdir"
        [ -d "$src_dir" ] || continue
        for src in "$src_dir"/*.md; do
            [ -f "$src" ] || continue
            local name="${src##*/}"
            # Skip if the sub-repo's upstream already owns this file.
            if git -C "$repo" ls-files --error-unmatch ".claude/$subdir/$name" >/dev/null 2>&1; then
                continue
            fi
            cp -f "$src" "$repo/.claude/$subdir/$name"
        done
    done
    for specfile in memory/constitution.md templates/tasks-template.md templates/spec-template.md templates/plan-template.md; do
        local src="$ROOT_DIR/.specify/$specfile"
        [ -f "$src" ] || continue
        if git -C "$repo" ls-files --error-unmatch ".specify/$specfile" >/dev/null 2>&1; then
            continue
        fi
        cp -f "$src" "$repo/.specify/$specfile"
    done

    # Compute the workspace-relative path from this sub-repo back to
    # <workspace>/tools/ (e.g. "../" for platform/, "../../" for
    # plugins/tradesurface/). Keeps every config free of user-home paths.
    local rel_to_root
    rel_to_root=$(workspace_relative_prefix "$repo")

    # Per-project MCP config — command is expressed as
    # ${CLAUDE_PROJECT_DIR}/<rel>/tools/codebase-memory-mcp, which Claude
    # Code expands at runtime to an absolute path rooted at this sub-repo.
    # Identical content shape on macOS, Linux, Windows.
    # Regenerate .mcp.json whenever upstream doesn't track it — the file
    # is git-ignored per-clone scaffolding, so adding or removing an MCP
    # entry at the workspace root must fan out to every sub-repo on the
    # next setup.sh run. The upstream-tracked check prevents clobbering
    # sub-repos that ship their own .mcp.json (currently none, but
    # future-proofs the script).
    if ! git -C "$repo" ls-files --error-unmatch .mcp.json >/dev/null 2>&1; then
        # Self-contained .mcp.json that mirrors the workspace-root set
        # (codebase-memory-mcp, rust-analyzer, github) with paths
        # relative from the sub-repo back to <workspace>/tools/. Every
        # env var the commands reference is declared in the `env` block
        # so Claude Code's `/doctor` static check doesn't warn about
        # "missing environment variables" — CLAUDE_PROJECT_DIR is
        # auto-injected by Claude, but listing it makes the check happy.
        # Optional secrets (GITHUB_PAT) produce legit warnings when
        # unset; teammates see them and know to export.
        cat > "$repo/.mcp.json" <<MCP
{
  "mcpServers": {
    "codebase-memory-mcp": {
      "type": "stdio",
      "command": "\${CLAUDE_PROJECT_DIR}/${rel_to_root}tools/codebase-memory-mcp",
      "env": {
        "CLAUDE_PROJECT_DIR": "\${CLAUDE_PROJECT_DIR}"
      }
    },
    "rust-analyzer": {
      "type": "stdio",
      "command": "\${CLAUDE_PROJECT_DIR}/${rel_to_root}tools/bin/rust-analyzer-mcp",
      "env": {
        "CLAUDE_PROJECT_DIR": "\${CLAUDE_PROJECT_DIR}"
      }
    },
    "github": {
      "type": "stdio",
      "command": "\${CLAUDE_PROJECT_DIR}/${rel_to_root}tools/github-mcp-server",
      "args": ["stdio"],
      "env": {
        "CLAUDE_PROJECT_DIR": "\${CLAUDE_PROJECT_DIR}",
        "GITHUB_PERSONAL_ACCESS_TOKEN": "\${GITHUB_PERSONAL_ACCESS_TOKEN}"
      }
    }
  }
}
MCP
    fi

    # settings.local.json — hook commands use $CLAUDE_PROJECT_DIR, which
    # Claude Code expands at run time to whichever sub-repo the session was
    # opened in.  Drift-check runs first so that if the developer has
    # pulled workspace-root changes, the sub-repo's own scaffolding gets
    # refreshed before anything else fires. The quotes around the paths
    # are essential on Windows where the expanded path may contain spaces.
    #
    # The `env` block is machine-local:
    #   * CLAUDE_PROJECT_DIR is pinned to the workspace root ($ROOT_DIR
    #     computed at setup time) so the committed .mcp.json's
    #     `${CLAUDE_PROJECT_DIR}/tools/...` paths resolve to the parent
    #     workspace's vendored tool binaries — which live only at the
    #     root, not in each sub-repo. Without this pin, Claude Code
    #     auto-injects CLAUDE_PROJECT_DIR as the sub-repo path and the
    #     MCP tools fail to launch.
    #   * GITHUB_PERSONAL_ACCESS_TOKEN is passed through from the
    #     developer's shell env (no secrets baked into files). Listing
    #     the key silences Claude Code's /doctor static check even when
    #     the value is unset.
    # Absolute path is portable because the file is git-ignored
    # (per-clone scaffold) — on another developer's clone setup.sh
    # recomputes $ROOT_DIR from their SCRIPT_DIR.
    # Every hook in the workspace-root `.claude/settings.json` is
    # mirrored into the sub-repo settings.local.json so a Claude session
    # opened inside platform/, plugins/tradesurface/, optiscript/, etc.
    # enforces the same discipline (drift-check, CBM gate,
    # commit-driven handoffs, push-nudge) as a root session. The
    # single-writer invariant for .session-state/handoff.md is preserved
    # because CLAUDE_PROJECT_DIR is pinned above to the workspace root
    # — every hook resolves to the same path regardless of which
    # sub-repo the session was opened in.
    cat > "$repo/.claude/settings.local.json" <<SETTINGS
{
  "env": {
    "CLAUDE_PROJECT_DIR": "$ROOT_DIR",
    "GITHUB_PERSONAL_ACCESS_TOKEN": "\${GITHUB_PERSONAL_ACCESS_TOKEN}"
  },
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear",
        "hooks": [
          { "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/drift-check.sh\"" },
          { "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/cbm-session-reminder.sh\"" },
          { "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/cbm-update-latest.sh\"" },
          { "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/session-handoff-load.sh\"" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Grep|Glob|Read",
        "hooks": [
          { "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/cbm-code-discovery-gate.sh\"" }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          { "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/wave-foreground-enforce.sh\"" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/post-commit-handoff.sh\"" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/handoff-nudge.sh\"" },
          { "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/push-nudge.sh\"" }
        ]
      }
    ]
  }
}
SETTINGS

    # CLAUDE.md — 10-line pointer to the workspace root. The root is the
    # single source of truth (see scripts/sync-specs.sh). Build targets
    # that vary per sub-repo are listed inline below so a Claude session
    # opened here knows the native command without a round-trip.
    #
    # Always regenerate unless upstream (Desk-Modal/<repo>) tracks it —
    # the template was trimmed in Phase 7 and we don't want stale long-
    # form copies lying around in sub-repo working trees.
    local claude_tracked=0
    if git -C "$repo" ls-files --error-unmatch CLAUDE.md >/dev/null 2>&1; then
        claude_tracked=1
    fi
    if [ $claude_tracked -eq 0 ]; then
        local repo_name; repo_name=$(basename "$repo")
        local rel_workspace="${rel_to_root%/}"
        [ -z "$rel_workspace" ] && rel_workspace="."
        local build_cmd
        case "$repo_name" in
            platform)       build_cmd="cargo build -p deskmodal-agent" ;;
            tradesurface)   build_cmd="pnpm nx run-many --target=build --all" ;;
            optiscript)     build_cmd="cargo build -p optiscript-service" ;;
            plugin-tools)   build_cmd="cargo build --release --bin dmpkg" ;;
            appmarket)      build_cmd="python scripts/validate.py (root)" ;;
            plugin-index)   build_cmd="python scripts/validate_plugin_index.py (root)" ;;
            core-server-api) build_cmd="cargo build" ;;
            *)              build_cmd="see $rel_workspace/CLAUDE.md" ;;
        esac
        cat > "$repo/CLAUDE.md" <<CLAUDE_MD
# $repo_name — pointer

Canonical context at **$rel_workspace/CLAUDE.md** and **$rel_workspace/.claude/rules/**.
Spec Kit assets at **$rel_workspace/.specify/**.

| Local build | \`$build_cmd\` |
|---|---|
| Full workspace CI | \`$rel_workspace/scripts/local-ci.sh --fast\` |

Use CBM (\`search_graph\` / \`trace_path\` / \`get_code_snippet\`) before Grep/Read on code.
CLAUDE_MD
    fi

    # Policy (2026-04-20 directive): share .claude/ (minus settings.local.json),
    # CLAUDE.md, .mcp.json, .specify/ across developers — these become
    # tracked files in each sub-repo so every teammate gets the same
    # agents / rules / skills / hooks / MCPs on `git clone`, not just
    # those who run setup.sh. The sync-specs.sh canonical flow keeps
    # them aligned with the workspace root.
    #
    # The ONLY file that stays machine-local is .claude/settings.local.json
    # (per-developer overrides — API keys, local model preferences, etc.).
    local exclude_paths=(
        ".claude/settings.local.json"
    )
    exclude_in_git "$repo" "${exclude_paths[@]}"

    echo "  Scaffolded: $(basename "$repo")"
}

for repo in \
    "$ROOT_DIR/platform" \
    "$ROOT_DIR/plugins/tradesurface" \
    "$ROOT_DIR/plugins/optiscript" \
    "$ROOT_DIR/plugin-tools" \
    "$ROOT_DIR/marketplace/appmarket" \
    "$ROOT_DIR/marketplace/plugin-index" \
    "$ROOT_DIR/core-server-api"
do
    scaffold_sub_repo_claude "$repo"
done

if [ "$CONFIG_ONLY" = 0 ]; then

# ---------------------------------------------------------------------------
# 9. Build dmpkg + workspaces + dist/
# ---------------------------------------------------------------------------
echo ""
echo "[9/10] Building workspaces + dist/..."

# Install tradesurface npm deps before build-dist.sh runs nx
if [ -d "$ROOT_DIR/plugins/tradesurface" ] && have pnpm; then
    echo "  pnpm install (tradesurface)..."
    (cd "$ROOT_DIR/plugins/tradesurface" && pnpm install --frozen-lockfile 2>&1 | tail -3) || \
        (cd "$ROOT_DIR/plugins/tradesurface" && pnpm install 2>&1 | tail -3) || \
        err "pnpm install failed"
fi

echo "  Building dmpkg (needed by build-dist.sh signing step)..."
(cd "$ROOT_DIR/plugin-tools" && cargo build --release --bin dmpkg 2>&1 | tail -2) || \
    err "dmpkg build failed"

echo "  Running build-dist.sh --release --sign..."
if "$SCRIPT_DIR/build-dist.sh" --release --sign 2>&1 | tail -15; then
    echo "  dist/ populated at $ROOT_DIR/dist/"
else
    err "build-dist.sh failed — see output above"
fi

# ---------------------------------------------------------------------------
# 10. Fast sanity check — local-ci.sh --fast
# ---------------------------------------------------------------------------
echo ""
echo "[10/10] Sanity check: local-ci.sh --fast..."
if "$SCRIPT_DIR/local-ci.sh" --fast 2>&1 | tail -10; then
    echo "  Sanity check OK"
else
    echo "  WARN: fast CI reported failures — inspect the output above"
fi

fi  # end "if [ \"$CONFIG_ONLY\" = 0 ]" — steps 9-10

# ---------------------------------------------------------------------------
# Optional: GUI test harness (--with-gui-tests)
#
# Installs the cross-platform Appium/XCUITest-based GUI test harness into
# tools/gui/. The vendored install never touches global npm/Homebrew/cargo
# state. Without --with-gui-tests, every GUI prod-check gate stays BLOCKED
# with a pointer to this flag, so nothing breaks for opt-out developers.
# ---------------------------------------------------------------------------
if [ "$WITH_GUI_TESTS" = 1 ]; then
    echo ""
    case "$OS_KIND" in
        darwin)  installer="$ROOT_DIR/tests/gui/setup/install-darwin.sh" ;;
        linux)   installer="$ROOT_DIR/tests/gui/setup/install-linux.sh" ;;
        windows)
            echo "  --with-gui-tests on Git Bash for Windows: run tests/gui/setup/install-windows.ps1 from PowerShell"
            installer=""
            ;;
        *)       installer="" ;;
    esac
    if [ -n "$installer" ] && [ -x "$installer" ]; then
        bash "$installer" || echo "  GUI harness installer returned non-zero — see output above"
    elif [ -n "$installer" ]; then
        echo "  GUI harness installer missing or not executable: $installer"
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
if [ $ERRORS -eq 0 ]; then
    cat <<SUMMARY
  Setup complete. Zero errors.

  Next:
    ./dist/DeskModal                    # Launch the agent
    ./scripts/local-ci.sh --fast        # Quick gate check
    ./scripts/local-ci.sh --full        # Full CI gates (pre-push)
    ./scripts/release.sh tradesurface --bump patch --push

  Sub-repo layout:
    platform/                   Desk-Modal/deskmodal
    plugins/tradesurface/       Desk-Modal/tradesurface
    plugins/optiscript/         Desk-Modal/optiscript
    plugin-tools/               Desk-Modal/plugin-tools
    marketplace/appmarket/      Desk-Modal/appmarket
    marketplace/plugin-index/   Desk-Modal/plugin-index
    deploy-infra/               Desk-Modal/deskmodal-deploy
    core-server-api/            Desk-Modal/core-server-api
    website/                    Desk-Modal/deskmodal-website
SUMMARY
else
    echo "  Setup completed with $ERRORS error(s). Fix and re-run."
fi

# ---------------------------------------------------------------------------
# Install the root pre-commit hook (copy, not symlink — Git Bash on
# Windows without admin rights can't make symlinks). The hook calls
# scripts/sync-specs.sh --check and refuses commits that touch canonical
# root paths without keeping sub-repos in sync.
# ---------------------------------------------------------------------------
if [ -f "$ROOT_DIR/scripts/pre-commit.sh" ] && [ -d "$ROOT_DIR/.git/hooks" ]; then
    cp -f "$ROOT_DIR/scripts/pre-commit.sh" "$ROOT_DIR/.git/hooks/pre-commit"
    chmod +x "$ROOT_DIR/.git/hooks/pre-commit" 2>/dev/null || true
    echo "  pre-commit: installed at .git/hooks/pre-commit"
fi

# ---------------------------------------------------------------------------
# Install the commit-msg hook that enforces
# .claude/rules/honesty.md §2 banned-phrase + citation requirement.
# Implemented in .claude/hooks/commit-message-honesty.sh; the installed
# file under .git/hooks/commit-msg is a copy of scripts/commit-msg.sh
# (3-line wrapper). Bypass via DESKMODAL_LAX=1 per the same convention
# as qg_honor_lax (scripts/quality-gates/lib/common.sh:180-206).
# ---------------------------------------------------------------------------
if [ -f "$ROOT_DIR/scripts/commit-msg.sh" ] && [ -d "$ROOT_DIR/.git/hooks" ]; then
    cp -f "$ROOT_DIR/scripts/commit-msg.sh" "$ROOT_DIR/.git/hooks/commit-msg"
    chmod +x "$ROOT_DIR/.git/hooks/commit-msg" 2>/dev/null || true
    echo "  commit-msg: installed at .git/hooks/commit-msg"
fi

# ---------------------------------------------------------------------------
# Record the drift hash. SessionStart `drift-check.sh` compares this to
# the live hash of the env-contract files; a mismatch re-runs
# `scripts/setup.sh --config-only` automatically, so every developer's
# next Claude session after a `git pull` self-heals.
# ---------------------------------------------------------------------------
record_drift_hash "$ROOT_DIR"
echo "============================================"
