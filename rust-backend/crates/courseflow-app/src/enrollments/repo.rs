use courseflow_core::enrollments::{Enrollment, EnrollmentSource};
use courseflow_core::ids::{CourseId, EnrollmentId, UserId};
use sqlx::PgExecutor;
use sqlx::types::Json;

use crate::errors::{AppError, AppResult};

pub async fn insert(executor: impl PgExecutor<'_>, e: &Enrollment) -> AppResult<()> {
    sqlx::query!(
        r#"INSERT INTO enrollments (id, user_id, course_id, source, created_at) VALUES ($1, $2, $3, $4, $5)"#,
        e.id.0,
        e.user_id.0,
        e.course_id.0,
        Json(&e.source) as _,
        e.created_at
    )
    .execute(executor)
    .await
    .map_err(|err| match &err {
        sqlx::Error::Database(db) if db.is_unique_violation() => AppError::conflict("already enrolled"),
        _ => AppError::from(err),
    })?;
    Ok(())
}

/// Idempotent variant for the billing webhook path: a duplicate delivery
/// must not fail on the UNIQUE (user_id, course_id) constraint.
pub async fn insert_if_absent(executor: impl PgExecutor<'_>, e: &Enrollment) -> AppResult<bool> {
    let r = sqlx::query!(
        r#"INSERT INTO enrollments (id, user_id, course_id, source, created_at) VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (user_id, course_id) DO NOTHING"#,
        e.id.0,
        e.user_id.0,
        e.course_id.0,
        Json(&e.source) as _,
        e.created_at
    )
    .execute(executor)
    .await?;
    Ok(r.rows_affected() == 1)
}

pub async fn exists(executor: impl PgExecutor<'_>, user_id: UserId, course_id: CourseId) -> AppResult<bool> {
    let found = sqlx::query_scalar!(
        r#"SELECT EXISTS(SELECT 1 FROM enrollments WHERE user_id = $1 AND course_id = $2) AS "exists!""#,
        user_id.0,
        course_id.0
    )
    .fetch_one(executor)
    .await?;
    Ok(found)
}

pub async fn list_for_user(executor: impl PgExecutor<'_>, user_id: UserId) -> AppResult<Vec<Enrollment>> {
    let rows = sqlx::query!(
        r#"SELECT id, user_id, course_id, source AS "source: Json<EnrollmentSource>", created_at
           FROM enrollments WHERE user_id = $1 ORDER BY created_at DESC"#,
        user_id.0
    )
    .fetch_all(executor)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| Enrollment {
            id: EnrollmentId(r.id),
            user_id: UserId(r.user_id),
            course_id: CourseId(r.course_id),
            source: r.source.0,
            created_at: r.created_at,
        })
        .collect())
}

pub async fn student_ids_for_course(executor: impl PgExecutor<'_>, course_id: CourseId) -> AppResult<Vec<UserId>> {
    let ids = sqlx::query_scalar!("SELECT user_id FROM enrollments WHERE course_id = $1", course_id.0)
        .fetch_all(executor)
        .await?;
    Ok(ids.into_iter().map(UserId).collect())
}
