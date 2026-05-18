---
name: deskmodal-verify-tier-c
description: Pre-push / pre-release Tier C — scripts/local-ci.sh --full --sign + scripts/launch.sh --verify. Per quality.md §18.7.1. ONCE per logical-impact batch OR pre-push.
when_to_use: About to push to main / cut release; OR logical-impact-batch with GUI/FDC3/dist changes wants CDP evidence
disable-model-invocation: true
allowed-tools: Bash(scripts/launch.sh*) Bash(scripts/local-ci.sh*) Bash(scripts/build-dist.sh*) Bash(python scripts/cdp-test-runner.py*)
effort: high
---

# DeskModal Tier C verification

F157 Layer 2 — full-fidelity verification per `quality.md §18.7.1`. Costs ~10-15 min for --full --sign + ~5-10 min for launch.sh --verify with CDP.

## Recent landings

!`git log --oneline -15`
!`git status --short`

## Instructions

The flow per `quality.md §18.7.1` Tier C:

1. **Full Rust + sign** — `scripts/local-ci.sh --full --sign`. Workspace `cargo fmt --check --all` + `cargo clippy --workspace --all-targets -- -D warnings` + `cargo test --workspace` + `cargo deny check` + `cargo audit` + dmpkg sign round-trip. rc=0 required.

2. **GUI / FDC3 / dist** — `scripts/launch.sh --verify` if the batch touched any of: `platform/**`, `plugins/*/services/**`, `plugins/*/apps/**`, FDC3, dist signing. This launches DeskModal under CDP + runs the assertion suite.

3. **CDP evidence per evidence-row** — under `specs/<feature>/evidence/<row>/`: screenshots + axe-core WCAG 2.2 AA + pixelmatch ≤0.1%.

4. **Mobile push notification** to confirm Tier C complete (per F157 Layer 9).

## Banned

- Tier C per-wave (10-15 min × N waves = hours wasted)
- Skipping Tier C pre-push to main
- Workspace `cargo test` mid-loop (use Tier A scoped)

## Output

```
Tier C (quality.md §18.7.1):
  scripts/local-ci.sh --full --sign: rc=0
  scripts/launch.sh --verify: rc=0; CDP evidence at specs/<feature>/evidence/
  → Pre-push GREEN; ready to push.
```
