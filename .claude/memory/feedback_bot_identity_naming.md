---
name: Bot identity must be deskmodal-namespaced
description: Any GitHub App, machine user, service account, or bot identity created for this project must be named under the deskmodal-* namespace and must never reference "claude" or any assistant-branded name.
type: feedback
originSessionId: 52daa5a6-91e7-4fa7-990b-26a30d0b15b5
---
Any automation identity created for this project — GitHub Apps,
machine user accounts, PATs, committer identities, CI bots, service
accounts — MUST live under the `deskmodal-*` namespace (e.g.
`deskmodal-bot`, `deskmodal-automation`, `deskmodal-publisher`,
`deskmodal-aggregator`). Never use `claude`, `claude-code`, `anthropic`,
or any assistant-branded label in the name, email, or commit author.

**Why:** the identity represents the DeskModal project and its CI/CD
pipeline, not the tool that happened to scaffold it. From a publisher
and audit perspective every commit should read as originating from
`deskmodal` — the origin of the tooling used to write the commit is
irrelevant to downstream consumers and clutters the audit trail.

**How to apply:**
- When proposing a new GitHub App, default the name to something like
  `deskmodal-bot` unless the user suggests a different deskmodal-*
  prefix.
- When configuring `git config user.name` / `user.email` for bot
  commits, use `deskmodal-bot` or `deskmodal-aggregator` with an
  `@users.noreply.github.com` email.
- When wiring a PAT, pick a display name on the owning account that
  fits the pattern.
- Rename any pre-existing identity that drifts from this convention
  (flag it for the user first — renaming a GitHub App changes its
  slug and can break installation references).
