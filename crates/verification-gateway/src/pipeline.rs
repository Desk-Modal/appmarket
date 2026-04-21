//! Pipeline trait + `NoopPipeline`.
//!
//! M208 replaces the `NoopPipeline` with the real 10-step compliance
//! pipeline. The skeleton exists so M202's acceptance scenarios
//! exercise the full intake path (dispatch / poll → queue →
//! pipeline) without blocking on M208.
//!
//! `NoopPipeline::drain_one` terminates a pending job as `skipped`,
//! recording a decision string that makes the provenance auditable
//! ("gateway skeleton — M208 pipeline not yet installed").

use thiserror::Error;
use tracing::info;

use crate::queue::{IntakeSource, JobEnqueue, JobQueue, PipelineStep};

#[derive(Debug, Error)]
pub enum PipelineError {
    #[error("queue: {0}")]
    Queue(#[from] crate::queue::QueueError),
}

/// What a pipeline did with a job. The `NoopPipeline` always returns
/// `Skipped`; M208's real pipeline will return the terminal verdict.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PipelineOutcome {
    Skipped,
}

/// Pipeline interface. M202 only ships `NoopPipeline`; M208 adds the
/// real 10-step implementation. The trait kept intentionally minimal
/// — a single `drain_one` surface — so M208 can either impl it
/// directly or evolve to an `async-trait` + streaming shape without
/// breaking callers.
pub trait Pipeline: Send + Sync + std::fmt::Debug {
    fn name(&self) -> &'static str;
}

/// Placeholder pipeline used by M202. Records a `skipped` terminal
/// row.
#[derive(Debug, Clone, Default)]
pub struct NoopPipeline;

impl Pipeline for NoopPipeline {
    fn name(&self) -> &'static str {
        "noop"
    }
}

impl NoopPipeline {
    /// Drain one pending job — writes the terminal `skipped` row and
    /// returns `PipelineOutcome::Skipped`.
    ///
    /// Idempotent: re-running on an already-drained `(repo, tag)`
    /// pair is a no-op via the queue's UNIQUE index.
    pub async fn drain_one(
        queue: &JobQueue,
        publisher_repo: &str,
        tag: &str,
    ) -> Result<PipelineOutcome, PipelineError> {
        // Inherit intake-source from the pending row so provenance is
        // preserved across the `pending -> skipped` transition.
        let pending = queue.get_pending(publisher_repo, tag).await?;
        let intake_enum = match pending.as_ref().map(|r| r.intake_source.as_str()) {
            Some("poll") => IntakeSource::Poll,
            _ => IntakeSource::Dispatch,
        };

        let result = queue
            .record_terminal(
                publisher_repo,
                tag,
                PipelineStep::Skipped,
                "skip",
                Some(r#"{"reason":"gateway skeleton — M208 pipeline not yet installed"}"#),
                intake_enum,
            )
            .await?;
        match result {
            JobEnqueue::Inserted(id) => {
                info!(
                    id,
                    publisher_repo, tag, "noop pipeline recorded skipped terminal"
                )
            }
            JobEnqueue::AlreadyPresent => {
                info!(
                    publisher_repo,
                    tag, "noop pipeline skipped already-present row"
                )
            }
        }
        Ok(PipelineOutcome::Skipped)
    }
}
