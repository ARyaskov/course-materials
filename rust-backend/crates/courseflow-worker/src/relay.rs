//! Outbox relay: claim a batch, handle each row, record the outcome.

use std::time::Duration;

use chrono::Utc;
use courseflow_app::config::WorkerConfig;
use courseflow_app::outbox;
use sqlx::PgPool;
use tokio_util::sync::CancellationToken;

use crate::handlers::Handlers;

#[derive(Debug, Clone)]
pub struct Relay {
    pool: PgPool,
    handlers: Handlers,
    batch_size: i64,
    max_attempts: i32,
    lease: chrono::Duration,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct Tick {
    pub claimed: usize,
    pub done: usize,
    pub failed: usize,
    pub dead: usize,
}

impl Relay {
    pub fn new(pool: PgPool, handlers: Handlers, config: &WorkerConfig) -> Self {
        Self {
            pool,
            handlers,
            batch_size: config.outbox_batch_size,
            max_attempts: config.outbox_max_attempts,
            lease: chrono::Duration::seconds(60),
        }
    }

    /// Direct access for tests that exercise a single handler (e.g. the
    /// at-least-once replay of one event) without going through `tick`.
    pub fn handlers(&self) -> &Handlers {
        &self.handlers
    }

    /// One iteration. Public so tests can call it directly instead of
    /// sleeping and hoping the loop ran.
    #[tracing::instrument(skip(self))]
    pub async fn tick(&self) -> Result<Tick, courseflow_app::AppError> {
        let now = Utc::now();
        let rows = outbox::claim_batch(&self.pool, self.batch_size, self.lease, now).await?;
        let mut tick = Tick { claimed: rows.len(), ..Tick::default() };
        for row in rows {
            let started = std::time::Instant::now();
            match self.handlers.handle(row.id.0, row.payload.clone()).await {
                Ok(()) => {
                    outbox::mark_done(&self.pool, row.id, Utc::now()).await?;
                    tick.done += 1;
                    metrics::counter!("courseflow_outbox_events_total", "outcome" => "done", "type" => row.event_type.clone()).increment(1);
                }
                Err(err) => {
                    let dead = outbox::mark_failed(
                        &self.pool,
                        row.id,
                        row.attempts,
                        self.max_attempts,
                        &err.to_string(),
                        Utc::now(),
                    )
                    .await?;
                    if dead {
                        tick.dead += 1;
                        tracing::error!(event_id = %row.id, attempts = row.attempts, error = %err, "outbox event moved to dead-letter");
                    } else {
                        tick.failed += 1;
                        tracing::warn!(event_id = %row.id, attempts = row.attempts, error = %err, "outbox event failed, will retry");
                    }
                    metrics::counter!("courseflow_outbox_events_total", "outcome" => if dead { "dead" } else { "failed" }, "type" => row.event_type.clone()).increment(1);
                }
            }
            metrics::histogram!("courseflow_outbox_handle_seconds", "type" => row.event_type)
                .record(started.elapsed().as_secs_f64());
        }
        if let Ok((pending, dead)) = outbox::pending_count(&self.pool).await {
            metrics::gauge!("courseflow_outbox_pending").set(pending as f64);
            metrics::gauge!("courseflow_outbox_dead").set(dead as f64);
        }
        Ok(tick)
    }

    /// The loop: poll while idle, drain immediately while there is work,
    /// stop at the next safe point when cancelled. A row claimed at the
    /// moment of shutdown is finished, not abandoned.
    pub async fn run(self, poll_interval: Duration, cancel: CancellationToken) {
        tracing::info!(?poll_interval, batch = self.batch_size, "outbox relay started");
        loop {
            if cancel.is_cancelled() {
                break;
            }
            let idle = match self.tick().await {
                Ok(tick) if tick.claimed > 0 => {
                    tracing::debug!(?tick, "outbox batch processed");
                    false
                }
                Ok(_) => true,
                Err(err) => {
                    tracing::error!(error = %err, "outbox tick failed");
                    true
                }
            };
            if idle {
                tokio::select! {
                    _ = cancel.cancelled() => break,
                    _ = tokio::time::sleep(poll_interval) => {}
                }
            }
        }
        tracing::info!("outbox relay stopped");
    }
}
