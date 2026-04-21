//! sqlx-backed job queue — SQLite for dev, Postgres schema parity
//! enforced by the migration file (`migrations/0001_gateway_init.sql`).
//!
//! A job row is keyed by `(publisher_repo, tag, pipeline_step)` — the
//! unique index in the migration makes intake idempotent. Dispatch
//! handler and poll loop both call [`JobQueue::enqueue_pending`]; the
//! second caller becomes a no-op. This makes dispatch + poll safe to
//! run in parallel without coordination.

use std::path::Path;
use std::str::FromStr;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePool, SqlitePoolOptions};
use thiserror::Error;

/// Pipeline-step labels the gateway itself writes. M208 will extend
/// this enum (schema, fdc3, signature, wasm_sandbox, size, license,
/// cve, screenshots, conformance, fallback) — for M202 the skeleton
/// only writes `pending` (on intake) and `skipped` (NoopPipeline
/// terminal).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PipelineStep {
    Pending,
    Skipped,
}

impl PipelineStep {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Skipped => "skipped",
        }
    }
}

impl FromStr for PipelineStep {
    type Err = QueueError;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "pending" => Ok(Self::Pending),
            "skipped" => Ok(Self::Skipped),
            other => Err(QueueError::UnknownStep(other.to_string())),
        }
    }
}

/// One row of `verification_jobs`. Matches the spec's shape:
/// `{publisher_repo, tag, pipeline_step, decision, evidence, ts}`
/// plus bookkeeping (`id`, `intake_source`).
#[derive(Debug, Clone)]
pub struct JobRecord {
    pub id: i64,
    pub publisher_repo: String,
    pub tag: String,
    pub pipeline_step: String,
    pub decision: Option<String>,
    pub evidence: Option<String>,
    pub intake_source: String,
    pub ts: DateTime<Utc>,
}

/// Which ingress observed the release first. The UNIQUE index on
/// `(publisher_repo, tag, pipeline_step)` means a "losing" intake's
/// INSERT is silently ignored; `enqueue_pending` returns
/// `JobEnqueue::AlreadyPresent` when that happens.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IntakeSource {
    Dispatch,
    Poll,
}

impl IntakeSource {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Dispatch => "dispatch",
            Self::Poll => "poll",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum JobEnqueue {
    Inserted(i64),
    AlreadyPresent,
}

#[derive(Debug, Error)]
pub enum QueueError {
    #[error("sqlx: {0}")]
    Sqlx(#[from] sqlx::Error),
    #[error("sqlx migrate: {0}")]
    Migrate(#[from] sqlx::migrate::MigrateError),
    #[error("unknown pipeline_step: {0}")]
    UnknownStep(String),
}

#[derive(Debug, Clone)]
pub struct JobQueue {
    pool: SqlitePool,
}

impl JobQueue {
    /// Open an in-memory SQLite DB and apply migrations — used by
    /// the three integration tests.
    pub async fn new_in_memory() -> Result<Self, QueueError> {
        let opts = SqliteConnectOptions::from_str(":memory:")?
            .create_if_missing(true)
            .foreign_keys(true);
        let pool = SqlitePoolOptions::new()
            .max_connections(1) // in-memory DBs are per-connection
            .connect_with(opts)
            .await?;
        Self::migrate(&pool).await?;
        Ok(Self { pool })
    }

    /// Open a file-backed SQLite DB and apply migrations.
    pub async fn new_file<P: AsRef<Path>>(path: P) -> Result<Self, QueueError> {
        let opts = SqliteConnectOptions::new()
            .filename(path.as_ref())
            .create_if_missing(true)
            .foreign_keys(true);
        let pool = SqlitePoolOptions::new()
            .max_connections(5)
            .connect_with(opts)
            .await?;
        Self::migrate(&pool).await?;
        Ok(Self { pool })
    }

    /// Apply migrations. Uses sqlx `MIGRATOR` pointed at
    /// `../../migrations` relative to this crate root. Kept as a
    /// runtime migrator (not `sqlx::migrate!`) so tests and binaries
    /// resolve the path the same way regardless of the binary's
    /// working directory.
    async fn migrate(pool: &SqlitePool) -> Result<(), QueueError> {
        // Inline the migration SQL to avoid path-relative lookup
        // fragility — the file is ~60 lines and living alongside
        // this crate under `marketplace/appmarket/migrations/`.
        //
        // Keeping both the file (for Postgres parity + operator
        // review) and the inline string (for executable tests)
        // avoids a runtime filesystem dependency during `cargo test`.
        const MIGRATION: &str = include_str!("../../../migrations/0001_gateway_init.sql");

        // Strip `--` line comments BEFORE splitting on `;`. SQL
        // comments anywhere inside a DDL block would otherwise cling
        // to their neighbouring tokens and look like syntax errors
        // to SQLite.
        let cleaned: String = MIGRATION
            .lines()
            .map(|line| {
                // Everything from a leading-whitespace `--` onward is
                // a comment. We don't bother with mid-line comments
                // because our migration files don't use them; if that
                // changes, use a proper SQL tokenizer here.
                match line.trim_start().starts_with("--") {
                    true => "",
                    false => line,
                }
            })
            .collect::<Vec<_>>()
            .join("\n");

        for stmt in cleaned.split(';').map(str::trim).filter(|s| !s.is_empty()) {
            sqlx::query(stmt).execute(pool).await?;
        }
        Ok(())
    }

    /// Insert a `pending` job unless `(publisher_repo, tag,
    /// 'pending')` is already present. Idempotent by construction
    /// (the UNIQUE index catches races between dispatch and poll).
    pub async fn enqueue_pending(
        &self,
        publisher_repo: &str,
        tag: &str,
        intake: IntakeSource,
    ) -> Result<JobEnqueue, QueueError> {
        let ts = Utc::now().to_rfc3339();
        // Use "INSERT OR IGNORE" so the unique-index conflict becomes
        // a silent no-op rather than a surfaced error.
        let result = sqlx::query(
            r#"
            INSERT OR IGNORE INTO verification_jobs
                (publisher_repo, tag, pipeline_step, decision, evidence, intake_source, ts)
            VALUES (?1, ?2, 'pending', NULL, NULL, ?3, ?4)
            "#,
        )
        .bind(publisher_repo)
        .bind(tag)
        .bind(intake.as_str())
        .bind(&ts)
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            Ok(JobEnqueue::AlreadyPresent)
        } else {
            Ok(JobEnqueue::Inserted(result.last_insert_rowid()))
        }
    }

    /// Append a terminal pipeline-step row. Used by `NoopPipeline` to
    /// record `skipped` once the `pending` row has been observed.
    pub async fn record_terminal(
        &self,
        publisher_repo: &str,
        tag: &str,
        step: PipelineStep,
        decision: &str,
        evidence: Option<&str>,
        intake: IntakeSource,
    ) -> Result<JobEnqueue, QueueError> {
        let ts = Utc::now().to_rfc3339();
        let result = sqlx::query(
            r#"
            INSERT OR IGNORE INTO verification_jobs
                (publisher_repo, tag, pipeline_step, decision, evidence, intake_source, ts)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
            "#,
        )
        .bind(publisher_repo)
        .bind(tag)
        .bind(step.as_str())
        .bind(decision)
        .bind(evidence)
        .bind(intake.as_str())
        .bind(&ts)
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            Ok(JobEnqueue::AlreadyPresent)
        } else {
            Ok(JobEnqueue::Inserted(result.last_insert_rowid()))
        }
    }

    /// True iff SOME row (any pipeline_step) exists for
    /// `(publisher_repo, tag)`. Used by the poll loop to avoid
    /// double-enqueue when dispatch already delivered the tag.
    pub async fn has_any_row_for(
        &self,
        publisher_repo: &str,
        tag: &str,
    ) -> Result<bool, QueueError> {
        let row: (i64,) = sqlx::query_as(
            r#"SELECT COUNT(*) FROM verification_jobs
               WHERE publisher_repo = ?1 AND tag = ?2"#,
        )
        .bind(publisher_repo)
        .bind(tag)
        .fetch_one(&self.pool)
        .await?;
        Ok(row.0 > 0)
    }

    /// Fetch the pending row for `(publisher_repo, tag)`, if any.
    pub async fn get_pending(
        &self,
        publisher_repo: &str,
        tag: &str,
    ) -> Result<Option<JobRecord>, QueueError> {
        let row = sqlx::query_as::<
            _,
            (
                i64,
                String,
                String,
                String,
                Option<String>,
                Option<String>,
                String,
                String,
            ),
        >(
            r#"
            SELECT id, publisher_repo, tag, pipeline_step, decision, evidence, intake_source, ts
            FROM verification_jobs
            WHERE publisher_repo = ?1 AND tag = ?2 AND pipeline_step = 'pending'
            LIMIT 1
            "#,
        )
        .bind(publisher_repo)
        .bind(tag)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|(id, pr, t, step, dec, ev, intake, ts)| JobRecord {
            id,
            publisher_repo: pr,
            tag: t,
            pipeline_step: step,
            decision: dec,
            evidence: ev,
            intake_source: intake,
            ts: DateTime::parse_from_rfc3339(&ts)
                .map(|dt| dt.with_timezone(&Utc))
                .unwrap_or_else(|_| Utc::now()),
        }))
    }

    /// Count all rows — used by integration-test assertions.
    pub async fn count_all(&self) -> Result<i64, QueueError> {
        let row: (i64,) = sqlx::query_as(r#"SELECT COUNT(*) FROM verification_jobs"#)
            .fetch_one(&self.pool)
            .await?;
        Ok(row.0)
    }

    /// Count rows matching a pipeline_step — used by assertions.
    pub async fn count_step(&self, step: &str) -> Result<i64, QueueError> {
        let row: (i64,) =
            sqlx::query_as(r#"SELECT COUNT(*) FROM verification_jobs WHERE pipeline_step = ?1"#)
                .bind(step)
                .fetch_one(&self.pool)
                .await?;
        Ok(row.0)
    }

    /// Expose the raw pool to module-internal callers.
    pub fn pool(&self) -> &SqlitePool {
        &self.pool
    }
}
