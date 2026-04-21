//! Verification Gateway binary entrypoint.
//!
//! Wires up the axum `/dispatch` handler + 5-minute poll loop against
//! a SQLite-backed job queue. Configuration is resolved from
//! environment variables; `sources.json` is read from the repo root
//! (path configurable via `APPMARKET_SOURCES_JSON`).
//!
//! Env vars:
//! - `APPMARKET_DISPATCH_TOKEN` — required. HMAC key for dispatch
//!   intake. Minimum 32 bytes recommended.
//! - `APPMARKET_SOURCES_JSON` — path to `sources.json`. Default
//!   `./sources.json`.
//! - `APPMARKET_DB_PATH` — SQLite file path. Default `./appmarket.db`.
//! - `APPMARKET_BIND` — `host:port`. Default `127.0.0.1:8787`.
//! - `APPMARKET_GITHUB_API_BASE` — override for the poll loop.
//!   Default `https://api.github.com`.
//! - `APPMARKET_GITHUB_TOKEN` — optional, raises poll rate limits.
//!
//! The binary is intentionally thin — everything meaningful lives in
//! the library crate so integration tests can exercise it without
//! binding a socket.

use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use deskmodal_verification_gateway::{
    build_app, run_poll_loop, AppState, GatewayConfig, JobQueue, PollConfig, ReleasesClient,
    SourcesRegistry,
};
use tokio::net::TcpListener;
use tokio::sync::watch;
use tracing::info;
use tracing_subscriber::{fmt, EnvFilter};

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing();

    let dispatch_token = std::env::var("APPMARKET_DISPATCH_TOKEN")
        .context("APPMARKET_DISPATCH_TOKEN env var is required")?;
    if dispatch_token.len() < 16 {
        anyhow::bail!("APPMARKET_DISPATCH_TOKEN must be ≥16 bytes (recommend 32+)");
    }
    let sources_path =
        std::env::var("APPMARKET_SOURCES_JSON").unwrap_or_else(|_| "./sources.json".to_string());
    let db_path =
        std::env::var("APPMARKET_DB_PATH").unwrap_or_else(|_| "./appmarket.db".to_string());
    let bind_addr =
        std::env::var("APPMARKET_BIND").unwrap_or_else(|_| "127.0.0.1:8787".to_string());
    let github_base = std::env::var("APPMARKET_GITHUB_API_BASE")
        .unwrap_or_else(|_| "https://api.github.com".to_string());
    let github_token = std::env::var("APPMARKET_GITHUB_TOKEN").ok();

    let config = GatewayConfig {
        dispatch_token: dispatch_token.into_bytes(),
        github_api_base: github_base,
        github_token,
    };

    let registry = SourcesRegistry::load_from_path(PathBuf::from(&sources_path))
        .with_context(|| format!("loading sources.json from {sources_path}"))?;
    info!(sources = registry.len(), "loaded sources.json");

    let queue = JobQueue::new_file(&db_path)
        .await
        .with_context(|| format!("opening queue DB at {db_path}"))?;

    let poll_cfg = PollConfig::default();
    let client = Arc::new(
        ReleasesClient::new(&config, poll_cfg.request_timeout)
            .context("constructing GitHub Releases HTTP client")?,
    );

    let registry_arc = Arc::new(registry);
    let state = AppState {
        config: Arc::new(config),
        registry: registry_arc.clone(),
        queue: queue.clone(),
    };

    let (shutdown_tx, shutdown_rx) = watch::channel(false);
    let poll_handle = tokio::spawn(run_poll_loop(
        client,
        registry_arc,
        queue.clone(),
        poll_cfg,
        shutdown_rx,
    ));

    let addr: SocketAddr = bind_addr
        .parse()
        .with_context(|| format!("parsing {bind_addr}"))?;
    let listener = TcpListener::bind(addr).await.context("binding")?;
    info!(%addr, "verification gateway listening");

    let app = build_app(state);

    // `tokio::signal::ctrl_c` triggers graceful shutdown of both the
    // axum server and the poll loop.
    let shutdown_signal = async move {
        let _ = tokio::signal::ctrl_c().await;
        info!("shutdown requested");
        let _ = shutdown_tx.send(true);
    };

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal)
        .await
        .context("axum serve")?;

    // Give the poll loop up to 2 s to finish its current cycle.
    let _ = tokio::time::timeout(Duration::from_secs(2), poll_handle).await;

    Ok(())
}

fn init_tracing() {
    fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info,deskmodal_verification_gateway=debug")),
        )
        .init();
}
