//! The relay is driven one tick at a time: no sleeping, no polling loop.

#![allow(clippy::unwrap_used)]

use std::sync::Arc;

use chrono::Utc;
use courseflow_app::config::Config;
use courseflow_app::notifications::{NotificationBus, NotificationService};
use courseflow_app::outbox::{self, OutboxPayload};
use courseflow_core::ids::UserId;
use courseflow_core::notifications::NotificationEvent;
use courseflow_core::ports::SystemClock;
use courseflow_core::users::{Email, PasswordHash, User};
use courseflow_worker::handlers::Handlers;
use courseflow_worker::relay::Relay;
use sqlx::PgPool;

async fn user(pool: &PgPool) -> UserId {
    let u = User::register(Email::parse("w@example.com").unwrap(), "W", PasswordHash::from_phc("x".into()), Utc::now())
        .unwrap();
    courseflow_app::users::repo::insert(pool, &u).await.unwrap();
    u.id
}

fn relay(pool: &PgPool) -> (Relay, NotificationService) {
    let bus = NotificationBus::new(None);
    let notifications = NotificationService::new(pool.clone(), bus, Arc::new(SystemClock));
    let handlers = Handlers { pool: pool.clone(), notifications: Arc::new(notifications.clone()) };
    (Relay::new(pool.clone(), handlers, &Config::for_tests("x").worker), notifications)
}

#[sqlx::test(migrations = "../../migrations")]
async fn notify_event_becomes_a_notification_and_a_bus_message(pool: PgPool) {
    let user_id = user(&pool).await;
    let (relay, notifications) = relay(&pool);
    let mut rx = notifications.bus().subscribe_local();

    outbox::enqueue(
        &pool,
        &OutboxPayload::Notify { user_id, event: NotificationEvent::Welcome { display_name: "W".into() } },
        Utc::now(),
    )
    .await
    .unwrap();

    let tick = relay.tick().await.unwrap();
    assert_eq!((tick.claimed, tick.done, tick.failed), (1, 1, 0));

    let stored = notifications.list_recent(user_id, 10).await.unwrap();
    assert_eq!(stored.len(), 1);
    let wire = rx.try_recv().unwrap();
    assert_eq!(wire.user_id, user_id);
    assert_eq!(wire.event.kind(), "welcome");

    // nothing left; a second tick is a no-op
    assert_eq!(relay.tick().await.unwrap().claimed, 0);
    let (pending, dead) = outbox::pending_count(&pool).await.unwrap();
    assert_eq!((pending, dead), (0, 0));
}

#[sqlx::test(migrations = "../../migrations")]
async fn failing_event_is_retried_with_backoff_then_parked(pool: PgPool) {
    let (relay, _) = relay(&pool);
    // A notification for a user that does not exist violates the FK: the
    // handler fails deterministically.
    let ghost = UserId::new();
    let id = outbox::enqueue(
        &pool,
        &OutboxPayload::Notify { user_id: ghost, event: NotificationEvent::Welcome { display_name: "?".into() } },
        Utc::now(),
    )
    .await
    .unwrap();

    let tick = relay.tick().await.unwrap();
    assert_eq!((tick.claimed, tick.failed, tick.dead), (1, 1, 0));
    // backoff: not due yet, so the next tick claims nothing
    assert_eq!(relay.tick().await.unwrap().claimed, 0);

    // fast-forward by resetting next_attempt_at; max_attempts is 3 in tests
    for expected_dead in [0, 1] {
        sqlx::query("UPDATE outbox_events SET next_attempt_at = now() WHERE id = $1")
            .bind(id.0)
            .execute(&pool)
            .await
            .unwrap();
        let tick = relay.tick().await.unwrap();
        assert_eq!(tick.claimed, 1);
        assert_eq!(tick.dead, expected_dead);
    }
    let (pending, dead) = outbox::pending_count(&pool).await.unwrap();
    assert_eq!((pending, dead), (0, 1));
}

#[sqlx::test(migrations = "../../migrations")]
async fn cleanup_runs_under_advisory_lock(pool: PgPool) {
    courseflow_worker::periodic::cleanup_once(&pool).await.unwrap();
}
