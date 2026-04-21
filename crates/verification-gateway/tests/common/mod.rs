//! Shared test helpers.
//!
//! Because the three test binaries each get their own module tree,
//! this file is re-`include!`d rather than made a proper crate
//! module. See individual test files — each `#[path = "common/mod.rs"]`
//! imports this helper. Any individual test binary may use only a
//! subset of the helpers — the allow-deadcode below silences the
//! cross-binary warnings that would otherwise appear.

#![allow(dead_code, clippy::unwrap_used, clippy::panic)]

use std::sync::Arc;

use deskmodal_verification_gateway::{
    build_app, AppState, GatewayConfig, JobQueue, SourcesRegistry,
};

pub const DISPATCH_TOKEN: &[u8] = b"test-dispatch-token-abcdefghijklmnop";

/// A minimal `sources.json` with one registered publisher.
/// Matches the existing shape at
/// `marketplace/appmarket/sources.json` (workspace-relative path).
pub const SOURCES_FIXTURE: &str = r#"{
    "publisher_keys": {
        "deskmodal-ci": {
            "algorithm": "ed25519",
            "source": "test",
            "owner": "Desk-Modal"
        }
    },
    "sources": [
        {
            "owner": "Desk-Modal",
            "repo": "optiscript",
            "id": "optiscript",
            "publisher_key_id": "deskmodal-ci"
        }
    ]
}"#;

pub async fn build_test_state() -> AppState {
    let registry = SourcesRegistry::load_from_slice(SOURCES_FIXTURE.as_bytes())
        .expect("fixture sources.json parses");
    let queue = JobQueue::new_in_memory()
        .await
        .expect("in-memory sqlite opens");
    let config = GatewayConfig {
        dispatch_token: DISPATCH_TOKEN.to_vec(),
        github_api_base: "http://127.0.0.1:9".to_string(), // unused in dispatch tests
        github_token: None,
    };
    AppState {
        config: Arc::new(config),
        registry: Arc::new(registry),
        queue,
    }
}

pub fn router(state: AppState) -> axum::Router {
    build_app(state)
}
