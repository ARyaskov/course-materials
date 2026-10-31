use std::sync::Arc;

use courseflow_core::ids::{CourseId, LessonId};
use courseflow_core::lessons::{Lesson, NewLesson};
use courseflow_core::policy::{self, Actor};
use courseflow_core::ports::Clock;
use sqlx::PgPool;

use crate::courses::repo as courses;
use crate::enrollments::repo as enrollments;
use crate::errors::{AppError, AppResult};
use crate::lessons::repo;
use crate::outbox::{self, OutboxPayload};

#[derive(Debug)]
pub struct LessonInput {
    pub title: String,
    pub content_md: String,
    pub is_free_preview: bool,
}

#[derive(Clone)]
pub struct LessonService {
    pool: PgPool,
    clock: Arc<dyn Clock>,
}

impl std::fmt::Debug for LessonService {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("LessonService")
    }
}

impl LessonService {
    pub fn new(pool: PgPool, clock: Arc<dyn Clock>) -> Self {
        Self { pool, clock }
    }

    /// Appends a lesson. Position is assigned inside the transaction while the
    /// course row is locked, so two authors' tabs cannot both take position 5.
    #[tracing::instrument(skip(self, input), fields(actor = %actor.id))]
    pub async fn add(&self, actor: &Actor, course_id: CourseId, input: LessonInput) -> AppResult<Lesson> {
        let now = self.clock.now();
        let mut tx = self.pool.begin().await?;
        let course = courses::find_by_id_for_update(&mut *tx, course_id).await?.ok_or(AppError::not_found("course"))?;
        policy::require_course_owner(actor, &course)?;
        let position = repo::next_position(&mut *tx, course_id).await?;
        let lesson = Lesson::create(
            NewLesson {
                course_id,
                position,
                title: input.title,
                content_md: input.content_md,
                is_free_preview: input.is_free_preview,
            },
            now,
        )?;
        repo::insert(&mut *tx, &lesson).await?;
        if course.is_published() {
            outbox::enqueue(
                &mut *tx,
                &OutboxPayload::LessonPublished { course_id, lesson_id: lesson.id, lesson_title: lesson.title.clone() },
                now,
            )
            .await?;
        }
        tx.commit().await?;
        Ok(lesson)
    }

    /// Lesson bodies are gated: enrolled students, the author, admins, and
    /// anyone for free-preview lessons.
    #[tracing::instrument(skip(self))]
    pub async fn get(&self, actor: Option<&Actor>, lesson_id: LessonId) -> AppResult<Lesson> {
        let lesson = repo::find_by_id(&self.pool, lesson_id).await?.ok_or(AppError::not_found("lesson"))?;
        let course = courses::find_by_id(&self.pool, lesson.course_id).await?.ok_or(AppError::not_found("course"))?;
        if !policy::can_view_course(actor, &course) {
            return Err(AppError::not_found("lesson"));
        }
        if lesson.is_free_preview || actor.is_some_and(|a| policy::require_course_owner(a, &course).is_ok()) {
            return Ok(lesson);
        }
        let Some(actor) = actor else {
            return Err(AppError::Unauthorized("login required"));
        };
        if !enrollments::exists(&self.pool, actor.id, course.id).await? {
            return Err(AppError::Domain(courseflow_core::DomainError::PermissionDenied("enrollment required")));
        }
        Ok(lesson)
    }

    /// Table of contents is public for published courses: titles only.
    #[tracing::instrument(skip(self))]
    pub async fn list(&self, actor: Option<&Actor>, course_id: CourseId) -> AppResult<Vec<Lesson>> {
        let course = courses::find_by_id(&self.pool, course_id).await?.ok_or(AppError::not_found("course"))?;
        if !policy::can_view_course(actor, &course) {
            return Err(AppError::not_found("course"));
        }
        repo::list_for_course(&self.pool, course_id).await
    }

    #[tracing::instrument(skip(self, input))]
    pub async fn update(&self, actor: &Actor, lesson_id: LessonId, input: LessonInput) -> AppResult<Lesson> {
        let mut lesson = repo::find_by_id(&self.pool, lesson_id).await?.ok_or(AppError::not_found("lesson"))?;
        let course = courses::find_by_id(&self.pool, lesson.course_id).await?.ok_or(AppError::not_found("course"))?;
        policy::require_course_owner(actor, &course)?;
        let title = input.title.trim();
        if title.is_empty() || title.chars().count() > Lesson::MAX_TITLE_LEN {
            return Err(courseflow_core::DomainError::validation("title", "must be 1..=200 characters").into());
        }
        lesson.title = title.to_owned();
        lesson.content_md = input.content_md;
        lesson.is_free_preview = input.is_free_preview;
        lesson.updated_at = self.clock.now();
        repo::update(&self.pool, &lesson).await?;
        Ok(lesson)
    }

    #[tracing::instrument(skip(self))]
    pub async fn delete(&self, actor: &Actor, lesson_id: LessonId) -> AppResult<()> {
        let lesson = repo::find_by_id(&self.pool, lesson_id).await?.ok_or(AppError::not_found("lesson"))?;
        let course = courses::find_by_id(&self.pool, lesson.course_id).await?.ok_or(AppError::not_found("course"))?;
        policy::require_course_owner(actor, &course)?;
        if course.is_published() {
            let n = courses::count_lessons(&self.pool, course.id).await?;
            if n <= 1 {
                return Err(AppError::conflict("a published course must keep at least one lesson"));
            }
        }
        repo::delete(&self.pool, lesson_id).await?;
        Ok(())
    }
}
