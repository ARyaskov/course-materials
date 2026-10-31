use std::sync::Arc;

use courseflow_core::ids::{NotificationId, UserId};
use courseflow_core::notifications::{Notification, NotificationEvent};
use courseflow_core::ports::Clock;
use sqlx::PgPool;
use uuid::Uuid;

use crate::errors::AppResult;
use crate::notifications::bus::{NotificationBus, WireEvent};
use crate::notifications::repo;

#[derive(Clone)]
pub struct NotificationService {
    pool: PgPool,
    bus: NotificationBus,
    clock: Arc<dyn Clock>,
}

impl std::fmt::Debug for NotificationService {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("NotificationService")
    }
}

impl NotificationService {
    pub fn new(pool: PgPool, bus: NotificationBus, clock: Arc<dyn Clock>) -> Self {
        Self { pool, bus, clock }
    }

    pub fn bus(&self) -> &NotificationBus {
        &self.bus
    }

    /// Called by the worker for every `Notify` outbox event: persist first
    /// (the record), then signal (the bus). If the signal is lost the client
    /// still sees the notification on its next fetch.
    #[tracing::instrument(skip(self, event), fields(kind = event.kind()))]
    pub async fn deliver(&self, user_id: UserId, event: NotificationEvent) -> AppResult<Notification> {
        let notification = Notification::new(user_id, event, self.clock.now());
        repo::insert(&self.pool, &notification).await?;
        self.bus
            .publish(&WireEvent {
                id: notification.id,
                user_id,
                version: NotificationEvent::VERSION,
                occurred_at: notification.created_at,
                event: notification.event.clone(),
            })
            .await;
        metrics::counter!("courseflow_notifications_delivered_total", "kind" => notification.event.kind()).increment(1);
        Ok(notification)
    }

    /// Delivery keyed by the source event: the outbox relay may run a handler
    /// twice, and the second run must not produce a second notification.
    /// `source` is the outbox row id; `salt` distinguishes fan-out recipients.
    pub async fn deliver_once(
        &self,
        source: Uuid,
        salt: &str,
        user_id: UserId,
        event: NotificationEvent,
    ) -> AppResult<Option<Notification>> {
        let id = NotificationId(Uuid::new_v5(&source, salt.as_bytes()));
        let notification = Notification::with_id(id, user_id, event, self.clock.now());
        if !repo::insert_if_absent(&self.pool, &notification).await? {
            tracing::debug!(notification_id = %id, "notification already delivered, skipping");
            return Ok(None);
        }
        self.bus
            .publish(&WireEvent {
                id: notification.id,
                user_id,
                version: NotificationEvent::VERSION,
                occurred_at: notification.created_at,
                event: notification.event.clone(),
            })
            .await;
        metrics::counter!("courseflow_notifications_delivered_total", "kind" => notification.event.kind()).increment(1);
        Ok(Some(notification))
    }

    pub async fn list_recent(&self, user_id: UserId, limit: i64) -> AppResult<Vec<Notification>> {
        repo::list_recent(&self.pool, user_id, limit.clamp(1, 100)).await
    }

    pub async fn mark_read(&self, user_id: UserId, id: NotificationId) -> AppResult<bool> {
        repo::mark_read(&self.pool, user_id, id, self.clock.now()).await
    }

    pub async fn unread_count(&self, user_id: UserId) -> AppResult<i64> {
        repo::unread_count(&self.pool, user_id).await
    }
}
