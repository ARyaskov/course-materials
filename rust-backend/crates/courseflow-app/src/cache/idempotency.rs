//! `Idempotency-Key` handling for state-changing requests.
//!
//! Key = user + route + client key. The first request claims the key with
//! `SET NX` (status "in_progress"); when it finishes, the response is stored
//! under the same key. Replays return the stored response; a concurrent
//! replay while the first is still running gets a conflict.

use std::time::Duration;

use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::cache::RedisHandle;
use crate::errors::{AppError, AppResult};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StoredResponse {
    pub status: u16,
    pub body: String,
    /// Hash of the request body: the same key with a different payload is a
    /// client bug, not a replay.
    pub request_hash: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
enum Entry {
    InProgress { request_hash: String },
    Done(StoredResponse),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IdempotencyOutcome {
    /// First time we see this key: proceed and call `finish` afterwards.
    Proceed,
    /// Same request already completed: return this response verbatim.
    Replay(StoredResponse),
    /// Same key, still running elsewhere.
    InProgress,
    /// Same key, different request body.
    Mismatch,
}

#[derive(Debug, Clone)]
pub struct IdempotencyGuard {
    redis: Option<RedisHandle>,
    ttl: Duration,
}

impl IdempotencyGuard {
    pub fn new(redis: Option<RedisHandle>, ttl: Duration) -> Self {
        Self { redis, ttl }
    }

    pub fn disabled() -> Self {
        Self { redis: None, ttl: Duration::ZERO }
    }

    pub fn is_enabled(&self) -> bool {
        self.redis.is_some()
    }

    pub fn hash_request(body: &[u8]) -> String {
        hex::encode(Sha256::digest(body))
    }

    fn key(&self, redis: &RedisHandle, user: &str, route: &str, client_key: &str) -> String {
        redis.key(&["idem", user, route, client_key])
    }

    /// Fail-closed: without Redis we cannot promise "exactly once", so the
    /// request is refused with 503 rather than executed twice.
    pub async fn begin(
        &self,
        user: &str,
        route: &str,
        client_key: &str,
        request_hash: &str,
    ) -> AppResult<IdempotencyOutcome> {
        let Some(redis) = &self.redis else {
            return Err(AppError::Unavailable("idempotency store".to_owned()));
        };
        let key = self.key(redis, user, route, client_key);
        let mut conn = redis.conn();
        let marker = serde_json::to_string(&Entry::InProgress { request_hash: request_hash.to_owned() })?;
        let opts = redis::SetOptions::default()
            .conditional_set(redis::ExistenceCheck::NX)
            .with_expiration(redis::SetExpiry::EX(self.ttl.as_secs()));
        let claimed: Option<String> = conn.set_options(&key, &marker, opts).await?;
        if claimed.is_some() {
            return Ok(IdempotencyOutcome::Proceed);
        }
        let existing: Option<String> = conn.get(&key).await?;
        let Some(existing) = existing else {
            // Expired between SET NX and GET: extremely rare, treat as new.
            return Ok(IdempotencyOutcome::Proceed);
        };
        Ok(match serde_json::from_str::<Entry>(&existing)? {
            Entry::InProgress { request_hash: h } if h == request_hash => IdempotencyOutcome::InProgress,
            Entry::Done(stored) if stored.request_hash == request_hash => IdempotencyOutcome::Replay(stored),
            _ => IdempotencyOutcome::Mismatch,
        })
    }

    pub async fn finish(&self, user: &str, route: &str, client_key: &str, response: StoredResponse) -> AppResult<()> {
        let Some(redis) = &self.redis else { return Ok(()) };
        let key = self.key(redis, user, route, client_key);
        let mut conn = redis.conn();
        let value = serde_json::to_string(&Entry::Done(response))?;
        conn.set_ex::<_, _, ()>(&key, value, self.ttl.as_secs()).await?;
        Ok(())
    }

    /// The handler failed with a 5xx: release the key so the client may retry.
    pub async fn abandon(&self, user: &str, route: &str, client_key: &str) {
        let Some(redis) = &self.redis else { return };
        let key = self.key(redis, user, route, client_key);
        let mut conn = redis.conn();
        let _ = conn.del::<_, ()>(&key).await;
    }
}
