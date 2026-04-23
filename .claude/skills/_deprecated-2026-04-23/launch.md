---
description: "Build, deploy, and launch DeskModal. Always runs local CI first."
user-invocable: true
---

# /launch [mode]

Build, deploy, and launch DeskModal. **CI must pass before launch.**

## Modes

| Mode | CI gate | Build | Launch |
|------|---------|-------|--------|
| `/launch` | fast (fmt+clippy) | debug | yes |
| `/launch full` | full (all gates+tests) | debug+sign | yes |
| `/launch release` | full | release+sign | yes |

## Execution

1. **Run local CI** — `./scripts/local-ci.sh --fast` (or `--full` for full/release mode). **STOP if this fails.**
2. **Build dist/** — `./scripts/build-dist.sh [--release] --sign`. Populates `dist/DeskModal{.app,.exe}` (flat at dist root) and `dist/plugins/<plugin-id>/`.
3. **Launch** — `./scripts/launch.sh`. Kills existing instance, runs directly from dist/, enables CDP on port 9222.

**No deploy step needed.** dist/ IS the runtime. Logs / storage live under `dist/data/` so the install is fully portable; `~/.deskmodal/` is only used as a fallback when no `config/desk.toml` marker sits next to the binary.
5. **Validate** — After launch, wait 5s then:
   - `curl -s http://localhost:9222/json/list` — verify WebView targets appear
   - Check logs: `tail dist/data/logs/desk.log.*` — verify services loaded + signatures verified
   - `python scripts/cdp-test-runner.py` — automated app validation

## Quick Commands (from repo root)

```bash
# Fast: lint + build + launch (most common during development)
./scripts/launch.sh --fast-build

# Full: all CI gates + build + sign + launch
./scripts/launch.sh --build

# Just launch (dist/ must already exist from a prior build)
./scripts/launch.sh
```

## Platform Binary Location

After build the binary sits at the **root** of `dist/` (flat layout, platform-specific shape):
```
dist/DeskModal.app/Contents/MacOS/DeskModal   # macOS (.app bundle — Dock icon, Cmd-Tab, etc.)
dist/DeskModal                                # Linux
dist/DeskModal.exe                            # Windows
```

`install_root()` walks up from the binary looking for `config/desk.toml`, so the `.app`-nested binary still resolves `dist/` correctly (4 levels up). User data lives next to the binary at `dist/data/` — logs, SQLite, keys all travel with the install dir.

## DeskModal Icon

The app icon is configured in `platform/apps/deskmodal-agent/src-tauri/tauri.conf.json`:
- Windows: `icon.ico` (bundled into .exe by Tauri)
- macOS: `icon.icns` (bundled into .app by Tauri)
- Tray: `tray.png` (system tray icon)

Icons source: `platform/apps/deskmodal-agent/src-tauri/icons/`

## NEVER
- Launch without CI passing
- Deploy unsigned service binaries
- Launch from `platform/target/` directly in production (use dist/)
