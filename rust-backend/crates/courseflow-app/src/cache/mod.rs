//! Redis adapters. Every operation is optional from the business point of
//! view except idempotency: a cache miss or a rate-limit counter that cannot
//! be read falls back to the database path; an idempotency check that cannot
//! be performed fails the request (fail-closed).

pub mod course_cache;
pub mod idempotency;
pub mod rate_limit;
pub mod redis_client;

pub use course_cache::CourseCache;
pub use idempotency::{IdempotencyGuard, IdempotencyOutcome};
pub use rate_limit::{RateLimitDecision, RateLimiter};
pub use redis_client::{RedisHandle, connect};
