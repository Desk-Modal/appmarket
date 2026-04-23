---
name: GUI testing via CDP
description: GUI testing uses CDP (port 9222) inside DeskModal WebViews — never take mouse/keyboard control, never use standalone dev servers
type: feedback
---

GUI testing MUST use Chrome DevTools Protocol (CDP) to interact with DeskModal WebViews programmatically. This allows testing without taking control of the user's mouse/keyboard — they can continue working in other windows.

**Why:** The apps run inside DeskModal's WebView2 with FDC3 injection, custom URI schemes, and viewport CSS. Testing against standalone dev servers doesn't validate the real deployment path. And taking mouse/keyboard control blocks the user from doing other work.

**How to apply:**
1. Launch DeskModal with CDP: `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--remote-debugging-port=9222" cargo run -p deskmodal-agent`
2. List targets: `curl -s http://localhost:9222/json/list`
3. Connect via WebSocket to the target's `webSocketDebuggerUrl`
4. Use CDP commands:
   - `Page.captureScreenshot` — visual verification
   - `Runtime.evaluate` — DOM assertions, state inspection
   - `Input.dispatchMouseEvent` / `Input.dispatchKeyEvent` — interaction (inside WebView, not physical)
5. Python `websockets` module is installed for CDP communication

**Rules:**
- NEVER use mcp__screen-capture-mcp__take_screenshot (blocks user's screen)
- NEVER take physical mouse/keyboard control
- CDP input events go to WebView internals only
- Take before/after screenshots for visual fixes
- Deploy fresh builds to `~/.deskmodal/plugins/tradesurface/` before testing
