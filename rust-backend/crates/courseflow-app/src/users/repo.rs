//! Users persistence: plain functions over an executor, no trait ceremony.
//! Callers decide whether `executor` is the pool or an open transaction.

use chrono::{DateTime, Utc};
use courseflow_core::ids::UserId;
use courseflow_core::users::{Email, PasswordHash, Role, User};
use sqlx::PgExecutor;
use uuid::Uuid;

use crate::errors::{AppError, AppResult};

/// Raw row: exactly what PostgreSQL returns. Converting it into the domain
/// `User` is where text becomes `Role` and a string becomes `Email`.
#[derive(Debug, sqlx::FromRow)]
struct UserRow {
    id: Uuid,
    email: String,
    display_name: String,
    password_hash: String,
    role: String,
    email_verified_at: Option<DateTime<Utc>>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

impl TryFrom<UserRow> for User {
    type Error = AppError;

    fn try_from(row: UserRow) -> Result<Self, Self::Error> {
        Ok(User {
            id: UserId(row.id),
            email: Email::parse(&row.email)?,
            display_name: row.display_name,
            password_hash: PasswordHash::from_phc(row.password_hash),
            role: row.role.parse::<Role>()?,
            email_verified_at: row.email_verified_at,
            created_at: row.created_at,
            updated_at: row.updated_at,
        })
    }
}

pub async fn insert(executor: impl PgExecutor<'_>, user: &User) -> AppResult<()> {
    sqlx::query!(
        r#"
        INSERT INTO users (id, email, display_name, password_hash, role, email_verified_at, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        "#,
        user.id.0,
        user.email.as_str(),
        user.display_name,
        user.password_hash.as_phc(),
        user.role.as_str(),
        user.email_verified_at,
        user.created_at,
        user.updated_at,
    )
    .execute(executor)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.is_unique_violation() => AppError::conflict("email already registered"),
        _ => AppError::from(e),
    })?;
    Ok(())
}

pub async fn find_by_id(executor: impl PgExecutor<'_>, id: UserId) -> AppResult<Option<User>> {
    let row = sqlx::query_as!(
        UserRow,
        r#"SELECT id, email, display_name, password_hash, role, email_verified_at, created_at, updated_at
           FROM users WHERE id = $1"#,
        id.0
    )
    .fetch_optional(executor)
    .await?;
    row.map(User::try_from).transpose()
}

pub async fn find_by_email(executor: impl PgExecutor<'_>, email: &Email) -> AppResult<Option<User>> {
    let row = sqlx::query_as!(
        UserRow,
        r#"SELECT id, email, display_name, password_hash, role, email_verified_at, created_at, updated_at
           FROM users WHERE email = $1"#,
        email.as_str()
    )
    .fetch_optional(executor)
    .await?;
    row.map(User::try_from).transpose()
}

pub async fn update(executor: impl PgExecutor<'_>, user: &User) -> AppResult<()> {
    let result = sqlx::query!(
        r#"UPDATE users
           SET display_name = $2, password_hash = $3, role = $4, email_verified_at = $5, updated_at = $6
           WHERE id = $1"#,
        user.id.0,
        user.display_name,
        user.password_hash.as_phc(),
        user.role.as_str(),
        user.email_verified_at,
        user.updated_at,
    )
    .execute(executor)
    .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::not_found("user"));
    }
    Ok(())
}

pub async fn count(executor: impl PgExecutor<'_>) -> AppResult<i64> {
    let n = sqlx::query_scalar!(r#"SELECT count(*) AS "count!" FROM users"#).fetch_one(executor).await?;
    Ok(n)
}
