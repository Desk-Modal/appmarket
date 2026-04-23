---
name: Service SDK 5-Persona Audit Findings
description: Comprehensive audit of DeskModal service SDK by 5 expert personas — 12 P0, 14 P1 gaps identified
type: project
---

# Service SDK Audit (2026-03-15)

5 expert personas reviewed the service SDK architecture. Full gap register at `specs/SERVICE-SDK-GAP-REGISTER.md`.

## Key Findings

**Rust Systems Architect**: In-process dispatcher missing (`_agent_transport` discarded at native_runner.rs:118). No cdylib loader. No marketplace pipeline.

**Frontend Architect**: No service discovery API. Silent failures when service unavailable. 30s crash detection lag. Fire-and-forget error pattern. No type validation across TS/Rust boundary.

**Integration Architect**: 45% FDC3 2.2 compliant for services. Not in app directory. No user channel API. No private channels. Services are second-class citizens in intent resolution. Service→web app routing missing.

**Security Architect**: No code signing. Service identity spoofable via IPC. No consent UI. No sandboxing for marketplace code. Secret isolation relies on string matching. Audit trail incomplete.

**Trading Domain Expert**: 50-80ms E2E latency acceptable for crypto. No sequence numbers. Per-consumer backpressure missing. No audit trail for regulatory replay. Circuit breaker too conservative.

## Execution Order
Wave 1: Unblock integration (P0-1, P0-2, P0-7, P0-8, P0-9)
Wave 2: FDC3 compliance (P0-3, P0-10, P1-7, P1-8)
Wave 3: Security hardening (P0-4, P0-5, P0-6, P0-12)
Wave 4: Marketplace pipeline (P0-11, P1-9, P1-10, P1-13)
Wave 5: Trading reliability (P1-1 through P1-6, P1-14)
Wave 6: Production polish (P2-*, remaining P1-*)

**Why:** SDK is 60% complete for internal use, NOT ready for marketplace.

**How to apply:** Use gap register to drive implementation. Completeness Auditor must sign off each wave before proceeding to next.
