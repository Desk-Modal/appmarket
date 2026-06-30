# Copilot

## 22. Copilot — evaluation, knowledge, persistent learning

**Cardinal directive (user 2026-05-17 verbatim — preserved per §1):** "how are we evaluating the copilot, which LLM is it using? we could use claude code first, but we would need to ensure claude is entirely trained and knowledgeable on the desk modal products, plugins, optiscript etc. Research whether wwe sshould consider an optimal learning approach, which keeps knowledge and learning across restarts, and extended from shared knowledge bases on an eventual deskmodal.com website"

**SOTA-technique directive (user 2026-05-17 verbatim):** "our copilot approach will leverage state of the art academic techniques as recent as may 17th 2026" — the model is small + local; the retrieval stack carries the quality.

**Invariants (durable; full mechanics in the wiki playbook):**

1. **Eval-floor is BLOCKING — no model lands without a golden-set score ≥ 85%** on the DeskModal-domain golden set (500+ Q&A). Regression > 5% blocks landing. Gate `quality:copilot-eval-floor` BLOCKING in `local-ci.sh --full`. Golden set version-pinned at `evals/golden/v<N>.jsonl` (`<N>` = dataset version, NOT API version per §5).
2. **Domain knowledge via RAG, NOT fine-tuning.** SOTA-as-of-2026-05-17 retrieval stack (Contextual Retrieval → multi-query/RAGFusion → HyDE → hybrid BM25+dense RRF → cross-encoder rerank → GraphRAG → CRAG self-reflection → citation injection). Corpus = `wiki/**` + `specs/**` + `.claude/rules/core.md` + every `plugin.toml` + lodestar symbols + committed `.opti` reference scripts. Technique-set refreshed every 3 months against latest publications.
3. **Copilot is OPTIONAL tier — the default DeskModal binary is AI-free.** Zero install delta / zero model download / zero RAG index for users who never opt in. Settings UI renders the copilot panel only when the plugin is installed + enabled (per §20).
4. **Default models, in-process via `candle` (Rust-native; no Ollama runtime):** generative = Qwen 2.5-Coder 1.5B Instruct (Apache 2.0; ~1.0 GB int4); embedding = nomic-embed-text-v1.5 int8 (~270 MB); reranker = mxbai-rerank-base-v1 (~184 MB). ~1.5 GB bundle delta, signed via F125 lifecycle. Models declared in `plugins/copilot/models/registry.toml`; user-selectable via sdk-config.
5. **LocalOnly is the DEFAULT privacy mode** — no API key, no cloud dependency, zero network egress for default operation.
6. **Cloud escalation is OPT-IN** (Claude Opus 4.8 / Sonnet 4.6 via Anthropic API) for reasoning the local model can't handle; user-toggled in Settings via sdk-config. A router (small classifier) picks local-vs-cloud per (task-class, complexity, privacy mode, daily cost ceiling); decisions audit-chained.
7. **Persistent learning across restarts** — per-user, privacy-gated: thread store + N=20-turn summarisation + cross-session RAG resume + accept/reject preference weights. All memory writes Ed25519-signed via the F143-D OrderAuditLog primitive. LocalOnly disables all summarisation + cross-session sync.
8. **Shared knowledge base** = the F146/F148 docs portal (`deskmodal.com` / `docs.deskmodal.dev`); same MD corpus indexed for RAG is published + community-discoverable; every install pulls the latest signed corpus delta on update.

**Forbidden patterns:**
- Hardcoded model name in source (selection via sdk-config per §20).
- Per-service prompt injection (system prompts assembled ONLY by copilot-engine via the RAG pipeline).
- LocalOnly silently routing to cloud (per §16 no-fallbacks; hard-fail).
- Production landing without a golden-set scorecard (per #1; eval-floor gate BLOCKS).

**Full mechanics** (SOTA retrieval stack a-k, model-registry upgrade flow, 4 deployment topologies, 7 DeskModal tools, persistent-learning schema, shared-KB pipeline, eval discipline, cascading F-spec list): `mcp__wiki-mcp__wiki_get_page playbooks/copilot/eval-rag-knowledge` OR `Read wiki/playbooks/copilot/eval-rag-knowledge.md`.

**Pairs with:** §16 (non-blocking — RAG retrieval ≤ 100ms p99) · §17 (SDK-only — consumed via sdk-copilot) · §19 (OptiScript-everywhere — AI codegen emits `.opti`) · §20 (sdk-config — copilot preferences) · §21 (spec hygiene — every wave updates F150) · §23 (FDC3 copilot uniformity). F150 master spec; F141/F147/F148/F149/F146 amendments; F143-D OrderAuditLog reuse.
