---
name: Do not push to git remotes or invoke CI during this work stream
description: Remote pushes cost real money — halt all git push / gh workflow run / repository_dispatch / release-create operations until explicitly unblocked
type: feedback
originSessionId: 52daa5a6-91e7-4fa7-990b-26a30d0b15b5
---

**CRITICAL — costs real money.** Every `git push` fires billable GitHub Actions workflows. Every `gh workflow run` does the same. Do not do either without explicit product-owner approval for each action.

Repos in scope: deskmodal, tradesurface, appmarket, paper-trading, service-sdk, price-feed-service, and any other Desk-Modal GitHub repo.

**Why:**
1. GitHub Actions minutes are billable. Multiple repos + multiple workflows (aggregate.yml, validate.yml, release.yml, ci.yml, codeql, cache-cleanup) multiply quickly.
2. Partial pushes during a multi-repo rework fire the appmarket aggregator on incomplete state and could publish a broken catalog to the live CDN.
3. The product owner wants a single coordinated cutover after all local work lands.

**How to apply:**
- Local `git commit` is fine and encouraged — keeps work organized and reviewable.
- `git push`: FORBIDDEN without explicit per-action approval.
- `gh workflow run`, `gh release create`, `gh pr create`: FORBIDDEN without explicit per-action approval.
- `repository_dispatch` events: FORBIDDEN.
- When spawning agents for tasks that would normally commit+push, the prompt MUST say explicitly: "commit locally only, do not push, do not invoke any gh command that triggers CI".
- Pre-flight check before any remote-touching action: ask the user.

**Historical note:** Earlier in 2026-04-11, the Build & Deploy stream pushed icons/aggregate.py changes and the Round-2 icon fix stream pushed the revised SVGs + _SYSTEM.md updates. Both fired aggregate.yml + validate.yml. The user flagged this as costing money. Do not repeat.

**When the user DOES unblock pushes:** they will likely want a coordinated sequence — (a) push paper-trading release tag, (b) push deskmodal-side rip-out + icon plumbing, (c) finally trigger the appmarket aggregator. Verify each step before proceeding to the next.
