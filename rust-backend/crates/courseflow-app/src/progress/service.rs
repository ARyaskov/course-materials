use std::sync::Arc;

use courseflow_core::ids::{CourseId, LessonId, UserId};
use courseflow_core::notifications::NotificationEvent;
use courseflow_core::policy::Actor;
use courseflow_core::ports::Clock;
use courseflow_core::progress::{Certificate, CourseProgress};
use sqlx::PgPool;

use crate::auth::tokens;
use crate::enrollments::repo as enrollments;
use crate::errors::{AppError, AppResult};
use crate::lessons::repo as lessons;
use crate::outbox::{self, OutboxPayload};
use crate::progress::repo;

#[derive(Debug, Clone)]
pub struct CompletionOutcome {
    pub progress: CourseProgress,
    pub newly_completed: bool,
    pub certificate: Option<Certificate>,
}

#[derive(Clone)]
pub struct ProgressService {
    pool: PgPool,
    clock: Arc<dyn Clock>,
}

impl std::fmt::Debug for ProgressService {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ProgressService")
    }
}

impl ProgressService {
    pub fn new(pool: PgPool, clock: Arc<dyn Clock>) -> Self {
        Self { pool, clock }
    }

    /// Marks a lesson done and, if that completes the course, issues the
    /// certificate and queues the notification — all in one transaction.
    #[tracing::instrument(skip(self), fields(actor = %actor.id))]
    pub async fn complete_lesson(&self, actor: &Actor, lesson_id: LessonId) -> AppResult<CompletionOutcome> {
        let now = self.clock.now();
        let lesson = lessons::find_by_id(&self.pool, lesson_id).await?.ok_or(AppError::not_found("lesson"))?;
        if !enrollments::exists(&self.pool, actor.id, lesson.course_id).await? {
            return Err(courseflow_core::DomainError::PermissionDenied("enrollment required").into());
        }

        let mut tx = self.pool.begin().await?;
        let newly_completed = repo::mark_completed(&mut *tx, actor.id, lesson_id, now).await?;
        let progress = repo::course_progress(&mut *tx, actor.id, lesson.course_id).await?;
        let mut certificate = None;
        if progress.is_complete() {
            let cert = Certificate {
                user_id: actor.id,
                course_id: lesson.course_id,
                issued_at: now,
                code: tokens::certificate_code(),
            };
            if repo::insert_certificate(&mut *tx, &cert).await? {
                outbox::enqueue(
                    &mut *tx,
                    &OutboxPayload::Notify {
                        user_id: actor.id,
                        event: NotificationEvent::CourseCompleted {
                            course_id: lesson.course_id,
                            certificate_code: cert.code.clone(),
                        },
                    },
                    now,
                )
                .await?;
                certificate = Some(cert);
            } else {
                certificate = repo::find_certificate(&mut *tx, actor.id, lesson.course_id).await?;
            }
        }
        tx.commit().await?;
        Ok(CompletionOutcome { progress, newly_completed, certificate })
    }

    pub async fn course_progress(
        &self,
        user_id: UserId,
        course_id: CourseId,
    ) -> AppResult<(CourseProgress, Vec<LessonId>)> {
        let progress = repo::course_progress(&self.pool, user_id, course_id).await?;
        let completed = repo::completed_lesson_ids(&self.pool, user_id, course_id).await?;
        Ok((progress, completed))
    }

    pub async fn certificate(&self, user_id: UserId, course_id: CourseId) -> AppResult<Option<Certificate>> {
        repo::find_certificate(&self.pool, user_id, course_id).await
    }

    /// Public verification endpoint: anyone with the code can check it.
    pub async fn verify_certificate(&self, code: &str) -> AppResult<Certificate> {
        repo::find_certificate_by_code(&self.pool, code).await?.ok_or(AppError::not_found("certificate"))
    }
}
