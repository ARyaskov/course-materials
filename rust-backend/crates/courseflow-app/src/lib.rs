#![cfg_attr(test, allow(clippy::unwrap_used, clippy::expect_used))]
//! CourseFlow application layer.
//!
//! Use cases (one module per feature) plus the adapters they need: PostgreSQL
//! through SQLx, Redis, the billing HTTP client, password hashing, JWT,
//! the transactional outbox and telemetry. HTTP never leaks in here; the
//! `courseflow-api` and `courseflow-worker` binaries are thin shells on top.

pub mod auth;
pub mod billing;
pub mod cache;
pub mod config;
pub mod courses;
pub mod db;
pub mod enrollments;
pub mod errors;
pub mod lessons;
pub mod notifications;
pub mod outbox;
pub mod progress;
pub mod resilience;
pub mod shared;
pub mod telemetry;
pub mod users;

pub use config::Config;
pub use errors::AppError;
