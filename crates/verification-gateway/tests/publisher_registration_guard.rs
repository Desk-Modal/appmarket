#![allow(clippy::unwrap_used, clippy::panic)]
//! Acceptance scenario #3 (M202 spec):
//!
//! > A `repository_dispatch` arrives from a publisher/repo NOT in
//! > `sources.json`. Observable: gateway rejects with HTTP 400 +
//! > `reason: unregistered_publisher`, no job enqueued.
//!
//! Command:
//!   cargo test -p deskmodal-verification-gateway --test publisher_registration_guard

#[path = "common/mod.rs"]
mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use deskmodal_verification_gateway::dispatch::{
    sign_body, EVENT_HEADER, EVENT_RELEASE_PUBLISHED, SIGNATURE_HEADER,
};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use tower::ServiceExt;

use common::{build_test_state, router, DISPATCH_TOKEN};

#[tokio::test]
async fn unregistered_publisher_rejected_and_no_row_enqueued() {
    let state = build_test_state().await;
    let queue = state.queue.clone();
    let app = router(state);

    // `sources.json` fixture only lists `Desk-Modal/optiscript`.
    // Every other (owner, repo) must be rejected.
    let body = serde_json::to_vec(&json!({
        "repo": "Some-Squatter/malicious-plugin",
        "tag": "v1.0.0",
        "asset_base_url": "https://evil.invalid/malicious-plugin/releases/download/v1.0.0",
        "publisher_key_id": "deskmodal-ci"
    }))
    .unwrap();
    // Attacker even has the HMAC token (the attack we guard against
    // is key leak → spoof registration; the `sources.json` check is
    // the trust anchor).
    let sig = sign_body(DISPATCH_TOKEN, &body);

    let req = Request::builder()
        .method("POST")
        .uri("/dispatch")
        .header(EVENT_HEADER, EVENT_RELEASE_PUBLISHED)
        .header(SIGNATURE_HEADER, sig)
        .header("content-type", "application/json")
        .body(Body::from(body))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["reason"], Value::String("unregistered_publisher".into()));

    // Observable: no rows written.
    assert_eq!(
        queue.count_all().await.unwrap(),
        0,
        "queue must remain empty after an unregistered-publisher rejection"
    );
}

#[tokio::test]
async fn malformed_repo_field_rejected() {
    let state = build_test_state().await;
    let queue = state.queue.clone();
    let app = router(state);

    // `repo` must be `owner/repo` form. `single-name` violates this
    // and MUST reject before the registration check.
    let body = serde_json::to_vec(&json!({
        "repo": "single-name",
        "tag": "v1.0.0",
        "asset_base_url": "https://example.invalid",
        "publisher_key_id": "deskmodal-ci"
    }))
    .unwrap();
    let sig = sign_body(DISPATCH_TOKEN, &body);
    let req = Request::builder()
        .method("POST")
        .uri("/dispatch")
        .header(EVENT_HEADER, EVENT_RELEASE_PUBLISHED)
        .header(SIGNATURE_HEADER, sig)
        .header("content-type", "application/json")
        .body(Body::from(body))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["reason"], Value::String("malformed_payload".into()));
    assert_eq!(queue.count_all().await.unwrap(), 0);
}

#[tokio::test]
async fn publisher_key_id_mismatch_rejected() {
    // The fixture binds `Desk-Modal/optiscript` to key id
    // `deskmodal-ci`. A dispatch that declares a different key id
    // (maybe a different-publisher key leaked) MUST be rejected
    // even though it's otherwise well-formed.
    let state = build_test_state().await;
    let queue = state.queue.clone();
    let app = router(state);

    let body = serde_json::to_vec(&json!({
        "repo": "Desk-Modal/optiscript",
        "tag": "v1.5.0",
        "asset_base_url": "https://example.invalid",
        "publisher_key_id": "some-other-key"
    }))
    .unwrap();
    let sig = sign_body(DISPATCH_TOKEN, &body);
    let req = Request::builder()
        .method("POST")
        .uri("/dispatch")
        .header(EVENT_HEADER, EVENT_RELEASE_PUBLISHED)
        .header(SIGNATURE_HEADER, sig)
        .header("content-type", "application/json")
        .body(Body::from(body))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["reason"], Value::String("publisher_key_mismatch".into()));
    assert_eq!(queue.count_all().await.unwrap(), 0);
}
