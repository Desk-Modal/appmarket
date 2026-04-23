---
name: Marketplace belongs in DeskModal repo
description: Marketplace app and all marketplace packages belong in DeskModal repo, not tradesurface
type: feedback
originSessionId: b4fe323d-5b15-4c43-bfb0-12f5722be9b2
---
Marketplace is a DeskModal platform feature, not associated with tradesurface.

**Why:** DeskModal is general-purpose; the marketplace serves all plugin developers, not just trading apps. Putting it in tradesurface would couple a platform feature to a domain-specific product.

**How to apply:** All marketplace packages (plugin-tools, verification-gateway, marketplace-sdk, plugin-installer, marketplace-telemetry), the marketplace app, example plugins, and marketplace docs belong in D:\celer\desk (DeskModal repo). Only tradesurface-specific marketplace integration (e.g., publishing tradesurface as a marketplace plugin) stays in the tradesurface repo.
