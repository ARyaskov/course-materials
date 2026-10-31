//! Closed → Open → HalfOpen circuit breaker. State lives in the process:
//! every API instance protects itself; that is enough for a monolith.

use std::sync::Mutex;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BreakerState {
    Closed,
    Open,
    HalfOpen,
}

#[derive(Debug)]
struct Inner {
    state: BreakerState,
    consecutive_failures: u32,
    opened_at: Option<Instant>,
}

#[derive(Debug)]
pub struct CircuitBreaker {
    name: &'static str,
    failure_threshold: u32,
    open_for: Duration,
    inner: Mutex<Inner>,
}

impl CircuitBreaker {
    pub fn new(name: &'static str, failure_threshold: u32, open_for: Duration) -> Self {
        Self {
            name,
            failure_threshold,
            open_for,
            inner: Mutex::new(Inner { state: BreakerState::Closed, consecutive_failures: 0, opened_at: None }),
        }
    }

    pub fn state(&self) -> BreakerState {
        self.lock().state
    }

    /// Returns `false` when the call must be rejected without trying.
    pub fn allow(&self) -> bool {
        let mut inner = self.lock();
        match inner.state {
            BreakerState::Closed => true,
            BreakerState::HalfOpen => true,
            BreakerState::Open => {
                let elapsed = inner.opened_at.map(|t| t.elapsed()).unwrap_or(Duration::MAX);
                if elapsed >= self.open_for {
                    inner.state = BreakerState::HalfOpen;
                    tracing::info!(breaker = self.name, "circuit half-open, probing");
                    true
                } else {
                    false
                }
            }
        }
    }

    pub fn record_success(&self) {
        let mut inner = self.lock();
        if inner.state != BreakerState::Closed {
            tracing::info!(breaker = self.name, "circuit closed");
        }
        inner.state = BreakerState::Closed;
        inner.consecutive_failures = 0;
        inner.opened_at = None;
        metrics::gauge!("courseflow_circuit_open", "breaker" => self.name).set(0.0);
    }

    pub fn record_failure(&self) {
        let mut inner = self.lock();
        inner.consecutive_failures += 1;
        if inner.state == BreakerState::HalfOpen || inner.consecutive_failures >= self.failure_threshold {
            if inner.state != BreakerState::Open {
                tracing::warn!(breaker = self.name, failures = inner.consecutive_failures, "circuit opened");
            }
            inner.state = BreakerState::Open;
            inner.opened_at = Some(Instant::now());
            metrics::gauge!("courseflow_circuit_open", "breaker" => self.name).set(1.0);
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        // A poisoned lock only means a panic elsewhere; the state is still consistent.
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opens_after_threshold_and_probes_later() {
        let b = CircuitBreaker::new("test", 2, Duration::from_millis(10));
        assert!(b.allow());
        b.record_failure();
        assert_eq!(b.state(), BreakerState::Closed);
        b.record_failure();
        assert_eq!(b.state(), BreakerState::Open);
        assert!(!b.allow());
        std::thread::sleep(Duration::from_millis(15));
        assert!(b.allow());
        assert_eq!(b.state(), BreakerState::HalfOpen);
        b.record_success();
        assert_eq!(b.state(), BreakerState::Closed);
    }
}
