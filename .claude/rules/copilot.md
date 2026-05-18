---
title: Copilot
authority: derives from `core.md`; topic-file for §22
load_when: any work touching plugins/copilot/, RAG indexing, model registry, golden-set eval, persistent memory, deployment topology
---

# Copilot

## 22. Copilot — evaluation, knowledge, persistent learning

**Cardinal directive (user 2026-05-17 verbatim — preserved per §1):** "how are we evaluating the copilot, which LLM is it using? we could use claude code first, but we would need to ensure claude is entirely trained and knowledgeable on the desk modal products, plugins, optiscript etc. Research whether wwe sshould consider an optimal learning approach, which keeps knowledge and learning across restarts, and extended from shared knowledge bases on an eventual deskmodal.com website"

**The rules:**

1. **Eval framework is mandatory (F150 W1) — no model lands in production without a golden-set score.** Production threshold: ≥ 85% accuracy on the DeskModal-domain golden set (500+ Q&A across OptiScript / SDK usage / plugin manifest / algo authoring / indicator design / alert authoring / market commentary / order-execution reasoning / risk explanation / audit-trail interpretation). Regression > 5% on a wave blocks landing. Gate `quality:copilot-eval-floor` BLOCKING in `local-ci.sh --full`.

2. **DeskModal-domain knowledge via RAG using SOTA-as-of-2026-05-17 techniques, NOT model fine-tuning.** User directive 2026-05-17 verbatim: "our copilot approach will leverage state of the art academic techniques as recent as may 17th 2026" — the model is small + local; the retrieval stack carries the quality. Indexed corpus:
   - `wiki/**/*.md` (84+ entity pages — primary domain knowledge)
   - `specs/**/*.md` (master specs + benchmarks)
   - `.claude/rules/core.md` (all 22 sections — canonical rules)
   - All `plugin.toml` (capability registry — auto-discoverable)
   - Selected source symbols + doc comments + tests (via CBM)
   - Committed `.opti` reference scripts (algo / indicator / alert exemplars)
   - Per-user notes / saved templates (opt-in)
   - Embeddings: **nomic-embed-text-v1.5 int8 (Apache 2.0; ~270 MB)** via fastembed; rusqlite SQLite-VSS storage.

   **SOTA retrieval stack (in pipeline order):**
   a. **Anthropic Contextual Retrieval (Sep 2024).** Each chunk prepended with situating-context summary BEFORE embedding (chunk situated within its document section). 35-49% reduction in retrieval failures. Indexing-time cost; amortised.
   b. **Multi-query / RAGFusion (2024).** Generate K=3 query variants (synonyms / decomposition) via the local model; retrieve for each; RRF combine.
   c. **Hypothetical Document Embeddings (HyDE).** For semantic queries: local model drafts a hypothetical answer; embed THAT; retrieve docs similar to the hypothetical. Better recall than embedding the bare question.
   d. **Hybrid search (BM25 + dense) with Reciprocal Rank Fusion.** Sparse catches exact symbols (`CHANNELS.COLLAB_VOICE_SIGNALING`); dense catches semantics. RRF combines.
   e. **Cross-encoder reranking** via **mxbai-rerank-base-v1 (Apache 2.0; ~184 MB)**. Top-50 hybrid candidates → top-K=8 final ranked.
   f. **GraphRAG entity-relationship summarisation (Microsoft, May 2024).** Build entity graph over the corpus; community summaries available for cross-cutting queries ("how do A and B interact").
   g. **LongRAG context window utilisation (2024).** Qwen 1.5B has 32K ctx — fits ~10 chunks comfortably; reduces retrieval surface vs short-context models.
   h. **Self-Reflective / Corrective RAG (CRAG, ICLR 2024).** Generator critiques retrieval relevance before answering; if low-confidence: broader retrieval → clarifying question → refuse-with-link ("I don't know — try docs at <link>"). Hallucination floor.
   i. **Citation injection.** Every retrieved fact surfaces inline `[ref: <path>:<line>]` markers; user clicks open the source. Transparency-over-magic per `feedback_workspace_ux_sota_bar` Jony-Ive cleanliness.
   j. **Re-index on git post-commit + file watcher** (incremental; only changed chunks).
   k. **Speculative decoding (optional)** — 0.5B draft model proposes; Qwen 1.5B verifies. 2-3× t/s boost.

   These techniques are the current SOTA per published research as of 2026-05-17. Adoption tracker in `specs/F150/research/sota-techniques-2026-05-17.md`. Future updates: every 3 months, refresh the technique-set against latest publications.

**Copilot is OPTIONAL — marketplace install per `feedback_per_capability_plugin_granularity`** (user directive 2026-05-17 amendment): plugins/copilot is NOT REQUIRED tier; ships at OPTIONAL marketplace tier. Users who never opt-in to AI features incur zero install delta, zero model download, zero RAG corpus index. Settings UI only renders copilot panel when the plugin is installed + enabled (per §20 #3). Default DeskModal binary is AI-free.

**Model registry + upgradability (per F149 sdk-config + F125 lifecycle):**
- Models declared in `plugins/copilot/models/registry.toml` — each entry: `{id, version, sha256, ed25519_sig, license, size_mb, download_url, role: generative|embedding|reranker|draft, capabilities: [...]}`.
- User-configurable via sdk-config keys: `copilot.model.generative` / `.embedding` / `.reranker` / `.draft`.
- Upgrade flow: settings UI shows "Update available" badge → signed download from HuggingFace mirror OR self-hosted CDN → SHA-256 + Ed25519 verify → quarantine + sandbox-test (run subset of golden-set; ≥80% required to activate) → swap on next session (or hot-reload if safe) → previous N=2 versions retained for rollback.
- Storage: `dist/data/copilot/models/<id>-<version>/` (gitignored; survives binary updates via install_root contract).
- Cleanup: GC older-than-N versions after successful activation; configurable retention.

**Deployment topology (multi-mode per user directive — optional remote services):**
- **Local-only (default for installed copilot):** in-process candle inference; LocalOnly privacy; zero network egress.
- **Self-hosted network (team mode):** trader's organisation deploys a `deskmodal-copilot-server` Rust binary on a LAN/WAN endpoint. Trader installations route via sdk-config `copilot.endpoint = https://copilot.team.internal`. Multi-tenancy: per-org namespace + audit chain. Signed JWT bearer tokens (Ed25519). Same Anthropic-API-compatible HTTP shape so local + remote consume one ProviderInterface.
- **DeskModal-hosted (`copilot.deskmodal.com`):** managed multi-tenant service for subscribers who want SOTA without local install or self-hosting. Per-user encrypted store; opt-in shared organisational knowledge base; canonical DeskModal docs auto-fed; subscription via core-server-api.
- **Hybrid:** local for default LocalOnly + remote escalation for complex tasks; router (sdk-config `copilot.router_policy`) decides per task.
- Routing transparency: every dispatch's deployment-target logged to the audit chain per §22 #7.

**Iterate-to-SOTA discipline (user directive: "evaluate, build knowledge, evolve, research latest, apply until SOTA"):**
- Eval-floor gate `quality:copilot-eval-floor` BLOCKING in --full per §22 #1 — every wave touching copilot-engine OR model registry reruns the golden set, produces scorecard, hallucination rate, latency, cost.
- SOTA-techniques tracker at `specs/150-copilot-eval-knowledge-sota/research/sota-techniques-<date>.md` refreshed every 3 months against latest publications (per §22 #2 last bullet); review-only adversarial agent runs the refresh.
- Knowledge build: corpus auto-re-indexed per `feedback_continuous_hygiene_across_all_axes` axis 5 + auto on git post-commit.
- Evolve: when a new SOTA technique publishes, document in tracker → propose wave → run head-to-head eval (current vs new technique) → adopt if scorecard improves > 2% with same latency budget.

3. **Small local open-source model — DEFAULT (user directive 2026-05-17 amendment):**
   - **Default generative model: Qwen 2.5-Coder 1.5B Instruct (Apache 2.0; ~1.0 GB int4 quantized)** — code-specialised; runs via Rust-native `candle` inference; Metal on macOS / CUDA on Linux+Windows / CPU fallback. ~10 t/s on M-series CPU; ~30 t/s with GPU. Strong on syntactic tasks (OptiScript, SDK calls, plugin.toml authoring).
   - **Default embedding model: nomic-embed-text-v1.5 int8 (Apache 2.0; ~270 MB)** — via fastembed (already in deskmodal-ai/rag tree).
   - **Default reranker: mxbai-rerank-base-v1 (Apache 2.0; ~184 MB)** — cross-encoder; top-50 hybrid candidates → top-K=8 final.
   - **Total bundle delta: ~1.5 GB** added to dist/. Acceptable per F146 distribution. Signed delta via F125 lifecycle.
   - **First-run download option** for bandwidth-constrained users: signed model bundle from HuggingFace mirror OR self-hosted CDN. NEVER from npm.
   - **LocalOnly is the DEFAULT privacy mode.** No API key required for default operation; no cloud dependency.
   - **Cloud escalation OPT-IN** (Claude Opus 4.7 + Sonnet 4.6 via Anthropic API) for complex reasoning the local model can't handle (strategy authoring requiring N-step reasoning + multi-step OptiScript synthesis + cross-symbol portfolio analysis). User-toggled in Settings UI (sdk-config per §20).
   - **Inference framework: `candle` (Rust-native; HuggingFace; Apache 2.0)** — workspace dep consistency. `llama.cpp` Rust bindings is the fallback if candle has perf gaps.
   - **NO Ollama runtime dependency.** Inference is in-process via candle; no external runtime install.
   - Router: small classifier picks local-vs-cloud based on (task-class, complexity-score, privacy mode, daily cost ceiling). Audit-chain logs router decisions.
   - Cost ceiling: local = zero marginal cost; cloud cap configurable via sdk-config.

4. **Tool-use via Claude tool API + DeskModal-specific tools:**
   - `query_optiscript_stdlib(symbol)` — returns optiscript-stdlib symbol's signature + docs
   - `lookup_plugin_capability(capability)` — returns matching plugins + channels + intents
   - `compile_opti_script(source)` — invokes optiscript-transpiler; returns errors or compiled binary hash
   - `backtest_strategy(opti_source, symbol, range)` — runs optiscript-runtime backtester; returns PnL + drawdown + Sharpe
   - `query_audit_chain(filter)` — privacy-aware queries on user's own audit chain
   - `read_user_notes(query)` — searches user's saved notes / scripts / templates
   - `find_marketplace_script(query)` — searches the marketplace + verification-tier filter
   - Tool execution audit-chained per F143-D OrderAuditLog primitive (extending to OrderAuditEvent::ToolUse).

5. **Persistent learning across restarts (per-user; privacy-gated):**
   - Conversation-thread store: `sdk-storage:copilot.threads.<thread_id>` — JSON with chain of turns; signed.
   - Long-term memory: every N=20 turns, background summarisation distils prior context → `copilot.memory.<user>.<facet>` (preferred algos, common symbols, risk preferences).
   - Cross-session resume: on chat open, system prompt = (last summary) + (top-K relevant prior turns from RAG) + (current RAG retrieval). Total < 200K tokens.
   - Preference learning: track suggestion accept/reject; per-user weight matrix biases future retrieval + provider selection.
   - Privacy gates: LocalOnly disables ALL summarisation + cross-session sync; CloudOptIn allows; Auto routes per-turn (heuristic: PII detected → LocalOnly path).
   - All memory writes Ed25519-signed via F143-D OrderAuditLog primitive (cross-spec reuse).

6. **Shared knowledge base at deskmodal.com / docs.deskmodal.dev (F146 + F148 + F150):**
   - F146 distribution + F148 architecture docs portal IS the public knowledge base.
   - Same MD corpus indexed for RAG is published; community discoverable.
   - Marketplace community contributions (published .opti scripts + indicator presets + alert templates) discoverable.
   - Optional community Q&A pairs feed back into golden eval set (curated; verification-tier gated).
   - Every DeskModal installation pulls latest indexed corpus on update (signed delta via F125 lifecycle + F146 dmpkg).
   - Anthropic Files API (or equivalent) optionally hosts public-knowledge embeddings for cloud-provider retrieval, alongside on-device retrieval for LocalOnly.

7. **Eval discipline (gate: `quality:copilot-eval-floor`):**
   - Golden set version-pinned in `evals/golden/v<N>.jsonl` (no V1/V2 ladder — `<N>` is dataset-VERSION not API-VERSION; see §5).
   - Every wave touching copilot-engine reruns eval harness; produces scorecard in `specs/F150/evidence/W<N>-eval/scorecard.md`.
   - Per-model scorecard tracks accuracy / latency p50/p99 / cost / tool-use correctness / refusal rate / hallucination rate.
   - Regression > 5% blocks landing.

**Forbidden patterns:**
- Hardcoded model name in source code (model selection via sdk-config per §20).
- Per-service prompt injection (system prompts MUST be assembled by copilot-engine via the RAG pipeline; no service authors its own LLM prompts).
- LocalOnly mode silently routing to cloud (per §16 no-fallbacks; hard-fail or use Ollama only).
- Production landing without golden-set scorecard (per #1; eval-floor gate BLOCKS).

**Cascading:**
- F150 master spec — full eval + RAG + persistent learning + multi-model + shared KB architecture
- F141 amendments — provider chain extends to Ollama + multi-model router; RAG wire-up; per-user memory
- F147 amendments — OptiScript codegen target = the RAG corpus's CURRENT SDK surface (no stale)
- F148 amendments — architecture diagram includes RAG indexer + eval harness as components
- F149 amendments — sdk-config carries per-user copilot preferences (privacy / model / cost cap)
- F146 amendments — docs portal IS the shared KB; ingestion pipeline declared
- F143-D OrderAuditLog primitive consumed for tool-use + memory-write audit chain

**Pairs with:**
- §16 (non-blocking — RAG retrieval ≤ 100ms p99; Ollama LocalOnly latency budget per platform)
- §17 (SDK only — copilot-engine consumed via sdk-copilot; no @tauri-apps direct imports in apps)
- §19 (OptiScript-everywhere — AI codegen emits .opti scripts)
- §20 (sdk-config — copilot preferences)
- §21 (spec hygiene — every wave updates F150 spec)
- security-engineer BLOCKING-1 closure (secrets → OS keychain; API keys for cloud providers route through OsKeychainStore)
- feedback_no_versioned_interfaces_pre_public — golden-set v<N> is dataset versioning, not API; allowed

