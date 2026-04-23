---
name: framework and deployment decisions
description: User directives on React, FDC3-only deployment, DeskModal evolution, and mobile reuse
type: feedback
---

1. Use React 19 (not SolidJS) — mobile reuse via React Native later
2. Tradesurface runs ONLY as FDC3 plugins on DeskModal — no standalone web app fallback
3. Evolve DeskModal's capabilities if needed to support Tradesurface requirements
4. TypeScript-first — developers should be able to modify designs and components easily
5. Ensure FDC3 compliance with any FDC3 2.2 container (not just DeskModal)
6. DeskModal-specific features via window.desk with graceful degradation
7. DeskModal evolution work to be done by a separate Claude Code session in the DeskModal codebase
