use std::time::Duration;

use redis::aio::{ConnectionManager, ConnectionManagerConfig};
use secrecy::ExposeSecret;

use crate::config::RedisConfig;

/// Cheap to clone: `ConnectionManager` multiplexes one TCP connection and
/// reconnects on its own.
#[derive(Clone)]
pub struct RedisHandle {
    manager: ConnectionManager,
    prefix: String,
}

impl std::fmt::Debug for RedisHandle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RedisHandle").field("prefix", &self.prefix).finish_non_exhaustive()
    }
}

impl RedisHandle {
    pub fn conn(&self) -> ConnectionManager {
        self.manager.clone()
    }

    /// `cf:course:<id>`; the prefix isolates environments sharing one Redis.
    pub fn key(&self, parts: &[&str]) -> String {
        let mut key = String::with_capacity(32);
        key.push_str(&self.prefix);
        for part in parts {
            key.push(':');
            key.push_str(part);
        }
        key
    }

    pub async fn ping(&self) -> redis::RedisResult<()> {
        let mut conn = self.conn();
        redis::cmd("PING").query_async::<String>(&mut conn).await.map(|_| ())
    }
}

/// Connects lazily: the API starts even when Redis is down, and readiness
/// reports the real state. Response timeouts are explicit so that a stalled
/// Redis cannot stall a request forever.
pub async fn connect(config: &RedisConfig) -> redis::RedisResult<RedisHandle> {
    let client = redis::Client::open(config.url.expose_secret())?;
    let manager_config = ConnectionManagerConfig::new()
        .set_connection_timeout(Some(Duration::from_secs(2)))
        .set_response_timeout(Some(Duration::from_millis(500)))
        .set_number_of_retries(3);
    let manager = ConnectionManager::new_with_config(client, manager_config).await?;
    Ok(RedisHandle { manager, prefix: config.key_prefix.clone() })
}
