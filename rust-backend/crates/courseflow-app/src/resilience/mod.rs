//! Patterns for talking to unreliable dependencies: retry with backoff and a
//! circuit breaker. Both are small, explicit and testable without a network.

pub mod breaker;
pub mod retry;

pub use breaker::{BreakerState, CircuitBreaker};
pub use retry::{RetryPolicy, retry};
