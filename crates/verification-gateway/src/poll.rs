//! 5-minute poll fallback over `sources.json`.
//!
//! Scenario the poll covers (spec Acceptance #2): a publisher's CI
//! publishes a GitHub Release but the `notify-appmarket` step fails
//! or never fires. The gateway's dispatch intake never sees the
//! event. The poll loop catches it by iterating every registered
//! `(owner, repo)` and calling
//! `GET /repos/<owner>/<repo>/releases/latest`. Any tag not yet in
//! the queue is enqueued as a `pending` poll-sourced job.
//!
//! The poll is deliberately independent of the dispatch path: both
//! can run concurrently without coordination, because the queue's
//! UNIQUE `(publisher_repo, tag, pipeline_step)` index makes double-
//! enqueue a no-op (dispatch wins if it beats the poll; poll wins if
//! dispatch is lost).

use std::sync::Arc;
use std::time::Duration;

use reqwest::{header, Client};
use serde::Deserialize;
use thiserror::Error;
use tracing::{debug, info, warn};

use crate::config::{GatewayConfig, Source, SourcesRegistry};
use crate::queue::{IntakeSource, JobEnqueue, JobQueue};

/// Configuration for the poll loop.
#[derive(Debug, Clone)]
pub struct PollConfig {
    /// Gap between full poll cycles. Spec target: 5 minutes.
    pub interval: Duration,
    /// Per-request HTTP timeout.
    pub request_timeout: Duration,
    /// Pause between per-source requests to give GitHub room under
    /// unauthenticated rate limits (60/h → one req per minute).
    pub between_sources: Duration,
}

impl Default for PollConfig {
    fn default() -> Self {
        Self {
            interval: Duration::from_secs(300),
            request_timeout: Duration::from_secs(15),
            between_sources: Duration::from_millis(100),
        }
    }
}

/// Minimal shape of the GitHub Releases API `latest` response the
/// poll cares about. Additional fields (prerelease, draft, assets,
/// ...) are M208's concern.
#[derive(Debug, Clone, Deserialize)]
pub struct ReleaseLatest {
    pub tag_name: String,
    #[serde(default)]
    pub draft: bool,
    #[serde(default)]
    pub prerelease: bool,
}

#[derive(Debug, Error)]
pub enum PollError {
    #[error("http: {0}")]
    Http(#[from] reqwest::Error),
    #[error("queue: {0}")]
    Queue(#[from] crate::queue::QueueError),
    #[error("upstream returned status {0}")]
    UpstreamStatus(u16),
}

/// HTTP client abstraction — lets tests swap the GitHub API for a
/// `wiremock` server.
pub struct ReleasesClient {
    http: Client,
    base: String,
    token: Option<String>,
}

impl ReleasesClient {
    pub fn new(config: &GatewayConfig, request_timeout: Duration) -> Result<Self, PollError> {
        let http = Client::builder()
            .user_agent("deskmodal-verification-gateway/0.1")
            .timeout(request_timeout)
            .build()?;
        Ok(Self {
            http,
            base: config.github_api_base.trim_end_matches('/').to_string(),
            token: config.github_token.clone(),
        })
    }

    /// Fetch the latest release for `owner/repo`. Returns `Ok(None)`
    /// on a 404 (no releases yet), `Err` on any other non-2xx.
    pub async fn latest(
        &self,
        owner: &str,
        repo: &str,
    ) -> Result<Option<ReleaseLatest>, PollError> {
        let url = format!("{}/repos/{}/{}/releases/latest", self.base, owner, repo);
        let mut req = self
            .http
            .get(&url)
            .header(header::ACCEPT, "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28");
        if let Some(token) = &self.token {
            req = req.bearer_auth(token);
        }
        let resp = req.send().await?;
        let status = resp.status();
        if status.as_u16() == 404 {
            return Ok(None);
        }
        if !status.is_success() {
            return Err(PollError::UpstreamStatus(status.as_u16()));
        }
        let rel: ReleaseLatest = resp.json().await?;
        Ok(Some(rel))
    }
}

/// One poll cycle over every registered source. Returns how many new
/// rows were inserted (useful for tests + metrics).
pub async fn run_poll_cycle(
    client: &ReleasesClient,
    registry: &SourcesRegistry,
    queue: &JobQueue,
    between_sources: Duration,
) -> usize {
    let mut inserted = 0usize;
    for source in registry.iter_sources() {
        match poll_one(client, source, queue).await {
            Ok(true) => inserted += 1,
            Ok(false) => {}
            Err(e) => warn!(
                owner = %source.owner,
                repo = %source.repo,
                error = %e,
                "poll: per-source failure (continuing)"
            ),
        }
        if !between_sources.is_zero() {
            tokio::time::sleep(between_sources).await;
        }
    }
    if inserted > 0 {
        info!(inserted, "poll cycle complete: new pending jobs enqueued");
    } else {
        debug!("poll cycle complete: no new jobs");
    }
    inserted
}

async fn poll_one(
    client: &ReleasesClient,
    source: &Source,
    queue: &JobQueue,
) -> Result<bool, PollError> {
    let Some(release) = client.latest(&source.owner, &source.repo).await? else {
        return Ok(false);
    };
    if release.draft || release.prerelease {
        return Ok(false);
    }
    let full_name = source.full_name();
    if queue.has_any_row_for(&full_name, &release.tag_name).await? {
        return Ok(false);
    }
    match queue
        .enqueue_pending(&full_name, &release.tag_name, IntakeSource::Poll)
        .await?
    {
        JobEnqueue::Inserted(id) => {
            info!(id, publisher_repo = %full_name, tag = %release.tag_name, "poll: enqueued gap");
            Ok(true)
        }
        JobEnqueue::AlreadyPresent => Ok(false),
    }
}

/// Run the poll loop forever. Intended to be spawned as a tokio task
/// by the binary. Exits on the `shutdown` cancellation signal.
pub async fn run_poll_loop(
    client: Arc<ReleasesClient>,
    registry: Arc<SourcesRegistry>,
    queue: JobQueue,
    poll_cfg: PollConfig,
    mut shutdown: tokio::sync::watch::Receiver<bool>,
) {
    info!(
        interval_secs = poll_cfg.interval.as_secs(),
        sources = registry.len(),
        "starting poll loop"
    );
    loop {
        // First cycle runs immediately; subsequent cycles wait for
        // `interval` or until shutdown fires.
        let _ = run_poll_cycle(&client, &registry, &queue, poll_cfg.between_sources).await;

        tokio::select! {
            _ = tokio::time::sleep(poll_cfg.interval) => continue,
            _ = shutdown.changed() => {
                if *shutdown.borrow() {
                    info!("poll loop: shutdown signal received");
                    break;
                }
            }
        }
    }
}
