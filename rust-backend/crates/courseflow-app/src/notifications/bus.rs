//! Cross-process fan-out through Redis pub/sub. The worker publishes; every
//! API instance subscribes and pushes to its local WebSocket/SSE clients.
//! Not durable by design: the `notifications` table is the record, the bus
//! is only the "wake up, something new" signal.

use courseflow_core::ids::{NotificationId, UserId};
use courseflow_core::notifications::NotificationEvent;
use futures::StreamExt;
use redis::AsyncCommands;
use secrecy::ExposeSecret;
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;
use tokio_util::sync::CancellationToken;

use crate::cache::RedisHandle;
use crate::config::RedisConfig;

/// What goes over the wire to clients.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WireEvent {
    pub id: NotificationId,
    pub user_id: UserId,
    pub version: u16,
    pub occurred_at: chrono::DateTime<chrono::Utc>,
    #[serde(flatten)]
    pub event: NotificationEvent,
}

#[derive(Debug, Clone)]
pub struct NotificationBus {
    redis: Option<RedisHandle>,
    channel: String,
    /// Local fan-out: subscribers inside this process (socket tasks).
    local: broadcast::Sender<WireEvent>,
}

impl NotificationBus {
    pub fn new(redis: Option<RedisHandle>) -> Self {
        let channel =
            redis.as_ref().map(|r| r.key(&["notifications"])).unwrap_or_else(|| "cf:notifications".to_owned());
        let (local, _) = broadcast::channel(1024);
        Self { redis, channel, local }
    }

    pub fn subscribe_local(&self) -> broadcast::Receiver<WireEvent> {
        self.local.subscribe()
    }

    /// Publish to Redis when available; always fan out locally so that a
    /// single-process deployment works without Redis at all.
    pub async fn publish(&self, event: &WireEvent) {
        let _ = self.local.send(event.clone());
        let Some(redis) = &self.redis else { return };
        let Ok(json) = serde_json::to_string(event) else { return };
        let mut conn = redis.conn();
        if let Err(err) = conn.publish::<_, _, ()>(&self.channel, json).await {
            tracing::warn!(error = %err, "notification publish failed");
        }
    }

    /// Long-running task for API processes: forwards Redis messages into the
    /// local broadcast channel until cancelled. Reconnects on failure.
    pub async fn run_subscriber(&self, config: &RedisConfig, cancel: CancellationToken) {
        let Some(_) = &self.redis else { return };
        loop {
            if cancel.is_cancelled() {
                return;
            }
            match self.subscribe_once(config, &cancel).await {
                Ok(()) => return,
                Err(err) => {
                    tracing::warn!(error = %err, "pub/sub subscriber failed, reconnecting in 2s");
                    tokio::select! {
                        _ = cancel.cancelled() => return,
                        _ = tokio::time::sleep(std::time::Duration::from_secs(2)) => {}
                    }
                }
            }
        }
    }

    async fn subscribe_once(&self, config: &RedisConfig, cancel: &CancellationToken) -> redis::RedisResult<()> {
        let client = redis::Client::open(config.url.expose_secret())?;
        let mut pubsub = client.get_async_pubsub().await?;
        pubsub.subscribe(&self.channel).await?;
        tracing::info!(channel = %self.channel, "subscribed to notification bus");
        let mut stream = pubsub.on_message();
        loop {
            tokio::select! {
                _ = cancel.cancelled() => return Ok(()),
                msg = stream.next() => {
                    let Some(msg) = msg else { return Err(redis::RedisError::from((redis::ErrorKind::Io, "pub/sub stream ended"))) };
                    let payload: String = msg.get_payload()?;
                    match serde_json::from_str::<WireEvent>(&payload) {
                        Ok(event) => { let _ = self.local.send(event); }
                        Err(err) => tracing::warn!(error = %err, "malformed bus message"),
                    }
                }
            }
        }
    }
}
