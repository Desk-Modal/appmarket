---
name: GitHub remote layout
description: Canonical GitHub org is Desk-Modal (renamed from deskmodaldev) — all local origin remotes point here, susspectsoftware-dev is dead
type: reference
originSessionId: 52daa5a6-91e7-4fa7-990b-26a30d0b15b5
---
All DeskModal work lives under the `Desk-Modal` GitHub org:
https://github.com/Desk-Modal

The org was renamed from `deskmodaldev` to `Desk-Modal` on 2026-04-10.
GitHub's URL redirect keeps the old name working for ~30 days; after
that, any reference to `deskmodaldev` breaks.

Canonical repos (all under `Desk-Modal/`):
- Desk-Modal/deskmodal
- Desk-Modal/tradesurface
- Desk-Modal/service-sdk
- Desk-Modal/plugin-tools
- Desk-Modal/price-feed-service
- Desk-Modal/paper-trading
- Desk-Modal/plugin-index
- Desk-Modal/deskmodal-fdc3-plugin
- Desk-Modal/deskmodal-website
- Desk-Modal/core-server-api

**Local remote layout** (as of 2026-04-10, post-rename):

| Repo path | `origin` remote |
|---|---|
| `D:\celer\desk` | `https://github.com/Desk-Modal/deskmodal.git` |
| `D:\code\tradesurface` | `https://github.com/Desk-Modal/tradesurface.git` |
| `D:\code\repo-extraction\service-sdk` | `https://github.com/Desk-Modal/service-sdk.git` |
| `D:\code\repo-extraction\plugin-tools` | `https://github.com/Desk-Modal/plugin-tools.git` |
| `D:\code\repo-extraction\price-feed-service` | `https://github.com/Desk-Modal/price-feed-service.git` |
| `D:\code\repo-extraction\paper-trading` | `https://github.com/Desk-Modal/paper-trading.git` |
| `D:\code\repo-extraction\plugin-index` | `https://github.com/Desk-Modal/plugin-index.git` |

**susspectsoftware-dev is DEPRECATED.** Never push there. The org was
abandoned due to a hit CI budget limit that caused all runs to fail in
2 seconds. All work moved to deskmodaldev then to Desk-Modal.

**deskmodaldev (old name) is GONE.** Any URL with `deskmodaldev/...`
works via redirect for ~30 days (until ~2026-05-10) and then breaks.
All hardcoded references in source, Cargo.toml, workflows, docs,
and the plugin-index.json file have been rewritten to `Desk-Modal/...`
in commits 132ca0d (deskmodal) + 7385e37 (tradesurface) + equivalents
in the 5 extraction repos.

**Branch protection on `main` across all 7 repos** (applied 2026-04-10
via API using a fine-grained PAT):
- required_status_checks.contexts = ["CI: all green"]
- required_status_checks.strict = true
- required_pull_request_reviews.required_approving_review_count = 1
- required_linear_history = true
- required_conversation_resolution = true
- allow_force_pushes = false
- allow_deletions = false
- enforce_admins = false (admins can hotfix main)

**Org-level "Workflow permissions" setting** — known OUTSTANDING as of
2026-04-10. Currently forced to "read" which blocks:
- sccache GHAC backend (can't write cache entries without `actions: write`)
- Any workflow that tries to push commits or create PRs

Must be flipped to "Read and write permissions" via web UI at
https://github.com/organizations/Desk-Modal/settings/actions
(or by adding "Actions policies: Read and write" organization
permission to the fine-grained PAT and re-running the IaC script).

`git push` (no args) is safe in every repo — `main` tracks `origin/main`
and every `origin` is `https://github.com/Desk-Modal/<repo>.git`.
