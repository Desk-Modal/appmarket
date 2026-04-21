//! DeskModal Verification Gateway — skeleton.
//!
//! Receives GitHub `repository_dispatch` events (event_type =
//! `release-published`) from registered publishers, enqueues them for
//! pipeline processing, and maintains a 5-minute poll loop over
//! `sources.json` as a resilience fallback for missed dispatches.
//!
//! Per ADR-0007 (`specs/adrs/ADR-0007-no-npm-publishing.md`), the
//! intake surface is GitHub `repository_dispatch` ONLY — no npm
//! webhook, no `@deskmodal/*` scope filter. The trust anchor is the
//! `sources.json` publisher registry; dispatches from unregistered
//! `owner/repo` pairs are rejected with HTTP 400.
//!
//! This crate ships the **skeleton** for M202 — the 10-step compliance
//! pipeline is M208. The gateway installs a [`NoopPipeline`] that
//! records `pending -> skipped` so the end-to-end intake path is
//! exercised without waiting on M208.
//!
//! # Entry points
//! - [`build_app`] — construct the axum router + state for integration
//!   tests (no socket binding required).
//! - [`run_poll_loop`] — the tokio task that polls `sources.json` every
//!   5 minutes (configurable) and enqueues gaps.
//!
//! # Modules
//! - [`config`] — gateway configuration + `sources.json` loader.
//! - [`dispatch`] — axum `/dispatch` handler + HMAC verification.
//! - [`poll`] — GitHub Releases poll fallback.
//! - [`queue`] — sqlx-backed job queue (SQLite for dev).
//! - [`pipeline`] — `Pipeline` trait + `NoopPipeline`.

pub mod config;
pub mod dispatch;
pub mod pipeline;
pub mod poll;
pub mod queue;

pub use config::{GatewayConfig, PublisherKey, Source, SourcesRegistry};
pub use dispatch::{build_app, AppState, DispatchPayload};
pub use pipeline::{NoopPipeline, Pipeline, PipelineOutcome};
pub use poll::{run_poll_cycle, run_poll_loop, PollConfig, ReleasesClient};
pub use queue::{IntakeSource, JobEnqueue, JobQueue, JobRecord, PipelineStep};
