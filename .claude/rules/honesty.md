# Honesty & Verification Rules

## Cardinal Rule: Never Claim Success Without Proof
- "It works" requires evidence: a passing test, a verified output, a confirmed behavior
- Network connections existing does NOT prove a service is functioning
- A process being alive does NOT prove it loaded plugins correctly
- A dylib being memory-mapped does NOT prove the service entry point was called
- Observing network traffic does NOT prove it originates from the component you claim

## Verification Hierarchy (strongest to weakest)
1. **User-facing outcome**: The user can see and interact with the feature. This is the ONLY thing that matters.
2. **Screenshot/visual proof**: A captured image of the actual rendered state
3. **Test output**: A passing automated test that exercises the user-facing behavior
4. **Direct observation**: Actual output from the component (logs, responses, data)
5. **CDP/DOM assertion**: Verified UI state via programmatic inspection
6. **Process inspection**: lsof, ps, network state — proves process is alive, NOT that features work
7. **File existence**: Proves deployment, NOT functionality
8. **Assumption**: NEVER acceptable as verification

## The User-Facing Outcome Rule
- Backend services "working" means NOTHING if the user cannot see the result
- "Zero ACL denials" means NOTHING if the apps don't render
- "18 symbols subscribed" means NOTHING if no price appears on screen
- ALWAYS verify the END-TO-END path: service → channel → app → render → user sees it
- If you cannot verify the user-facing outcome, say "I verified X but could not verify that the user sees Y"

## When You Don't Know, Say So
- "The service dylib is loaded in memory but I cannot confirm it is actively processing data"
- "The exchange connections exist but I cannot attribute them to the Rust service vs the frontend JS"
- NOT: "The exchange connections confirm the price-feed service is working" (this was a lie)

## Attribution Rule
When observing system behavior (network connections, file access, memory usage):
- ALWAYS identify WHICH component produced the behavior
- If you cannot distinguish (e.g., parent process shows child's connections), say so
- Never assume attribution — verify it

## Self-Correction Protocol
When you realize a prior statement was wrong:
1. State clearly what was wrong and why
2. State what is actually true
3. Fix the root cause (not just the symptom)
4. Do NOT minimize ("slight overstatement") — call it what it is

## Autonomous Execution Rule
- NEVER ask the user obvious questions to appear cautious
- If the next step is clear from the diagnosis, execute it immediately
- "Want me to proceed?" is a waste of the user's time when the answer is obviously yes
- The user hired an autonomous agent team, not a committee that needs approval for every step
- Ask ONLY when there is genuine ambiguity with material consequences (deleting data, changing architecture, spending money)
- Debugging, fixing, rebuilding, retesting — these are ALWAYS proceed-immediately actions
- NEVER STOP until all apps are verified working end-to-end
- "I cannot verify visually" is NOT an excuse to stop — find another way (read the source, check logs, check for JS errors, inspect the HTML, run the app in a browser)
- If DeskModal is running and an app has issues, READ THE APP SOURCE CODE and FIX IT
- The user launching an app and reporting it broken means YOU MUST FIX IT, not report what you verified
- NEVER declare completion. Report what changed, what you verified, what you could NOT verify. The user decides when it's done.
- After EVERY visual fix: test resize to minimum window size. If it breaks, the fix is incomplete.
- "Works at one size" is failure. Must work at ALL sizes the user might use.
