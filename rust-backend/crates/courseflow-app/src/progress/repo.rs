use chrono::{DateTime, Utc};
use courseflow_core::ids::{CourseId, LessonId, UserId};
use courseflow_core::progress::{Certificate, CourseProgress};
use sqlx::PgExecutor;

use crate::errors::AppResult;

/// Idempotent: completing an already completed lesson is not an error.
pub async fn mark_completed(
    executor: impl PgExecutor<'_>,
    user_id: UserId,
    lesson_id: LessonId,
    now: DateTime<Utc>,
) -> AppResult<bool> {
    let r = sqlx::query!(
        r#"INSERT INTO lesson_progress (user_id, lesson_id, completed_at) VALUES ($1, $2, $3)
           ON CONFLICT (user_id, lesson_id) DO NOTHING"#,
        user_id.0,
        lesson_id.0,
        now
    )
    .execute(executor)
    .await?;
    Ok(r.rows_affected() == 1)
}

pub async fn course_progress(
    executor: impl PgExecutor<'_>,
    user_id: UserId,
    course_id: CourseId,
) -> AppResult<CourseProgress> {
    let row = sqlx::query!(
        r#"SELECT
             count(l.id) AS "total!",
             count(p.lesson_id) AS "completed!"
           FROM lessons l
           LEFT JOIN lesson_progress p ON p.lesson_id = l.id AND p.user_id = $1
           WHERE l.course_id = $2"#,
        user_id.0,
        course_id.0
    )
    .fetch_one(executor)
    .await?;
    Ok(CourseProgress { course_id, completed_lessons: row.completed as u32, total_lessons: row.total as u32 })
}

pub async fn completed_lesson_ids(
    executor: impl PgExecutor<'_>,
    user_id: UserId,
    course_id: CourseId,
) -> AppResult<Vec<LessonId>> {
    let ids = sqlx::query_scalar!(
        r#"SELECT p.lesson_id FROM lesson_progress p JOIN lessons l ON l.id = p.lesson_id
           WHERE p.user_id = $1 AND l.course_id = $2"#,
        user_id.0,
        course_id.0
    )
    .fetch_all(executor)
    .await?;
    Ok(ids.into_iter().map(LessonId).collect())
}

pub async fn insert_certificate(executor: impl PgExecutor<'_>, cert: &Certificate) -> AppResult<bool> {
    let r = sqlx::query!(
        r#"INSERT INTO certificates (user_id, course_id, code, issued_at) VALUES ($1, $2, $3, $4)
           ON CONFLICT (user_id, course_id) DO NOTHING"#,
        cert.user_id.0,
        cert.course_id.0,
        cert.code,
        cert.issued_at
    )
    .execute(executor)
    .await?;
    Ok(r.rows_affected() == 1)
}

pub async fn find_certificate(
    executor: impl PgExecutor<'_>,
    user_id: UserId,
    course_id: CourseId,
) -> AppResult<Option<Certificate>> {
    let row = sqlx::query!(
        "SELECT user_id, course_id, code, issued_at FROM certificates WHERE user_id = $1 AND course_id = $2",
        user_id.0,
        course_id.0
    )
    .fetch_optional(executor)
    .await?;
    Ok(row.map(|r| Certificate {
        user_id: UserId(r.user_id),
        course_id: CourseId(r.course_id),
        code: r.code,
        issued_at: r.issued_at,
    }))
}

pub async fn find_certificate_by_code(executor: impl PgExecutor<'_>, code: &str) -> AppResult<Option<Certificate>> {
    let row = sqlx::query!("SELECT user_id, course_id, code, issued_at FROM certificates WHERE code = $1", code)
        .fetch_optional(executor)
        .await?;
    Ok(row.map(|r| Certificate {
        user_id: UserId(r.user_id),
        course_id: CourseId(r.course_id),
        code: r.code,
        issued_at: r.issued_at,
    }))
}
