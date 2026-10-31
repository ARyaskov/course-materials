//! Custom extractors: the HTTP boundary translated into typed values.

pub mod auth;
pub mod idempotency;
pub mod pagination;
pub mod request_id;
pub mod signed_webhook;
pub mod validated;

pub use auth::{CurrentUser, MaybeUser};
pub use idempotency::IdempotencyKey;
pub use pagination::Pagination;
pub use request_id::RequestId;
pub use signed_webhook::SignedWebhook;
pub use validated::{Validate, ValidatedJson};
