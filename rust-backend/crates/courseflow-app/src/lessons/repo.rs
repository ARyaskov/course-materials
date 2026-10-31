use chrono::{DateTime, Utc};
use courseflow_core::ids::{CourseId, LessonId};
use courseflow_core::lessons::Lesson;
use sqlx::PgExecutor;
use uuid::Uuid;

use crate::errors::{AppError, AppResult};

#[derive(Debug, sqlx::FromRow)]
struct LessonRow {
    id: Uuid,
    course_id: Uuid,
    position: i32,
    title: String,
    content_md: String,
    is_free_preview: bool,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

impl From<LessonRow> for Lesson {
    fn from(r: LessonRow) -> Self {
        Lesson {
            id: LessonId(r.id),
            course_id: CourseId(r.course_id),
            position: r.position,
            title: r.title,
            content_md: r.content_md,
            is_free_preview: r.is_free_preview,
            created_at: r.created_at,
            updated_at: r.updated_at,
        }
    }
}

pub async fn insert(executor: impl PgExecutor<'_>, lesson: &Lesson) -> AppResult<()> {
    sqlx::query!(
        r#"INSERT INTO lessons (id, course_id, position, title, content_md, is_free_preview, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)"#,
        lesson.id.0,
        lesson.course_id.0,
        lesson.position,
        lesson.title,
        lesson.content_md,
        lesson.is_free_preview,
        lesson.created_at,
        lesson.updated_at
    )
    .execute(executor)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.is_unique_violation() => AppError::conflict("lesson position already taken"),
        _ => AppError::from(e),
    })?;
    Ok(())
}

pub async fn find_by_id(executor: impl PgExecutor<'_>, id: LessonId) -> AppResult<Option<Lesson>> {
    let row = sqlx::query_as!(
        LessonRow,
        r#"SELECT id, course_id, position, title, content_md, is_free_preview, created_at, updated_at
           FROM lessons WHERE id = $1"#,
        id.0
    )
    .fetch_optional(executor)
    .await?;
    Ok(row.map(Lesson::from))
}

pub async fn list_for_course(executor: impl PgExecutor<'_>, course_id: CourseId) -> AppResult<Vec<Lesson>> {
    let rows = sqlx::query_as!(
        LessonRow,
        r#"SELECT id, course_id, position, title, content_md, is_free_preview, created_at, updated_at
           FROM lessons WHERE course_id = $1 ORDER BY position"#,
        course_id.0
    )
    .fetch_all(executor)
    .await?;
    Ok(rows.into_iter().map(Lesson::from).collect())
}

pub async fn next_position(executor: impl PgExecutor<'_>, course_id: CourseId) -> AppResult<i32> {
    let max = sqlx::query_scalar!(
        r#"SELECT coalesce(max(position), 0) AS "max!" FROM lessons WHERE course_id = $1"#,
        course_id.0
    )
    .fetch_one(executor)
    .await?;
    Ok(max + 1)
}

pub async fn update(executor: impl PgExecutor<'_>, lesson: &Lesson) -> AppResult<()> {
    let r = sqlx::query!(
        r#"UPDATE lessons SET title = $2, content_md = $3, is_free_preview = $4, updated_at = $5 WHERE id = $1"#,
        lesson.id.0,
        lesson.title,
        lesson.content_md,
        lesson.is_free_preview,
        lesson.updated_at
    )
    .execute(executor)
    .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::not_found("lesson"));
    }
    Ok(())
}

pub async fn delete(executor: impl PgExecutor<'_>, id: LessonId) -> AppResult<bool> {
    let r = sqlx::query!("DELETE FROM lessons WHERE id = $1", id.0).execute(executor).await?;
    Ok(r.rows_affected() == 1)
}
