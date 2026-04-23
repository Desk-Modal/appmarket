---
name: DeskModal Plugin Development Guide
description: How to build, deploy, and debug tradesurface as a DeskModal plugin — deployment paths, HTML requirements, FDC3 injection, manifest format
type: reference
---

## Building & Running DeskModal

```bash
cd platform/
cargo build -p deskmodal-agent
./target/debug/deskmodal-agent.exe
```

Kill before rebuilding: `taskkill /f /im deskmodal-agent.exe` (may need to `mv` the exe if locked).

## Plugin Deployment Location

**`~/.deskmodal/plugins/tradesurface/`** (NOT `~/.desk/plugins/`)

```
├── plugin.toml              # Plugin manifest (apps, WASM, workspaces)
├── icons/*.svg              # App icons (read as data URIs on startup)
├── apps/{name}/             # One dir per app
│   ├── index.html           # Entry point (served via deskmodal-plugin://)
│   └── assets/              # JS/CSS bundles
└── workspaces/*.toml        # Workspace templates
```

## Critical HTML Requirements

1. **No `crossorigin` attribute** on `<script type="module">` tags — breaks custom URI scheme
2. **Relative paths** — use `src="./assets/..."` not `src="/assets/..."`
3. DeskModal auto-injects into HTML served via `deskmodal-plugin://`:
   - Viewport CSS (margin/padding reset, `#root { width:100%; height:100% }`)
   - FDC3 client for iframe mode (postMessage-based `window.fdc3` + `fdc3Ready` event)

## How Apps Are Loaded

- **Standalone window**: Tauri WebView with preload script providing `window.fdc3` via IPC
- **Tile in shell**: `<iframe src="http://deskmodal-plugin.localhost/{plugin}/{asset_root}/{app}/index.html">` with injected postMessage FDC3 client
- Both modes inject viewport-filling CSS — apps should use `height: 100%` not `height: 100vh`

## Plugin Manifest Format (plugin.toml)

```toml
[plugin]
name = "tradesurface"
version = "0.1.0"

[apps]
asset_root = "apps"

[[apps.entries]]
appId = "tradesurface.feeds"
name = "Tradesurface Price Feed Hub"
type = "web"
path = "feeds"                    # → apps/feeds/index.html
title = "Price Feed Hub"

[apps.entries.icons]
src = "icons/feeds.svg"           # Relative to plugin dir

[apps.entries.interop.intents.listensFor.ViewChart]
displayName = "View Chart"
contexts = ["fdc3.instrument"]

[apps.entries.interop.userChannels]
broadcasts = ["fdc3.instrument"]
listensFor = ["fdc3.quote"]
```

## FDC3 API Available in Apps

`window.fdc3` is available after `fdc3Ready` event:

```js
window.addEventListener('fdc3Ready', () => {
  fdc3.broadcast(context)
  fdc3.addContextListener('fdc3.instrument', handler)  // → Promise<Listener>
  fdc3.raiseIntent('ViewChart', context)
  fdc3.getUserChannels()           // → Promise<Channel[]>
  fdc3.joinUserChannel(channelId)
  fdc3.getCurrentChannel()
  fdc3.getInfo()
});
```

## Debugging Tips

- DeskModal reads plugins at startup only — **restart after deploying**
- Check icons exist at `icons/{name}.svg` — missing icons show monogram fallback
- If app is blank in standalone window: right-click → Inspect Element to see console errors
- If app is blank as tile: check browser DevTools console in the main window (F12)
- The CSP allows: `deskmodal-plugin:`, `http://deskmodal-plugin.localhost`, `data:`, `blob:`

## Post-Build Deploy Script

```bash
# After Vite build
for app in feeds chart watchlist depth analytics screener alerts editor; do
  cp -r apps/$app/build/* ~/.deskmodal/plugins/tradesurface/apps/$app/
done
# Remove crossorigin from HTML (Vite adds it, breaks custom URI scheme)
sed -i 's/ crossorigin//g' ~/.deskmodal/plugins/tradesurface/apps/*/index.html
```
