use axum::extract::FromRequestParts;
use axum::http::request::Parts;

use crate::http::error::ApiError;

pub const HEADER: &str = "idempotency-key";

/// Required on purchase endpoints: a retry with the same key must not create
/// a second purchase. Format is client-chosen; length is capped.
#[derive(Debug, Clone)]
pub struct IdempotencyKey(pub String);

impl<S: Send + Sync> FromRequestParts<S> for IdempotencyKey {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        let value = parts
            .headers
            .get(HEADER)
            .ok_or(ApiError::BadRequest("Idempotency-Key header is required".into()))?
            .to_str()
            .map_err(|_| ApiError::BadRequest("Idempotency-Key must be ASCII".into()))?
            .trim();
        if value.is_empty() || value.len() > 128 {
            return Err(ApiError::BadRequest("Idempotency-Key must be 1..=128 characters".into()));
        }
        // The key becomes a segment of a Redis key: no separators, no surprises.
        if !value.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_') {
            return Err(ApiError::BadRequest("Idempotency-Key may contain only letters, digits, '-' and '_'".into()));
        }
        Ok(IdempotencyKey(value.to_owned()))
    }
}
