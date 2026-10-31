//! Housekeeping on a timer. Each job takes a PostgreSQL advisory lock so that
//! running two worker replicas does not double the work.

use std::time::Duration;

use chrono::Utc;
use courseflow_app::auth::refresh;
use courseflow_app::outbox;
use sqlx::PgPool;
use tokio_util::sync::CancellationToken;

const LOCK_CLEANUP: i64 = 7_401_001;

pub async fn run_cleanup(pool: PgPool, every: Duration, cancel: CancellationToken) {
    let mut interval = tokio::time::interval(every);
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        tokio::select! {
            _ = cancel.cancelled() => break,
            _ = interval.tick() => {
                if let Err(err) = cleanup_once(&pool).await {
                    tracing::warn!(error = %err, "cleanup iteration failed");
                }
            }
        }
    }
    tracing::info!("cleanup job stopped");
}

#[tracing::instrument(skip_all)]
pub async fn cleanup_once(pool: &PgPool) -> Result<(), courseflow_app::AppError> {
    let mut conn = pool.acquire().await?;
    let locked: bool = sqlx::query_scalar!(r#"SELECT pg_try_advisory_lock($1) AS "locked!""#, LOCK_CLEANUP)
        .fetch_one(&mut *conn)
        .await?;
    if !locked {
        tracing::debug!("another worker holds the cleanup lock, skipping");
        return Ok(());
    }
    let now = Utc::now();
    let result = async {
        let tokens = refresh::delete_stale(&mut *conn, now).await?;
        let requeued = outbox::requeue_expired_locks(&mut *conn, now).await?;
        let purged = outbox::delete_done(&mut *conn, now - chrono::Duration::days(7)).await?;
        tracing::info!(tokens, requeued, purged, "cleanup done");
        Ok::<_, courseflow_app::AppError>(())
    }
    .await;
    // Release even if the body failed; the session-level lock would
    // otherwise follow the pooled connection.
    let _ = sqlx::query_scalar!(r#"SELECT pg_advisory_unlock($1) AS "unlocked!""#, LOCK_CLEANUP)
        .fetch_one(&mut *conn)
        .await;
    result
}
