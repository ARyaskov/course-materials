use chrono::{DateTime, Utc};
use courseflow_core::ids::{NotificationId, UserId};
use courseflow_core::notifications::{Notification, NotificationEvent};
use sqlx::PgExecutor;
use sqlx::types::Json;

use crate::errors::AppResult;

pub async fn insert(executor: impl PgExecutor<'_>, n: &Notification) -> AppResult<()> {
    sqlx::query!(
        "INSERT INTO notifications (id, user_id, event, created_at) VALUES ($1, $2, $3, $4)",
        n.id.0,
        n.user_id.0,
        Json(&n.event) as _,
        n.created_at
    )
    .execute(executor)
    .await?;
    Ok(())
}

/// Idempotent insert for at-least-once consumers: `false` means this
/// notification (same id) was already stored by an earlier attempt.
pub async fn insert_if_absent(executor: impl PgExecutor<'_>, n: &Notification) -> AppResult<bool> {
    let r = sqlx::query!(
        "INSERT INTO notifications (id, user_id, event, created_at) VALUES ($1, $2, $3, $4) ON CONFLICT (id) DO NOTHING",
        n.id.0,
        n.user_id.0,
        Json(&n.event) as _,
        n.created_at
    )
    .execute(executor)
    .await?;
    Ok(r.rows_affected() == 1)
}

pub async fn list_recent(executor: impl PgExecutor<'_>, user_id: UserId, limit: i64) -> AppResult<Vec<Notification>> {
    let rows = sqlx::query!(
        r#"SELECT id, user_id, event AS "event: Json<NotificationEvent>", created_at, read_at
           FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2"#,
        user_id.0,
        limit
    )
    .fetch_all(executor)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| Notification {
            id: NotificationId(r.id),
            user_id: UserId(r.user_id),
            event: r.event.0,
            created_at: r.created_at,
            read_at: r.read_at,
        })
        .collect())
}

pub async fn mark_read(
    executor: impl PgExecutor<'_>,
    user_id: UserId,
    id: NotificationId,
    now: DateTime<Utc>,
) -> AppResult<bool> {
    let r = sqlx::query!(
        "UPDATE notifications SET read_at = $3 WHERE id = $1 AND user_id = $2 AND read_at IS NULL",
        id.0,
        user_id.0,
        now
    )
    .execute(executor)
    .await?;
    Ok(r.rows_affected() == 1)
}

pub async fn unread_count(executor: impl PgExecutor<'_>, user_id: UserId) -> AppResult<i64> {
    let n = sqlx::query_scalar!(
        r#"SELECT count(*) AS "count!" FROM notifications WHERE user_id = $1 AND read_at IS NULL"#,
        user_id.0
    )
    .fetch_one(executor)
    .await?;
    Ok(n)
}
