---
name: deskmodal-pinescript-import
description: Import a TradingView Pinescript v5 file and transpile to OptiScript per F147 OptiScript-everywhere + Pinescript-superset directive.
when_to_use: User pastes / cites a .pine file or asks to "import this Pinescript"
disable-model-invocation: true
allowed-tools: Read Bash(plugins/optiscript/**) Edit Write
effort: high
paths: plugins/optiscript/**
---

# DeskModal Pinescript import

F157 Layer 2 — wraps F147 pinescript-import per `feedback_pinescript_superset_optiscript` (2026-05-18 NEVER FORGOTTEN directive).

## Pinescript v5 conformance baseline

!`ROOT=$(bash "${CLAUDE_SKILL_DIR}/../_lib/dm-root.sh") && test -f "$ROOT/specs/147-optiscript-everywhere/pinescript-compat-matrix.md" && head -20 "$ROOT/specs/147-optiscript-everywhere/pinescript-compat-matrix.md"`

## Instructions

OptiScript is a 100% Pinescript v5 superset. TradingView users can drop `.pine` files into DeskModal and they work byte-identically; OptiScript ADDS FDC3 primitives + order intents + service proxies + audit chain + chart-context tradeTicks/depth-l3.

Process:
1. **Read the `.pine` source** the user provided.
2. **Run through F133 Pine v5 transpiler** to produce OptiScript bytecode. The transpiler lives in `plugins/optiscript/crates/optiscript-transpiler/`.
3. **Verify byte-equivalence** for the test-script's `plot()` / `plotshape()` / `alertcondition()` outputs against TradingView reference data when available.
4. **Save** the `.opti` source to `scripts:custom:<id>` via sdk-storage OR write to `plugins/optiscript/scripts/imported/<name>.opti`.
5. **Optionally augment** with DeskModal-only features (FDC3 broadcasts, order intents, persistent state) — preserve the original semantics; ADDITIONS only.

## Compat matrix

If the source uses unimplemented Pinescript v5 features, list them with the `[unverified-W2]` tag per the F147 pinescript-compat-matrix.md.

## Output

- Path to the transpiled `.opti` file
- Byte-equivalence verification result (PASS / PARTIAL / FAIL with specific node)
- List of any unimplemented features encountered
