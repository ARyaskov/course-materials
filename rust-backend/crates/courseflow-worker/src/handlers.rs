//! What each outbox event means. Handlers must be idempotent: at-least-once
//! delivery guarantees that some of them will run twice. Notifications derive
//! their id from the outbox row id, so a re-run inserts nothing new.

use std::sync::Arc;

use courseflow_app::enrollments::repo as enrollments;
use courseflow_app::errors::AppResult;
use courseflow_app::notifications::NotificationService;
use courseflow_app::outbox::OutboxPayload;
use courseflow_core::notifications::NotificationEvent;
use sqlx::PgPool;
use uuid::Uuid;

#[derive(Clone)]
pub struct Handlers {
    pub pool: PgPool,
    pub notifications: Arc<NotificationService>,
}

impl std::fmt::Debug for Handlers {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Handlers")
    }
}

impl Handlers {
    #[tracing::instrument(skip_all, fields(event_type = payload.event_type(), %source))]
    pub async fn handle(&self, source: Uuid, payload: OutboxPayload) -> AppResult<()> {
        match payload {
            OutboxPayload::Notify { user_id, event } => {
                self.notifications.deliver_once(source, "notify", user_id, event).await?;
            }
            OutboxPayload::PurchasePaid { purchase_id, user_id, course_id } => {
                // Enrollment was created in the webhook transaction; this hook
                // is where analytics / CRM / e-mail receipts would go.
                tracing::info!(%purchase_id, %user_id, %course_id, "purchase paid (mock receipt e-mail sent)");
            }
            OutboxPayload::LessonPublished { course_id, lesson_id, lesson_title } => {
                // Fan-out: one outbox row becomes N notifications, each with
                // an id derived from (row id, user id): a retry after a crash
                // only fills in the recipients that were missed.
                let students = enrollments::student_ids_for_course(&self.pool, course_id).await?;
                for user_id in students {
                    self.notifications
                        .deliver_once(
                            source,
                            &user_id.to_string(),
                            user_id,
                            NotificationEvent::LessonPublished {
                                course_id,
                                lesson_id,
                                lesson_title: lesson_title.clone(),
                            },
                        )
                        .await?;
                }
            }
        }
        Ok(())
    }
}
