//! Redis behaviour is tested against a real server, never a fake: TTL and
//! atomicity are exactly what a fake gets wrong. The server comes from
//! `COURSEFLOW_TEST_REDIS_URL` (default `redis://127.0.0.1:6379/15`); when
//! nothing answers there, the test starts a throwaway container with
//! testcontainers and removes it at the end. Without Docker either, the test
//! is skipped with a message.

#![allow(clippy::unwrap_used)]

use std::time::Duration;

use courseflow_app::cache::idempotency::StoredResponse;
use courseflow_app::cache::{IdempotencyGuard, IdempotencyOutcome, RateLimitDecision, RateLimiter, RedisHandle};
use courseflow_app::config::RedisConfig;
use secrecy::SecretString;
use testcontainers::core::{IntoContainerPort, WaitFor};
use testcontainers::runners::AsyncRunner;
use testcontainers::{ContainerAsync, GenericImage};

/// A connected handle plus, when one had to be started, the container that
/// backs it. Keep the value alive for the whole test: dropping it removes
/// the container.
struct TestRedis {
    handle: RedisHandle,
    _container: Option<ContainerAsync<GenericImage>>,
}

async fn connect(url: String) -> Option<RedisHandle> {
    let config =
        RedisConfig { url: SecretString::from(url), key_prefix: format!("t{}", uuid::Uuid::now_v7().simple()) };
    let handle = courseflow_app::cache::connect(&config).await.ok()?;
    handle.ping().await.ok()?;
    Some(handle)
}

async fn redis() -> Option<TestRedis> {
    let url = std::env::var("COURSEFLOW_TEST_REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379/15".into());
    if let Some(handle) = connect(url).await {
        return Some(TestRedis { handle, _container: None });
    }
    let image = GenericImage::new("redis", "8-alpine")
        .with_exposed_port(6379.tcp())
        .with_wait_for(WaitFor::message_on_stdout("Ready to accept connections"));
    let container = match image.start().await {
        Ok(container) => container,
        Err(err) => {
            eprintln!("no redis and no docker ({err}); skipping");
            return None;
        }
    };
    let port = container.get_host_port_ipv4(6379).await.ok()?;
    let url = format!("redis://127.0.0.1:{port}/0");
    eprintln!("started throwaway redis at {url}");
    let handle = connect(url).await?;
    Some(TestRedis { handle, _container: Some(container) })
}

#[tokio::test]
async fn rate_limiter_counts_within_window() {
    let Some(redis) = redis().await else {
        eprintln!("redis not available, skipping");
        return;
    };
    let limiter = RateLimiter::new(Some(redis.handle.clone()), true);
    for _ in 0..3 {
        assert!(matches!(
            limiter.check("login", "1.2.3.4", 3, Duration::from_secs(60)).await,
            RateLimitDecision::Allowed { .. }
        ));
    }
    match limiter.check("login", "1.2.3.4", 3, Duration::from_secs(60)).await {
        RateLimitDecision::Limited { retry_after_secs } => assert!((1..=60).contains(&retry_after_secs)),
        other => panic!("expected limit, got {other:?}"),
    }
    // another subject has its own window
    assert!(matches!(
        limiter.check("login", "5.6.7.8", 3, Duration::from_secs(60)).await,
        RateLimitDecision::Allowed { .. }
    ));
}

#[tokio::test]
async fn idempotency_guard_replays_and_detects_mismatch() {
    let Some(redis) = redis().await else {
        eprintln!("redis not available, skipping");
        return;
    };
    let guard = IdempotencyGuard::new(Some(redis.handle.clone()), Duration::from_secs(60));
    let hash = IdempotencyGuard::hash_request(b"course-1");

    assert_eq!(guard.begin("u1", "checkout", "k1", &hash).await.unwrap(), IdempotencyOutcome::Proceed);
    assert_eq!(guard.begin("u1", "checkout", "k1", &hash).await.unwrap(), IdempotencyOutcome::InProgress);
    let other = IdempotencyGuard::hash_request(b"course-2");
    assert_eq!(guard.begin("u1", "checkout", "k1", &other).await.unwrap(), IdempotencyOutcome::Mismatch);

    let stored = StoredResponse { status: 201, body: "{}".into(), request_hash: hash.clone() };
    guard.finish("u1", "checkout", "k1", stored.clone()).await.unwrap();
    assert_eq!(guard.begin("u1", "checkout", "k1", &hash).await.unwrap(), IdempotencyOutcome::Replay(stored));

    // a different user with the same client key is unrelated
    assert_eq!(guard.begin("u2", "checkout", "k1", &hash).await.unwrap(), IdempotencyOutcome::Proceed);
}

#[tokio::test]
async fn idempotency_without_redis_fails_closed() {
    let guard = IdempotencyGuard::disabled();
    assert!(matches!(guard.begin("u", "r", "k", "h").await, Err(courseflow_app::AppError::Unavailable(_))));
}

#[tokio::test]
async fn rate_limiter_without_redis_fails_open() {
    let limiter = RateLimiter::disabled();
    assert!(matches!(limiter.check("login", "x", 1, Duration::from_secs(1)).await, RateLimitDecision::Allowed { .. }));
}
