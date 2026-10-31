use std::future::Future;
use std::time::Duration;

use rand::RngExt;

#[derive(Debug, Clone, Copy)]
pub struct RetryPolicy {
    pub max_attempts: u32,
    pub base_delay: Duration,
    pub max_delay: Duration,
}

impl RetryPolicy {
    pub fn new(max_attempts: u32) -> Self {
        Self { max_attempts, base_delay: Duration::from_millis(200), max_delay: Duration::from_secs(5) }
    }

    /// Exponential backoff with full jitter: `random(0, min(max, base * 2^n))`.
    pub fn delay_for(&self, attempt: u32) -> Duration {
        let exp = self.base_delay.saturating_mul(2u32.saturating_pow(attempt));
        let cap = exp.min(self.max_delay);
        let millis = cap.as_millis() as u64;
        if millis == 0 {
            return Duration::ZERO;
        }
        Duration::from_millis(rand::rng().random_range(0..=millis))
    }
}

/// Runs `op` until it succeeds, returns a non-retryable error, or the policy
/// is exhausted. `is_retryable` decides per error: 5xx and timeouts yes,
/// 4xx never.
pub async fn retry<T, E, F, Fut>(policy: RetryPolicy, is_retryable: impl Fn(&E) -> bool, mut op: F) -> Result<T, E>
where
    F: FnMut(u32) -> Fut,
    Fut: Future<Output = Result<T, E>>,
{
    let mut attempt = 0;
    loop {
        match op(attempt).await {
            Ok(v) => return Ok(v),
            Err(err) if attempt + 1 < policy.max_attempts && is_retryable(&err) => {
                let delay = policy.delay_for(attempt);
                tracing::debug!(attempt, ?delay, "retrying after error");
                tokio::time::sleep(delay).await;
                attempt += 1;
            }
            Err(err) => return Err(err),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};

    #[tokio::test]
    async fn retries_until_success() {
        let calls = AtomicU32::new(0);
        let policy =
            RetryPolicy { max_attempts: 5, base_delay: Duration::from_millis(1), max_delay: Duration::from_millis(2) };
        let result: Result<&str, &str> = retry(
            policy,
            |_| true,
            |_| {
                let n = calls.fetch_add(1, Ordering::SeqCst);
                async move { if n < 2 { Err("boom") } else { Ok("done") } }
            },
        )
        .await;
        assert_eq!(result, Ok("done"));
        assert_eq!(calls.load(Ordering::SeqCst), 3);
    }

    #[tokio::test]
    async fn non_retryable_stops_immediately() {
        let calls = AtomicU32::new(0);
        let policy = RetryPolicy::new(5);
        let result: Result<(), &str> = retry(
            policy,
            |e| *e != "fatal",
            |_| {
                calls.fetch_add(1, Ordering::SeqCst);
                async { Err("fatal") }
            },
        )
        .await;
        assert_eq!(result, Err("fatal"));
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }
}
