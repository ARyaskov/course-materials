use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use std::convert::Infallible;

pub const HEADER: &str = "x-request-id";

/// The id set by `SetRequestIdLayer`; handlers include it in problem
/// responses so a client can quote it in a bug report.
#[derive(Debug, Clone)]
pub struct RequestId(pub String);

impl<S: Send + Sync> FromRequestParts<S> for RequestId {
    type Rejection = Infallible;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        let id = parts.headers.get(HEADER).and_then(|v| v.to_str().ok()).unwrap_or("unknown").to_owned();
        Ok(RequestId(id))
    }
}
