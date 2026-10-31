//! Refresh-token storage with rotation and reuse detection.
//!
//! Every successful refresh issues a new token in the same *family* and marks
//! the old one as replaced. If a replaced token shows up again, somebody has a
//! copy of it: the whole family is revoked.

use chrono::{DateTime, Utc};
use courseflow_core::ids::UserId;
use sqlx::PgExecutor;
use uuid::Uuid;

use crate::errors::{AppError, AppResult};

#[derive(Debug, Clone)]
pub struct RefreshTokenRecord {
    pub id: Uuid,
    pub user_id: UserId,
    pub family_id: Uuid,
    pub expires_at: DateTime<Utc>,
    pub revoked_at: Option<DateTime<Utc>>,
    pub replaced_by: Option<Uuid>,
}

impl RefreshTokenRecord {
    pub fn is_active(&self, now: DateTime<Utc>) -> bool {
        self.revoked_at.is_none() && self.replaced_by.is_none() && self.expires_at > now
    }
}

pub async fn insert(
    executor: impl PgExecutor<'_>,
    id: Uuid,
    user_id: UserId,
    family_id: Uuid,
    token_hash: &[u8],
    expires_at: DateTime<Utc>,
    now: DateTime<Utc>,
) -> AppResult<()> {
    sqlx::query!(
        r#"INSERT INTO refresh_tokens (id, user_id, family_id, token_hash, expires_at, created_at)
           VALUES ($1, $2, $3, $4, $5, $6)"#,
        id,
        user_id.0,
        family_id,
        token_hash,
        expires_at,
        now
    )
    .execute(executor)
    .await?;
    Ok(())
}

pub async fn find_by_hash(executor: impl PgExecutor<'_>, token_hash: &[u8]) -> AppResult<Option<RefreshTokenRecord>> {
    let row = sqlx::query!(
        r#"SELECT id, user_id, family_id, expires_at, revoked_at, replaced_by
           FROM refresh_tokens WHERE token_hash = $1"#,
        token_hash
    )
    .fetch_optional(executor)
    .await?;
    Ok(row.map(|r| RefreshTokenRecord {
        id: r.id,
        user_id: UserId(r.user_id),
        family_id: r.family_id,
        expires_at: r.expires_at,
        revoked_at: r.revoked_at,
        replaced_by: r.replaced_by,
    }))
}

pub async fn mark_replaced(executor: impl PgExecutor<'_>, id: Uuid, replaced_by: Uuid) -> AppResult<()> {
    sqlx::query!("UPDATE refresh_tokens SET replaced_by = $2 WHERE id = $1", id, replaced_by).execute(executor).await?;
    Ok(())
}

pub async fn revoke_family(executor: impl PgExecutor<'_>, family_id: Uuid, now: DateTime<Utc>) -> AppResult<u64> {
    let result = sqlx::query!(
        "UPDATE refresh_tokens SET revoked_at = $2 WHERE family_id = $1 AND revoked_at IS NULL",
        family_id,
        now
    )
    .execute(executor)
    .await?;
    Ok(result.rows_affected())
}

pub async fn revoke_all_for_user(executor: impl PgExecutor<'_>, user_id: UserId, now: DateTime<Utc>) -> AppResult<u64> {
    let result = sqlx::query!(
        "UPDATE refresh_tokens SET revoked_at = $2 WHERE user_id = $1 AND revoked_at IS NULL",
        user_id.0,
        now
    )
    .execute(executor)
    .await?;
    Ok(result.rows_affected())
}

/// Periodic cleanup: expired or revoked rows older than a day are useless.
pub async fn delete_stale(executor: impl PgExecutor<'_>, now: DateTime<Utc>) -> AppResult<u64> {
    let result = sqlx::query!(
        r#"DELETE FROM refresh_tokens
           WHERE expires_at < $1 OR (revoked_at IS NOT NULL AND revoked_at < $1 - interval '1 day')"#,
        now
    )
    .execute(executor)
    .await?;
    Ok(result.rows_affected())
}

/// One-time action tokens (password reset, e-mail verification).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActionPurpose {
    PasswordReset,
    EmailVerification,
}

impl ActionPurpose {
    pub fn as_str(self) -> &'static str {
        match self {
            ActionPurpose::PasswordReset => "password_reset",
            ActionPurpose::EmailVerification => "email_verification",
        }
    }
}

pub async fn insert_action_token(
    executor: impl PgExecutor<'_>,
    user_id: UserId,
    purpose: ActionPurpose,
    token_hash: &[u8],
    expires_at: DateTime<Utc>,
) -> AppResult<()> {
    sqlx::query!(
        r#"INSERT INTO action_tokens (id, user_id, purpose, token_hash, expires_at)
           VALUES ($1, $2, $3, $4, $5)"#,
        Uuid::now_v7(),
        user_id.0,
        purpose.as_str(),
        token_hash,
        expires_at
    )
    .execute(executor)
    .await?;
    Ok(())
}

/// Atomically consumes a valid token: `UPDATE ... WHERE used_at IS NULL` is
/// the single-use guarantee even under concurrent requests.
pub async fn consume_action_token(
    executor: impl PgExecutor<'_>,
    purpose: ActionPurpose,
    token_hash: &[u8],
    now: DateTime<Utc>,
) -> AppResult<Option<UserId>> {
    let row = sqlx::query!(
        r#"UPDATE action_tokens SET used_at = $3
           WHERE token_hash = $1 AND purpose = $2 AND used_at IS NULL AND expires_at > $3
           RETURNING user_id"#,
        token_hash,
        purpose.as_str(),
        now
    )
    .fetch_optional(executor)
    .await?;
    Ok(row.map(|r| UserId(r.user_id)))
}

pub fn map_conflict(err: sqlx::Error) -> AppError {
    match &err {
        sqlx::Error::Database(db) if db.is_unique_violation() => AppError::conflict("token collision"),
        _ => AppError::from(err),
    }
}
