---
name: deskmodal-verify-tier-a
description: Scoped Tier A verification — cargo check -p / cargo test -p / pnpm --filter — for the wave's declared write-set only. Per quality.md §18.7.1. Use after impl agents return + before committing.
when_to_use: An impl wave just finished; need scoped Tier A verification before commit
allowed-tools: Bash(cargo check -p *) Bash(cargo test -p *) Bash(cargo clippy -p *) Bash(cargo fmt -p *) Bash(pnpm --filter *) Bash(git diff --name-only:*)
effort: medium
---

# DeskModal Tier A verification

F157 Layer 2 helper — scoped per `quality.md §18.7.1` (NEVER workspace-wide; cargo + nx incremental cache survives across waves only if scoped).

## Changed scope

!`git diff --name-only HEAD~1 2>/dev/null | head -15`

## Instructions

Run scoped Tier A verification:

1. **Compute affected scope** from `git diff --name-only`. Group by:
   - Rust crate: parse `Cargo.toml` for the `[package] name`; map file to crate
   - TS package: parse `package.json` for the `name`; map file to package
   - Plain markdown / config: no Tier A needed

2. **Run scoped commands per scope:**
   - Each affected Rust crate: `cargo check -p <crate>` then `cargo test -p <crate>`
   - Each affected TS package: `pnpm --filter <pkg> test`
   - Nx graph-affected: `pnpm nx affected -t build --base=HEAD~1`

3. **Each command must rc=0** for the wave to be APPROVE-eligible.

4. **NEVER** run `cargo test --workspace`, `cargo check --workspace`, or `pnpm nx run-many -t test` here. That's Tier B (`scripts/local-ci.sh --fast`), reserved for phase boundary.

5. **Report results** with the exact commands run + their rc. The /goal evaluator reads the transcript to judge.

## Cache discipline

Per `architecture.md §28.4`: NEVER `cargo clean`, NEVER `nx reset`, NEVER `rm -rf target/`. Cache survives → Tier A is fast.

## Output

```
Tier A verification (quality.md §18.7.1):
  cargo check -p <crate-A>: rc=0
  cargo test -p <crate-A>: rc=0 (12 passed)
  pnpm --filter @deskmodal/<pkg> test: rc=0 (8 passed)
  → APPROVE eligibility: yes
```
