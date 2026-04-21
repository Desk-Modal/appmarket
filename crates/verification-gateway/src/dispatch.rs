//! axum `/dispatch` handler + HMAC verification + `AppState`.
//!
//! Per ADR-0007, intake is GitHub `repository_dispatch` only. The
//! dispatch payload shape (per M202 spec):
//!
//! ```json
//! {
//!   "repo":             "owner/repo",
//!   "tag":              "v1.2.3",
//!   "asset_base_url":   "https://github.com/owner/repo/releases/download/v1.2.3",
//!   "publisher_key_id": "deskmodal-ci"
//! }
//! ```
//!
//! HMAC-SHA256 verification:
//! - Publisher CI signs the raw request body with a shared secret
//!   held in the Desk-Modal/appmarket GitHub Actions secret
//!   `APPMARKET_DISPATCH_TOKEN_<PUBLISHER_KEY_ID>`.
//! - The HMAC goes into the `X-AppMarket-Signature` header as
//!   `sha256=<hex>`.
//! - The gateway recomputes + constant-time compares (via `subtle`).
//!
//! Rejections (HTTP 400 + JSON body `{reason: "..."}`):
//! - `missing_signature` — header absent or malformed.
//! - `invalid_signature` — HMAC mismatch.
//! - `unregistered_publisher` — `(owner, repo)` not in `sources.json`.
//! - `malformed_payload` — JSON parse or shape error.
//!
//! On success: HTTP 202 + `{enqueued: true | false, job_id: ...}`.

use std::sync::Arc;

use axum::{
    body::Bytes,
    extract::State,
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::post,
    Json, Router,
};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::Sha256;
use subtle::ConstantTimeEq;
use tracing::{error, info, warn};

use crate::config::{GatewayConfig, SourcesRegistry};
use crate::queue::{IntakeSource, JobEnqueue, JobQueue};

type HmacSha256 = Hmac<Sha256>;

/// Header carrying the publisher's HMAC signature over the raw body.
/// Matches GitHub webhook convention (`sha256=<hex>`).
pub const SIGNATURE_HEADER: &str = "x-appmarket-signature";

/// Header carrying the dispatch event-type. Must equal
/// `release-published` for this intake.
pub const EVENT_HEADER: &str = "x-appmarket-event";

/// Expected value for [`EVENT_HEADER`].
pub const EVENT_RELEASE_PUBLISHED: &str = "release-published";

/// Shared application state — axum handlers hold a cloned `Arc` over
/// this via `State<AppState>`.
#[derive(Debug, Clone)]
pub struct AppState {
    pub config: Arc<GatewayConfig>,
    pub registry: Arc<SourcesRegistry>,
    pub queue: JobQueue,
}

/// Dispatch JSON body shape.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DispatchPayload {
    /// `owner/repo` — the publisher's plugin source repo.
    pub repo: String,
    /// Release tag (e.g., "v1.2.3").
    pub tag: String,
    /// Where release assets live; the verifier pipeline (M208) will
    /// fetch manifests + checksums from here. Kept opaque by the
    /// gateway skeleton.
    pub asset_base_url: String,
    /// Which `publisher_keys` id produced the signature over the
    /// assets. Enforced against `sources.json[*].publisher_key_id`.
    pub publisher_key_id: String,
}

/// Response body for a rejection.
#[derive(Debug, Serialize)]
struct ErrorBody<'a> {
    reason: &'a str,
}

/// Response body for a successful enqueue.
#[derive(Debug, Serialize)]
struct AcceptedBody {
    enqueued: bool,
    /// `inserted` → new row, `already_present` → idempotent no-op.
    status: &'static str,
    /// Publisher repo the gateway accepted the dispatch for.
    publisher_repo: String,
    tag: String,
}

/// Build the axum Router + shared state. No socket binding — the
/// caller wires this into their runtime. Used both by the binary and
/// by integration tests (via `tower::ServiceExt::oneshot`).
pub fn build_app(state: AppState) -> Router {
    Router::new()
        .route("/dispatch", post(dispatch_handler))
        .route("/healthz", axum::routing::get(healthz))
        .with_state(state)
}

async fn healthz() -> &'static str {
    "ok"
}

/// POST /dispatch — `repository_dispatch` intake.
async fn dispatch_handler(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    // -- 1. Event-type header ------------------------------------------
    let event = headers
        .get(EVENT_HEADER)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    if event != EVENT_RELEASE_PUBLISHED {
        warn!(event, "rejecting dispatch: wrong event type");
        return reject(StatusCode::BAD_REQUEST, "invalid_event");
    }

    // -- 2. HMAC signature ---------------------------------------------
    let sig_header = headers.get(SIGNATURE_HEADER).and_then(|v| v.to_str().ok());
    let Some(sig_value) = sig_header else {
        warn!("rejecting dispatch: missing signature header");
        return reject(StatusCode::BAD_REQUEST, "missing_signature");
    };
    let Some(provided_hex) = sig_value.strip_prefix("sha256=") else {
        warn!(sig_value, "rejecting dispatch: malformed signature prefix");
        return reject(StatusCode::BAD_REQUEST, "missing_signature");
    };
    let Ok(provided_bytes) = hex::decode(provided_hex) else {
        warn!("rejecting dispatch: non-hex signature");
        return reject(StatusCode::BAD_REQUEST, "invalid_signature");
    };

    let Ok(mut mac) = HmacSha256::new_from_slice(&state.config.dispatch_token) else {
        error!("dispatch_token empty or invalid length — refusing to verify");
        return reject(StatusCode::INTERNAL_SERVER_ERROR, "server_misconfigured");
    };
    mac.update(&body);
    let expected = mac.finalize().into_bytes();
    // Constant-time compare to avoid timing leaks.
    if provided_bytes.len() != expected.len() || expected.ct_eq(&provided_bytes).unwrap_u8() != 1 {
        warn!("rejecting dispatch: invalid signature");
        return reject(StatusCode::BAD_REQUEST, "invalid_signature");
    }

    // -- 3. Parse JSON body --------------------------------------------
    let payload: DispatchPayload = match serde_json::from_slice(&body) {
        Ok(p) => p,
        Err(e) => {
            warn!(error = %e, "rejecting dispatch: malformed payload");
            return reject(StatusCode::BAD_REQUEST, "malformed_payload");
        }
    };

    // -- 4. Registration guard -----------------------------------------
    let (owner, repo) = match split_owner_repo(&payload.repo) {
        Some(pair) => pair,
        None => {
            warn!(repo = %payload.repo, "rejecting dispatch: repo field not in 'owner/repo' form");
            return reject(StatusCode::BAD_REQUEST, "malformed_payload");
        }
    };
    let Some(source) = state.registry.find_source(owner, repo) else {
        warn!(%owner, %repo, "rejecting dispatch: unregistered publisher");
        return reject(StatusCode::BAD_REQUEST, "unregistered_publisher");
    };

    // Publisher-key binding: the signed dispatch must declare the key
    // id that `sources.json` has bound to the repo. This enforces the
    // per-publisher trust anchor (open question from spec, closed as
    // "per-publisher" — a key for repo A cannot be reused for repo B).
    let expected_key_id = source.effective_key_id();
    if payload.publisher_key_id != expected_key_id {
        warn!(
            got = %payload.publisher_key_id,
            expected = %expected_key_id,
            "rejecting dispatch: publisher_key_id mismatch"
        );
        return reject(StatusCode::BAD_REQUEST, "publisher_key_mismatch");
    }

    // -- 5. Enqueue ----------------------------------------------------
    let full_name = source.full_name();
    match state
        .queue
        .enqueue_pending(&full_name, &payload.tag, IntakeSource::Dispatch)
        .await
    {
        Ok(JobEnqueue::Inserted(id)) => {
            info!(id, publisher_repo = %full_name, tag = %payload.tag, "enqueued dispatch");
            accepted(
                StatusCode::ACCEPTED,
                &AcceptedBody {
                    enqueued: true,
                    status: "inserted",
                    publisher_repo: full_name,
                    tag: payload.tag,
                },
            )
        }
        Ok(JobEnqueue::AlreadyPresent) => {
            info!(publisher_repo = %full_name, tag = %payload.tag, "dispatch already present (idempotent)");
            accepted(
                StatusCode::ACCEPTED,
                &AcceptedBody {
                    enqueued: false,
                    status: "already_present",
                    publisher_repo: full_name,
                    tag: payload.tag,
                },
            )
        }
        Err(e) => {
            error!(error = %e, "queue insert failed");
            reject(StatusCode::INTERNAL_SERVER_ERROR, "queue_unavailable")
        }
    }
}

fn split_owner_repo(repo: &str) -> Option<(&str, &str)> {
    let (owner, rest) = repo.split_once('/')?;
    if owner.is_empty() || rest.is_empty() || rest.contains('/') {
        return None;
    }
    Some((owner, rest))
}

fn reject(status: StatusCode, reason: &'static str) -> Response {
    (status, Json(json!(ErrorBody { reason }))).into_response()
}

fn accepted(status: StatusCode, body: &AcceptedBody) -> Response {
    (status, Json(body)).into_response()
}

/// Test helper: sign a body with the shared token and return the
/// header value a caller should set on `X-AppMarket-Signature`.
/// Exposed at module scope so integration tests can reuse it without
/// re-implementing the HMAC.
pub fn sign_body(token: &[u8], body: &[u8]) -> String {
    let mut mac = HmacSha256::new_from_slice(token).expect("HMAC accepts any key length");
    mac.update(body);
    format!("sha256={}", hex::encode(mac.finalize().into_bytes()))
}
