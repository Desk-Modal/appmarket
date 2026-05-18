---
name: engineering standards and process rules
description: Critical engineering rules - no versioned interfaces, no redundancy, always integrated, break interfaces freely, refactor over duplicate
type: feedback
---

1. Never create versioned interfaces (e.g., ConfigV2) — break interfaces and update all consumers
2. Never create redundant files — search first, extend existing, refactor shared logic
3. Never duplicate capabilities — if similar code exists, refactor into shared utility
4. Every capability must be integrated and exposed to users — no orphan code
5. All naming must be logically branded for Tradesurface (see .claude/rules/naming.md)
6. State of the art, mission critical product — treat every line of code accordingly
7. Always verify implementations against specs before considering a phase complete
8. Use /verify skill to validate packages against acceptance criteria
9. Code must be organized in the cleanest, optimal, best-practice manner
10. Chart engine is framework-agnostic TypeScript + Canvas — React manages UI frame only
11. WASM acceleration path for indicators — TypeScript-first, Rust WASM when profiling shows need
12. Knowledge lives in: CLAUDE.md (project context), .claude/rules/ (conventions), .claude/skills/ (workflows), memory/ (cross-session learning)
13. On context clear or new session: read CLAUDE.md first, check memory, read relevant rules — never start blind
