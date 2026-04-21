#![allow(clippy::unwrap_used, clippy::panic)]
//! Acceptance scenario #2 (M202 spec):
//!
//! > The dispatch payload is lost (network glitch, publisher workflow
//! > never called `notify-appmarket`); the 5-minute poll loop checks
//! > `GET /repos/<pub>/<repo>/releases/latest` for every registered
//! > source and picks up the missing tag.
//! >
//! > Observable: poll cycle observes the GitHub Releases API,
//! > detects the new tag not yet in the job queue, enqueues a
//! > `pending` job.
//!
//! Command:
//!   cargo test -p deskmodal-verification-gateway --test poll_fallback

#[path = "common/mod.rs"]
mod common;

use std::time::Duration;

use deskmodal_verification_gateway::{
    run_poll_cycle, GatewayConfig, JobQueue, ReleasesClient, SourcesRegistry,
};
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

use common::SOURCES_FIXTURE;

async fn build_mock_environment() -> (MockServer, SourcesRegistry, JobQueue, GatewayConfig) {
    let mock_server = MockServer::start().await;
    let registry =
        SourcesRegistry::load_from_slice(SOURCES_FIXTURE.as_bytes()).expect("fixture parses");
    let queue = JobQueue::new_in_memory().await.expect("sqlite opens");
    let config = GatewayConfig {
        dispatch_token: b"unused-in-poll-tests".to_vec(),
        github_api_base: mock_server.uri(),
        github_token: None,
    };
    (mock_server, registry, queue, config)
}

#[tokio::test]
async fn poll_cycle_enqueues_missing_tag_from_latest_release() {
    let (mock_server, registry, queue, config) = build_mock_environment().await;

    // The fixture has `Desk-Modal/optiscript` as the sole publisher.
    // Mock its `latest` release.
    Mock::given(method("GET"))
        .and(path("/repos/Desk-Modal/optiscript/releases/latest"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "tag_name": "v2.0.0",
            "draft": false,
            "prerelease": false
        })))
        .mount(&mock_server)
        .await;

    // Pre-assert: queue is empty — simulates the "dispatch was lost"
    // scenario from the acceptance clause.
    assert_eq!(queue.count_all().await.unwrap(), 0);

    let client = ReleasesClient::new(&config, Duration::from_secs(5)).expect("client");
    let inserted = run_poll_cycle(&client, &registry, &queue, Duration::ZERO).await;

    // Observable: pending row enqueued for the release the poll
    // discovered.
    assert_eq!(inserted, 1, "poll cycle should insert one gap row");
    let row = queue
        .get_pending("Desk-Modal/optiscript", "v2.0.0")
        .await
        .expect("queue read")
        .expect("row present");
    assert_eq!(row.pipeline_step, "pending");
    assert_eq!(row.decision, None, "pending row's decision must be NULL");
    assert_eq!(row.intake_source, "poll");
}

#[tokio::test]
async fn poll_skips_when_queue_already_has_tag() {
    // Simulates the race: dispatch succeeded first, then poll fires.
    // The poll MUST see the existing row and skip — no double enqueue.
    let (mock_server, registry, queue, config) = build_mock_environment().await;

    // Pre-enqueue the tag as if a dispatch had already landed it.
    queue
        .enqueue_pending(
            "Desk-Modal/optiscript",
            "v3.0.0",
            deskmodal_verification_gateway::queue::IntakeSource::Dispatch,
        )
        .await
        .unwrap();

    Mock::given(method("GET"))
        .and(path("/repos/Desk-Modal/optiscript/releases/latest"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "tag_name": "v3.0.0",
            "draft": false,
            "prerelease": false
        })))
        .mount(&mock_server)
        .await;

    let client = ReleasesClient::new(&config, Duration::from_secs(5)).expect("client");
    let inserted = run_poll_cycle(&client, &registry, &queue, Duration::ZERO).await;
    assert_eq!(
        inserted, 0,
        "poll must not double-enqueue when dispatch already landed the tag"
    );
    // Only the original dispatch row remains (no extra rows from poll).
    assert_eq!(queue.count_all().await.unwrap(), 1);
    let row = queue
        .get_pending("Desk-Modal/optiscript", "v3.0.0")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        row.intake_source, "dispatch",
        "the winning insert was the dispatch, not the poll"
    );
}

#[tokio::test]
async fn poll_ignores_draft_and_prerelease() {
    let (mock_server, registry, queue, config) = build_mock_environment().await;
    Mock::given(method("GET"))
        .and(path("/repos/Desk-Modal/optiscript/releases/latest"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "tag_name": "v4.0.0-rc1",
            "draft": false,
            "prerelease": true
        })))
        .mount(&mock_server)
        .await;
    let client = ReleasesClient::new(&config, Duration::from_secs(5)).expect("client");
    let inserted = run_poll_cycle(&client, &registry, &queue, Duration::ZERO).await;
    assert_eq!(inserted, 0, "prereleases must not be enqueued");
    assert_eq!(queue.count_all().await.unwrap(), 0);
}

#[tokio::test]
async fn poll_tolerates_404_no_releases_yet() {
    // A registered publisher may have ZERO releases. The poll MUST
    // shrug that off rather than error the whole cycle.
    let (mock_server, registry, queue, config) = build_mock_environment().await;
    Mock::given(method("GET"))
        .and(path("/repos/Desk-Modal/optiscript/releases/latest"))
        .respond_with(ResponseTemplate::new(404))
        .mount(&mock_server)
        .await;
    let client = ReleasesClient::new(&config, Duration::from_secs(5)).expect("client");
    let inserted = run_poll_cycle(&client, &registry, &queue, Duration::ZERO).await;
    assert_eq!(inserted, 0);
    assert_eq!(queue.count_all().await.unwrap(), 0);
}

#[tokio::test]
async fn poll_cycle_survives_per_source_upstream_error() {
    // When GitHub returns 500 for one source, the poll MUST continue
    // to the next source rather than abort. We only have one source
    // in the fixture, so this test asserts that the cycle returns
    // cleanly (no panic, no poisoned state) and inserts zero rows.
    let (mock_server, registry, queue, config) = build_mock_environment().await;
    Mock::given(method("GET"))
        .and(path("/repos/Desk-Modal/optiscript/releases/latest"))
        .respond_with(ResponseTemplate::new(500))
        .mount(&mock_server)
        .await;
    let client = ReleasesClient::new(&config, Duration::from_secs(5)).expect("client");
    let inserted = run_poll_cycle(&client, &registry, &queue, Duration::ZERO).await;
    assert_eq!(inserted, 0);
    assert_eq!(queue.count_all().await.unwrap(), 0);
}
