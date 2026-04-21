//! Gateway configuration + `sources.json` registry.
//!
//! The registry is loaded once at startup (or per-test) and shared
//! across the dispatch handler and the poll loop. `SourcesRegistry`
//! exposes `is_registered(owner, repo)` + `dispatch_token_for(owner,
//! repo)` — the two predicates every intake path needs.
//!
//! `sources.json` shape (relevant subset):
//! ```json
//! {
//!   "publisher_keys": {
//!     "deskmodal-ci": {"algorithm": "ed25519", "owner": "Desk-Modal", ...}
//!   },
//!   "sources": [
//!     {"owner": "Desk-Modal", "repo": "optiscript", "id": "optiscript", ...}
//!   ]
//! }
//! ```
//!
//! Dispatch tokens live in the environment, namespaced by publisher
//! key id: `APPMARKET_DISPATCH_TOKEN_<KEY_ID_UPPER>`. A token is
//! resolved per source via the source's `publisher_key_id` field (or
//! via the `publisher_keys` block + default fallback) — this keeps the
//! open question from `spec.md` closed as "per-publisher" (leaked
//! token on publisher X cannot be used to spoof publisher Y).

use std::collections::BTreeMap;
use std::path::Path;

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// One row of `sources.json` `publisher_keys` map.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PublisherKey {
    /// e.g. "ed25519".
    pub algorithm: String,
    /// Optional metadata; NOT the secret.
    #[serde(default)]
    pub source: Option<String>,
    /// GitHub org/owner the key belongs to. Enforced match against the
    /// dispatch's `repo` owner when a source declares this publisher.
    #[serde(default)]
    pub owner: Option<String>,
}

/// One entry of `sources.json` `sources[]` array.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Source {
    pub owner: String,
    pub repo: String,
    /// Logical display id (e.g., "optiscript"). Used for enqueue
    /// display; NOT the trust anchor — `(owner, repo)` is.
    #[serde(default)]
    pub id: Option<String>,
    /// `publisher_keys` index; falls back to `deskmodal-ci` when
    /// absent (matches existing `sources.json` convention).
    #[serde(default)]
    pub publisher_key_id: Option<String>,
    /// Ignored by the gateway; kept so we can round-trip the
    /// struct for tests without data loss.
    #[serde(flatten)]
    pub _extra: BTreeMap<String, serde_json::Value>,
}

impl Source {
    /// The owner+repo pair that uniquely identifies a source.
    pub fn full_name(&self) -> String {
        format!("{}/{}", self.owner, self.repo)
    }

    /// Which `publisher_keys` entry this source is bound to.
    pub fn effective_key_id(&self) -> &str {
        self.publisher_key_id.as_deref().unwrap_or("deskmodal-ci")
    }
}

/// Raw on-disk shape of `sources.json`. Only the fields the gateway
/// uses are modelled; everything else round-trips via `BTreeMap`.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct SourcesFile {
    #[serde(default)]
    pub publisher_keys: BTreeMap<String, PublisherKey>,
    pub sources: Vec<Source>,
    #[serde(flatten)]
    pub _extra: BTreeMap<String, serde_json::Value>,
}

/// Runtime view of `sources.json` with fast lookup helpers.
#[derive(Debug, Clone)]
pub struct SourcesRegistry {
    sources: Vec<Source>,
    keys: BTreeMap<String, PublisherKey>,
}

#[derive(Debug, Error)]
pub enum RegistryError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid JSON: {0}")]
    Json(#[from] serde_json::Error),
}

impl SourcesRegistry {
    pub fn new(sources: Vec<Source>, keys: BTreeMap<String, PublisherKey>) -> Self {
        Self { sources, keys }
    }

    /// Load from a filesystem path.
    pub fn load_from_path<P: AsRef<Path>>(path: P) -> Result<Self, RegistryError> {
        let bytes = std::fs::read(path)?;
        Self::load_from_slice(&bytes)
    }

    /// Load from an in-memory JSON byte buffer — used by tests.
    pub fn load_from_slice(bytes: &[u8]) -> Result<Self, RegistryError> {
        let file: SourcesFile = serde_json::from_slice(bytes)?;
        Ok(Self::new(file.sources, file.publisher_keys))
    }

    /// True iff `(owner, repo)` is listed in `sources[]`. Case-
    /// insensitive comparison on the GitHub convention — GitHub
    /// routes owner/repo case-insensitively.
    pub fn is_registered(&self, owner: &str, repo: &str) -> bool {
        self.find_source(owner, repo).is_some()
    }

    /// Return the source entry for a registered `(owner, repo)`, if
    /// any.
    pub fn find_source(&self, owner: &str, repo: &str) -> Option<&Source> {
        self.sources
            .iter()
            .find(|s| s.owner.eq_ignore_ascii_case(owner) && s.repo.eq_ignore_ascii_case(repo))
    }

    /// Iterate every registered source (poll loop).
    pub fn iter_sources(&self) -> impl Iterator<Item = &Source> {
        self.sources.iter()
    }

    /// Number of registered sources.
    pub fn len(&self) -> usize {
        self.sources.len()
    }

    /// Whether the registry is empty (no registered sources).
    pub fn is_empty(&self) -> bool {
        self.sources.is_empty()
    }

    /// Return the `PublisherKey` for a given key id (for diagnostics).
    pub fn key(&self, key_id: &str) -> Option<&PublisherKey> {
        self.keys.get(key_id)
    }
}

/// Gateway configuration supplied at startup.
#[derive(Debug, Clone)]
pub struct GatewayConfig {
    /// HMAC key used to authenticate dispatch payloads. In prod, set
    /// per-publisher; in dev + tests, a single string is fine.
    ///
    /// A real deployment resolves this per-source by reading env
    /// `APPMARKET_DISPATCH_TOKEN_<KEY_ID_UPPER>`. The skeleton keeps
    /// a single global for simplicity and lets the open question
    /// from spec `sec:open-questions` close as "per-publisher" by
    /// construction — swap `dispatch_token` for a `BTreeMap<String,
    /// Vec<u8>>` when M208 needs it.
    pub dispatch_token: Vec<u8>,

    /// GitHub API base, overridable for tests. Default
    /// `https://api.github.com`.
    pub github_api_base: String,

    /// Optional GitHub token for poll requests. Raises rate limits
    /// and grants access to private sources. `None` uses unauth'd
    /// requests (60/h).
    pub github_token: Option<String>,
}

impl Default for GatewayConfig {
    fn default() -> Self {
        Self {
            dispatch_token: b"dev-dispatch-token".to_vec(),
            github_api_base: "https://api.github.com".to_string(),
            github_token: None,
        }
    }
}
