//! Transactional outbox. `enqueue` is called inside the business transaction;
//! the worker drains rows with `claim_batch` (FOR UPDATE SKIP LOCKED) and
//! reports the outcome with `mark_done` / `mark_failed`.

pub mod repo;

use courseflow_core::ids::{CourseId, PurchaseId, UserId};
use courseflow_core::notifications::NotificationEvent;
use serde::{Deserialize, Serialize};

pub use repo::{
    OutboxRow, claim_batch, delete_done, enqueue, mark_done, mark_failed, pending_count, requeue_expired_locks,
};

/// Everything that can be written to the outbox. Tagged JSON keeps the table
/// generic while the payload stays typed in Rust.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum OutboxPayload {
    Notify {
        user_id: UserId,
        event: NotificationEvent,
    },
    /// A purchase became paid: enrollment already exists, downstream effects
    /// (certificate bookkeeping, analytics) may hang off this later.
    PurchasePaid {
        purchase_id: PurchaseId,
        user_id: UserId,
        course_id: CourseId,
    },
    /// A lesson was added to a published course: notify enrolled students.
    LessonPublished {
        course_id: CourseId,
        lesson_id: courseflow_core::ids::LessonId,
        lesson_title: String,
    },
}

impl OutboxPayload {
    pub fn event_type(&self) -> &'static str {
        match self {
            OutboxPayload::Notify { .. } => "notify",
            OutboxPayload::PurchasePaid { .. } => "purchase_paid",
            OutboxPayload::LessonPublished { .. } => "lesson_published",
        }
    }
}
