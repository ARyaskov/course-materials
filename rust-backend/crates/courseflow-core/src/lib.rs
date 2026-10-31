#![cfg_attr(test, allow(clippy::unwrap_used, clippy::expect_used))]
//! CourseFlow domain layer.
//!
//! No I/O, no HTTP, no SQL: only types, invariants, state transitions and the
//! ports (traits) that the application layer uses to talk to the outside world.

pub mod billing;
pub mod courses;
pub mod enrollments;
pub mod errors;
pub mod ids;
pub mod lessons;
pub mod money;
pub mod notifications;
pub mod policy;
pub mod ports;
pub mod progress;
pub mod users;

pub use errors::DomainError;
pub use ids::*;
pub use money::{Currency, Money};
