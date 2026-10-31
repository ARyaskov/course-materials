#![cfg_attr(test, allow(clippy::unwrap_used, clippy::expect_used))]
//! Worker library: the relay loop and handlers are here so that integration
//! tests can drive one iteration at a time without spawning the binary.

pub mod handlers;
pub mod periodic;
pub mod relay;
