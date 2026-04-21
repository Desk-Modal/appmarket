-- Verification Gateway job queue
--
-- Created for M202 (GitHub `repository_dispatch` intake + poll fallback +
-- job queue). Row shape per spec:
--   {publisher_repo, tag, pipeline_step, decision, evidence, ts}
--
-- Dev uses SQLite; Postgres prod parity enforced by keeping types to the
-- portable subset (TEXT, INTEGER, BLOB, timestamps as TEXT-ISO-8601).
-- Both backends use the same migration file; sqlx `ANY` is NOT used — each
-- binary pins a driver at build time (SQLite for local dev, Postgres for
-- prod) but the schema is identical.

CREATE TABLE IF NOT EXISTS verification_jobs (
    -- Composite identity: a (publisher_repo, tag) pair is one job. Multiple
    -- pipeline-step rows share the identity for audit history.
    id              INTEGER PRIMARY KEY AUTOINCREMENT,

    -- `owner/repo` of the publisher's plugin source repo (matches
    -- sources.json `owner` + `repo`).
    publisher_repo  TEXT    NOT NULL,

    -- Release tag (e.g., "v1.2.3").
    tag             TEXT    NOT NULL,

    -- Pipeline-step label. `pending` on enqueue; transitions through
    -- verifier steps (schema, fdc3, signature, ...); terminal `passed` |
    -- `failed` | `skipped`. M208 drives these transitions; M202 ships
    -- only `pending` and `skipped` (via NoopPipeline).
    pipeline_step   TEXT    NOT NULL,

    -- Per-step verdict. NULL while the step is in flight. `ok` | `fail` |
    -- `skip` on completion. M202 writes `skip` on the terminal row.
    decision        TEXT,

    -- Step-specific evidence (JSON blob). May be NULL for `pending` rows.
    -- E.g. for `signature`: {"public_key_id": "...", "sig_path": "...",
    -- "sha256": "..."}.
    evidence        TEXT,

    -- Intake source. `dispatch` | `poll`. Helps distinguish which ingress
    -- observed the release; a repository_dispatch that beats the poll
    -- wins the insert (UNIQUE constraint below).
    intake_source   TEXT    NOT NULL,

    -- Wall-clock timestamp (ISO-8601, UTC). SQLite has no native
    -- timestamp type — we store as TEXT and parse client-side.
    ts              TEXT    NOT NULL
);

-- A (publisher_repo, tag, pipeline_step) triplet is unique — idempotent
-- intake on both dispatch and poll paths. The poll loop checks for the
-- `pending` row before inserting; a race where dispatch + poll both fire
-- is resolved by this constraint (second insert becomes a no-op).
CREATE UNIQUE INDEX IF NOT EXISTS idx_verification_jobs_triplet
    ON verification_jobs (publisher_repo, tag, pipeline_step);

-- Fast lookup "do we already have this (repo, tag) somewhere?" used by
-- both the dispatch handler and the poll loop before enqueue.
CREATE INDEX IF NOT EXISTS idx_verification_jobs_repo_tag
    ON verification_jobs (publisher_repo, tag);

-- Fast lookup "what's currently pending?" used by the pipeline runner.
CREATE INDEX IF NOT EXISTS idx_verification_jobs_pending
    ON verification_jobs (pipeline_step, ts)
    WHERE pipeline_step = 'pending';
