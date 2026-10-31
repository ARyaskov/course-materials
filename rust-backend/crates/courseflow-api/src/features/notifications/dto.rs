use chrono::{DateTime, Utc};
use courseflow_core::ids::NotificationId;
use courseflow_core::notifications::{Notification, NotificationEvent};
use serde::Serialize;
use utoipa::ToSchema;

#[derive(Debug, Serialize, ToSchema)]
pub struct NotificationResponse {
    pub id: NotificationId,
    pub version: u16,
    #[serde(flatten)]
    #[schema(value_type = Object)]
    pub event: NotificationEvent,
    pub created_at: DateTime<Utc>,
    pub read: bool,
}

impl From<Notification> for NotificationResponse {
    fn from(n: Notification) -> Self {
        Self {
            id: n.id,
            version: NotificationEvent::VERSION,
            event: n.event,
            created_at: n.created_at,
            read: n.read_at.is_some(),
        }
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct UnreadResponse {
    pub unread: i64,
}
