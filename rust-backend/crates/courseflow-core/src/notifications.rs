use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::ids::{CourseId, LessonId, NotificationId, PurchaseId, UserId};

/// Typed real-time protocol. `type` is the discriminator both in JSONB outbox
/// payloads and on the wire (WebSocket / SSE); `version` lets clients survive
/// evolution of a single event shape.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum NotificationEvent {
    Welcome { display_name: String },
    EmailVerification { token_hint: String },
    PasswordReset { token_hint: String },
    PurchaseCompleted { purchase_id: PurchaseId, course_id: CourseId, course_title: String },
    PurchaseFailed { purchase_id: PurchaseId, course_id: CourseId, reason: String },
    LessonPublished { course_id: CourseId, lesson_id: LessonId, lesson_title: String },
    CourseCompleted { course_id: CourseId, certificate_code: String },
}

impl NotificationEvent {
    pub const VERSION: u16 = 1;

    pub fn kind(&self) -> &'static str {
        match self {
            NotificationEvent::Welcome { .. } => "welcome",
            NotificationEvent::EmailVerification { .. } => "email_verification",
            NotificationEvent::PasswordReset { .. } => "password_reset",
            NotificationEvent::PurchaseCompleted { .. } => "purchase_completed",
            NotificationEvent::PurchaseFailed { .. } => "purchase_failed",
            NotificationEvent::LessonPublished { .. } => "lesson_published",
            NotificationEvent::CourseCompleted { .. } => "course_completed",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Notification {
    pub id: NotificationId,
    pub user_id: UserId,
    pub event: NotificationEvent,
    pub created_at: DateTime<Utc>,
    pub read_at: Option<DateTime<Utc>>,
}

impl Notification {
    pub fn new(user_id: UserId, event: NotificationEvent, now: DateTime<Utc>) -> Self {
        Self::with_id(NotificationId::new(), user_id, event, now)
    }

    /// Deterministic id (derived by the caller from the source event) makes
    /// re-delivery after a crash a no-op instead of a duplicate.
    pub fn with_id(id: NotificationId, user_id: UserId, event: NotificationEvent, now: DateTime<Utc>) -> Self {
        Self { id, user_id, event, created_at: now, read_at: None }
    }
}
