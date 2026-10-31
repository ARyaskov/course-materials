use chrono::{DateTime, Duration, Utc};
use courseflow_core::ids::OutboxEventId;
use sqlx::PgExecutor;
use sqlx::types::Json;

use crate::errors::AppResult;
use crate::outbox::OutboxPayload;

#[derive(Debug, Clone)]
pub struct OutboxRow {
    pub id: OutboxEventId,
    pub event_type: String,
    pub payload: OutboxPayload,
    pub attempts: i32,
}

pub async fn enqueue(
    executor: impl PgExecutor<'_>,
    payload: &OutboxPayload,
    now: DateTime<Utc>,
) -> AppResult<OutboxEventId> {
    let id = OutboxEventId::new();
    sqlx::query!(
        r#"INSERT INTO outbox_events (id, event_type, payload, next_attempt_at, created_at)
           VALUES ($1, $2, $3, $4, $4)"#,
        id.0,
        payload.event_type(),
        Json(payload) as _,
        now
    )
    .execute(executor)
    .await?;
    Ok(id)
}

/// Claims up to `batch` due events for `lease`. Other workers skip locked
/// rows, so several relay processes can run side by side.
pub async fn claim_batch(
    executor: impl PgExecutor<'_>,
    batch: i64,
    lease: Duration,
    now: DateTime<Utc>,
) -> AppResult<Vec<OutboxRow>> {
    let lease_secs = lease.num_milliseconds() as f64 / 1000.0;
    let rows = sqlx::query!(
        r#"
        WITH due AS (
            SELECT id FROM outbox_events
            WHERE status IN ('pending', 'processing')
              AND next_attempt_at <= $3
              AND (locked_until IS NULL OR locked_until < $3)
            ORDER BY next_attempt_at
            LIMIT $1
            FOR UPDATE SKIP LOCKED
        )
        UPDATE outbox_events o
        SET status = 'processing', locked_until = $3::timestamptz + make_interval(secs => $2), attempts = o.attempts + 1
        FROM due
        WHERE o.id = due.id
        RETURNING o.id, o.event_type, o.payload AS "payload: Json<OutboxPayload>", o.attempts
        "#,
        batch,
        lease_secs,
        now
    )
    .fetch_all(executor)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| OutboxRow {
            id: OutboxEventId(r.id),
            event_type: r.event_type,
            payload: r.payload.0,
            attempts: r.attempts,
        })
        .collect())
}

pub async fn mark_done(executor: impl PgExecutor<'_>, id: OutboxEventId, now: DateTime<Utc>) -> AppResult<()> {
    sqlx::query!(
        "UPDATE outbox_events SET status = 'done', processed_at = $2, locked_until = NULL, last_error = NULL WHERE id = $1",
        id.0,
        now
    )
    .execute(executor)
    .await?;
    Ok(())
}

/// Exponential backoff with a cap; after `max_attempts` the row is parked as
/// `dead` and shows up in metrics instead of being retried forever.
pub async fn mark_failed(
    executor: impl PgExecutor<'_>,
    id: OutboxEventId,
    attempts: i32,
    max_attempts: i32,
    error: &str,
    now: DateTime<Utc>,
) -> AppResult<bool> {
    let dead = attempts >= max_attempts;
    let backoff_secs = 2i64.saturating_pow(attempts.clamp(0, 10) as u32).min(600);
    sqlx::query!(
        r#"UPDATE outbox_events
           SET status = CASE WHEN $2 THEN 'dead' ELSE 'pending' END,
               next_attempt_at = $3::timestamptz + make_interval(secs => $4),
               locked_until = NULL,
               last_error = left($5, 2000)
           WHERE id = $1"#,
        id.0,
        dead,
        now,
        backoff_secs as f64,
        error
    )
    .execute(executor)
    .await?;
    Ok(dead)
}

/// A worker that died mid-batch leaves rows `processing` with an expired
/// lease; they become claimable again automatically, this only keeps the
/// status column honest for dashboards.
pub async fn requeue_expired_locks(executor: impl PgExecutor<'_>, now: DateTime<Utc>) -> AppResult<u64> {
    let r = sqlx::query!(
        "UPDATE outbox_events SET status = 'pending', locked_until = NULL WHERE status = 'processing' AND locked_until < $1",
        now
    )
    .execute(executor)
    .await?;
    Ok(r.rows_affected())
}

pub async fn delete_done(executor: impl PgExecutor<'_>, older_than: DateTime<Utc>) -> AppResult<u64> {
    let r = sqlx::query!("DELETE FROM outbox_events WHERE status = 'done' AND processed_at < $1", older_than)
        .execute(executor)
        .await?;
    Ok(r.rows_affected())
}

pub async fn pending_count(executor: impl PgExecutor<'_>) -> AppResult<(i64, i64)> {
    let row = sqlx::query!(
        r#"SELECT
             count(*) FILTER (WHERE status IN ('pending', 'processing')) AS "pending!",
             count(*) FILTER (WHERE status = 'dead') AS "dead!"
           FROM outbox_events"#
    )
    .fetch_one(executor)
    .await?;
    Ok((row.pending, row.dead))
}
