---
name: SDK-only access enforcement
description: Services (price-feed, paper-trading) must ONLY interact with DeskModal via ServiceSDK — no direct access to core internals
type: feedback
originSessionId: c79c755b-a808-4030-96ed-c4cde43c8b33
---
Services must interact with DeskModal ONLY through the ServiceSDK (deskmodal-service-sdk). No workarounds, no direct imports from deskmodal-core.

**Why:** The product owner wants a clean boundary: DeskModal internals are invisible to services/plugins. If a capability is needed but doesn't exist in the SDK, expand the SDK — don't bypass it.

**How to apply:**
- price-feed and paper-trading must import from deskmodal-service-sdk, never deskmodal-core
- When a new capability is needed, add it to the ServiceSDK first
- Any agent implementing service features must verify the import chain stays within SDK boundaries
- DeskModal cannot be interacted with unless via the SDKs
