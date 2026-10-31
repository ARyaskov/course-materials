#![cfg_attr(test, allow(clippy::unwrap_used, clippy::expect_used))]
//! CourseFlow HTTP API. `main.rs` only wires configuration, telemetry and
//! shutdown; everything testable lives here so integration tests can build
//! the router without binding a port.

pub mod app;
pub mod features;
pub mod http;
pub mod state;

pub use app::{build_router, build_state};
pub use state::AppState;
