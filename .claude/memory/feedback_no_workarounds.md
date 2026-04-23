---
name: No Workarounds — Mission-Critical Implementations Only
description: Never use workarounds or hacks. Always fix root causes. 100% deterministic builds required.
type: feedback
---

Never use workarounds, hacks, or bypasses. Always fix root causes properly.

**Why:** This is a mission-critical trading platform. Workarounds introduce non-determinism, mask real issues, and compound into reliability problems. The user explicitly requires 100% determinism.

**How to apply:**
- If a build fails, fix the root cause (e.g., AV file locks → add exclusions, not `emptyOutDir: false`)
- If a test fails, fix the code, not the test
- If a process has a gap, fix the process, not the symptom
- Never use `--force`, `--no-verify`, `emptyOutDir: false`, or similar flags as substitutes for proper fixes
- If a proper fix requires user action (reboot, admin permissions, config change), communicate that directly
