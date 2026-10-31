use axum::extract::{FromRequestParts, Query};
use axum::http::request::Parts;
use courseflow_app::shared::pagination::{Cursor, PageRequest};
use serde::Deserialize;
use utoipa::IntoParams;

use crate::http::error::ApiError;

#[derive(Debug, Deserialize, IntoParams)]
pub struct PaginationQuery {
    /// Page size, 1..=100 (default 20).
    pub limit: Option<i64>,
    /// Opaque cursor from the previous page's `next_cursor`.
    pub cursor: Option<String>,
}

/// Parses `?limit=&cursor=` into a validated `PageRequest`.
#[derive(Debug, Clone, Copy)]
pub struct Pagination(pub PageRequest);

impl<S: Send + Sync> FromRequestParts<S> for Pagination {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let Query(q) = Query::<PaginationQuery>::from_request_parts(parts, state)
            .await
            .map_err(|e| ApiError::BadRequest(e.body_text()))?;
        let after = q.cursor.as_deref().map(Cursor::decode).transpose()?;
        Ok(Pagination(PageRequest::new(q.limit, after)?))
    }
}
