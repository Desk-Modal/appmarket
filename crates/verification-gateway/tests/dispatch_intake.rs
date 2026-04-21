#![allow(clippy::unwrap_used, clippy::panic)]
//! Acceptance scenario #1 (M202 spec):
//!
//! > A registered publisher's CI publishes a GitHub Release; the
//! > `notify-appmarket` step fires `repository_dispatch` to
//! > `Desk-Modal/appmarket` with `event_type=release-published` +
//! > payload `{repo, tag, asset_base_url, publisher_key_id}`. The
//! > gateway receives it within 30 s.
//! >
//! > Observable: gateway writes a `pending` status row
//! > (`{publisher_repo, tag, pipeline_step: "pending", decision:
//! > null}`); webhook intake responds 202.
//!
//! The acceptance command is exactly:
//!   cargo test -p deskmodal-verification-gateway --test dispatch_intake

#[path = "common/mod.rs"]
mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use deskmodal_verification_gateway::dispatch::{
    sign_body, EVENT_HEADER, EVENT_RELEASE_PUBLISHED, SIGNATURE_HEADER,
};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use tower::ServiceExt; // `.oneshot`

use common::{build_test_state, router, DISPATCH_TOKEN};

#[tokio::test]
async fn dispatch_happy_path_writes_pending_row_and_202() {
    let state = build_test_state().await;
    let queue = state.queue.clone();
    let app = router(state);

    let body = serde_json::to_vec(&json!({
        "repo": "Desk-Modal/optiscript",
        "tag": "v1.2.3",
        "asset_base_url": "https://github.com/Desk-Modal/optiscript/releases/download/v1.2.3",
        "publisher_key_id": "deskmodal-ci"
    }))
    .unwrap();
    let sig = sign_body(DISPATCH_TOKEN, &body);

    let req = Request::builder()
        .method("POST")
        .uri("/dispatch")
        .header("content-type", "application/json")
        .header(EVENT_HEADER, EVENT_RELEASE_PUBLISHED)
        .header(SIGNATURE_HEADER, &sig)
        .body(Body::from(body))
        .unwrap();

    let resp = app.oneshot(req).await.expect("router responds");
    let status = resp.status();
    let body_bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let body_json: Value = serde_json::from_slice(&body_bytes).expect("response is JSON");

    assert_eq!(
        status,
        StatusCode::ACCEPTED,
        "expected 202; body = {body_json}"
    );
    assert_eq!(body_json["enqueued"], Value::Bool(true));
    assert_eq!(body_json["status"], Value::String("inserted".into()));
    assert_eq!(
        body_json["publisher_repo"],
        Value::String("Desk-Modal/optiscript".into())
    );
    assert_eq!(body_json["tag"], Value::String("v1.2.3".into()));

    // Observable: pending row in queue with decision=null.
    let pending = queue
        .get_pending("Desk-Modal/optiscript", "v1.2.3")
        .await
        .expect("queue read")
        .expect("row present");
    assert_eq!(pending.publisher_repo, "Desk-Modal/optiscript");
    assert_eq!(pending.tag, "v1.2.3");
    assert_eq!(pending.pipeline_step, "pending");
    assert!(
        pending.decision.is_none(),
        "decision must be NULL on pending row"
    );
    assert_eq!(pending.intake_source, "dispatch");
}

#[tokio::test]
async fn dispatch_without_signature_rejected() {
    let state = build_test_state().await;
    let app = router(state);

    let body = serde_json::to_vec(&json!({
        "repo": "Desk-Modal/optiscript",
        "tag": "v9.9.9",
        "asset_base_url": "https://example.invalid",
        "publisher_key_id": "deskmodal-ci"
    }))
    .unwrap();

    let req = Request::builder()
        .method("POST")
        .uri("/dispatch")
        .header(EVENT_HEADER, EVENT_RELEASE_PUBLISHED)
        .header("content-type", "application/json")
        .body(Body::from(body))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["reason"], Value::String("missing_signature".into()));
}

#[tokio::test]
async fn dispatch_with_bad_signature_rejected() {
    let state = build_test_state().await;
    let app = router(state);

    let body = serde_json::to_vec(&json!({
        "repo": "Desk-Modal/optiscript",
        "tag": "v2.0.0",
        "asset_base_url": "https://example.invalid",
        "publisher_key_id": "deskmodal-ci"
    }))
    .unwrap();
    // Sign with the WRONG key; gateway expects `DISPATCH_TOKEN`.
    let bad_sig = sign_body(b"wrong-key", &body);

    let req = Request::builder()
        .method("POST")
        .uri("/dispatch")
        .header(EVENT_HEADER, EVENT_RELEASE_PUBLISHED)
        .header(SIGNATURE_HEADER, bad_sig)
        .header("content-type", "application/json")
        .body(Body::from(body))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["reason"], Value::String("invalid_signature".into()));
}

#[tokio::test]
async fn dispatch_wrong_event_type_rejected() {
    let state = build_test_state().await;
    let app = router(state);
    let body = serde_json::to_vec(&json!({
        "repo": "Desk-Modal/optiscript",
        "tag": "v1.0.0",
        "asset_base_url": "https://example.invalid",
        "publisher_key_id": "deskmodal-ci"
    }))
    .unwrap();
    let sig = sign_body(DISPATCH_TOKEN, &body);
    let req = Request::builder()
        .method("POST")
        .uri("/dispatch")
        .header(EVENT_HEADER, "something-else")
        .header(SIGNATURE_HEADER, sig)
        .header("content-type", "application/json")
        .body(Body::from(body))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["reason"], Value::String("invalid_event".into()));
}

#[tokio::test]
async fn dispatch_idempotent_same_repo_tag() {
    let state = build_test_state().await;
    let queue = state.queue.clone();
    let app = router(state);

    let body = serde_json::to_vec(&json!({
        "repo": "Desk-Modal/optiscript",
        "tag": "v1.2.3",
        "asset_base_url": "https://example.invalid",
        "publisher_key_id": "deskmodal-ci"
    }))
    .unwrap();
    let sig = sign_body(DISPATCH_TOKEN, &body);

    // First dispatch: inserted.
    let first = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dispatch")
                .header(EVENT_HEADER, EVENT_RELEASE_PUBLISHED)
                .header(SIGNATURE_HEADER, &sig)
                .header("content-type", "application/json")
                .body(Body::from(body.clone()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::ACCEPTED);
    let first_body: Value =
        serde_json::from_slice(&first.into_body().collect().await.unwrap().to_bytes()).unwrap();
    assert_eq!(first_body["status"], "inserted");

    // Second dispatch of the same (repo, tag): already_present.
    let second = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dispatch")
                .header(EVENT_HEADER, EVENT_RELEASE_PUBLISHED)
                .header(SIGNATURE_HEADER, sig)
                .header("content-type", "application/json")
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(second.status(), StatusCode::ACCEPTED);
    let second_body: Value =
        serde_json::from_slice(&second.into_body().collect().await.unwrap().to_bytes()).unwrap();
    assert_eq!(second_body["status"], "already_present");

    // Exactly one pending row.
    assert_eq!(queue.count_step("pending").await.unwrap(), 1);
}
