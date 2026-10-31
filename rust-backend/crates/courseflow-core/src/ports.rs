//! Ports: the domain's view of the outside world. Only effects that need a
//! test double live here; persistence stays explicit in the application layer.
//!
//! The async traits return a boxed future so that they are dyn-compatible:
//! `Arc<dyn BillingClient>` can be stored in application state and swapped
//! for a fake in tests. Native `async fn` in traits (Rust 1.75+) would tie the
//! caller to a concrete type through generics; both styles are legitimate,
//! this one keeps `AppState` monomorphic.

use std::future::Future;
use std::pin::Pin;

use chrono::{DateTime, Utc};

use crate::billing::{PaymentCreated, PaymentRequest};
use crate::users::PasswordHash;

pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Time is an input, not a global: use cases receive `now` from a `Clock`, so
/// tests can freeze it.
pub trait Clock: Send + Sync + 'static {
    fn now(&self) -> DateTime<Utc>;
}

#[derive(Debug, Clone, Copy, Default)]
pub struct SystemClock;

impl Clock for SystemClock {
    fn now(&self) -> DateTime<Utc> {
        Utc::now()
    }
}

#[derive(Debug, thiserror::Error)]
pub enum BillingError {
    #[error("billing provider unavailable: {0}")]
    Unavailable(String),
    #[error("billing provider rejected the request: {0}")]
    Rejected(String),
    #[error("billing provider timed out")]
    Timeout,
    #[error("billing circuit is open, retry later")]
    CircuitOpen,
}

/// Outbound payments.
pub trait BillingClient: Send + Sync + 'static {
    fn create_payment(&self, request: PaymentRequest) -> BoxFuture<'_, Result<PaymentCreated, BillingError>>;
}

#[derive(Debug, thiserror::Error)]
#[error("password hashing failed: {0}")]
pub struct HashError(pub String);

/// Argon2 in production, a cheap fake in tests. Hashing is CPU-bound, so the
/// implementation is expected to run it on a blocking thread.
pub trait PasswordHasher: Send + Sync + 'static {
    fn hash<'a>(&'a self, password: &'a str) -> BoxFuture<'a, Result<PasswordHash, HashError>>;
    fn verify<'a>(&'a self, password: &'a str, hash: &'a PasswordHash) -> BoxFuture<'a, Result<bool, HashError>>;
    /// Whether a stored hash was produced with weaker parameters than the
    /// current ones; the service re-hashes on the next successful login.
    fn needs_rehash(&self, _hash: &PasswordHash) -> bool {
        false
    }
}
