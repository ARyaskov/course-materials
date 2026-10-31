//! RFC 9457 Problem Details for every error the API returns.
//!
//! ```json
//! {
//!   "type": "https://courseflow.dev/errors/validation",
//!   "title": "Validation failed",
//!   "status": 422,
//!   "detail": "title: must not be empty",
//!   "code": "validation_failed",
//!   "errors": [{"field": "title", "message": "must not be empty"}],
//!   "request_id": "…"
//! }
//! ```

use axum::Json;
use axum::extract::rejection::JsonRejection;
use axum::http::{HeaderValue, StatusCode, header};
use axum::response::{IntoResponse, Response};
use courseflow_app::AppError;
use courseflow_core::DomainError;
use serde::Serialize;
use utoipa::ToSchema;

#[derive(Debug, Clone, Serialize, ToSchema, PartialEq, Eq)]
pub struct FieldError {
    pub field: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct Problem {
    #[serde(rename = "type")]
    pub type_uri: String,
    pub title: String,
    pub status: u16,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    /// Stable machine-readable code; clients switch on this, never on `detail`.
    pub code: &'static str,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub errors: Vec<FieldError>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retry_after_secs: Option<u64>,
}

#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("bad request: {0}")]
    BadRequest(String),
    #[error("validation failed")]
    Validation(Vec<FieldError>),
    #[error("unauthorized")]
    Unauthorized(&'static str),
    #[error("forbidden: {0}")]
    Forbidden(String),
    #[error("{0} not found")]
    NotFound(&'static str),
    #[error("conflict: {0}")]
    Conflict(String),
    #[error("rate limited")]
    RateLimited { retry_after_secs: u64 },
    #[error("service unavailable: {0}")]
    Unavailable(String),
    #[error("internal error")]
    Internal(#[source] anyhow::Error),
}

pub type ApiResult<T> = Result<T, ApiError>;

impl ApiError {
    pub fn status(&self) -> StatusCode {
        match self {
            ApiError::BadRequest(_) => StatusCode::BAD_REQUEST,
            ApiError::Validation(_) => StatusCode::UNPROCESSABLE_ENTITY,
            ApiError::Unauthorized(_) => StatusCode::UNAUTHORIZED,
            ApiError::Forbidden(_) => StatusCode::FORBIDDEN,
            ApiError::NotFound(_) => StatusCode::NOT_FOUND,
            ApiError::Conflict(_) => StatusCode::CONFLICT,
            ApiError::RateLimited { .. } => StatusCode::TOO_MANY_REQUESTS,
            ApiError::Unavailable(_) => StatusCode::SERVICE_UNAVAILABLE,
            ApiError::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            ApiError::BadRequest(_) => "bad_request",
            ApiError::Validation(_) => "validation_failed",
            ApiError::Unauthorized(_) => "unauthorized",
            ApiError::Forbidden(_) => "forbidden",
            ApiError::NotFound(_) => "not_found",
            ApiError::Conflict(_) => "conflict",
            ApiError::RateLimited { .. } => "rate_limited",
            ApiError::Unavailable(_) => "unavailable",
            ApiError::Internal(_) => "internal_error",
        }
    }

    pub fn to_problem(&self, request_id: Option<String>) -> Problem {
        let status = self.status();
        let (title, detail, errors, retry_after_secs) = match self {
            ApiError::BadRequest(d) => ("Bad request", Some(d.clone()), vec![], None),
            ApiError::Validation(errors) => {
                let detail = errors.first().map(|e| format!("{}: {}", e.field, e.message));
                ("Validation failed", detail, errors.clone(), None)
            }
            ApiError::Unauthorized(d) => ("Unauthorized", Some((*d).to_owned()), vec![], None),
            ApiError::Forbidden(d) => ("Forbidden", Some(d.clone()), vec![], None),
            ApiError::NotFound(entity) => ("Not found", Some(format!("{entity} not found")), vec![], None),
            ApiError::Conflict(d) => ("Conflict", Some(d.clone()), vec![], None),
            ApiError::RateLimited { retry_after_secs } => ("Too many requests", None, vec![], Some(*retry_after_secs)),
            ApiError::Unavailable(d) => {
                ("Service unavailable", Some(format!("{d} is unavailable, retry later")), vec![], None)
            }
            // Never leak internals: the request id is the link to the server log.
            ApiError::Internal(_) => ("Internal server error", None, vec![], None),
        };
        Problem {
            type_uri: format!("https://courseflow.dev/errors/{}", self.code()),
            title: title.to_owned(),
            status: status.as_u16(),
            detail,
            code: self.code(),
            errors,
            request_id,
            retry_after_secs,
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let status = self.status();
        match &self {
            ApiError::Internal(err) => tracing::error!(error = ?err, "request failed"),
            ApiError::Unavailable(dep) => tracing::warn!(dependency = %dep, "dependency unavailable"),
            other => tracing::debug!(error = %other, code = other.code(), "request rejected"),
        }
        metrics::counter!("courseflow_http_errors_total", "code" => self.code()).increment(1);
        // request id is attached later by the middleware that knows it
        let problem = self.to_problem(None);
        let mut response = (status, Json(problem)).into_response();
        response.headers_mut().insert(header::CONTENT_TYPE, HeaderValue::from_static("application/problem+json"));
        if let ApiError::RateLimited { retry_after_secs } = self
            && let Ok(value) = HeaderValue::from_str(&retry_after_secs.to_string())
        {
            response.headers_mut().insert(header::RETRY_AFTER, value);
        }
        response
    }
}

impl From<AppError> for ApiError {
    fn from(err: AppError) -> Self {
        match err {
            AppError::Domain(DomainError::Validation { field, message }) => {
                ApiError::Validation(vec![FieldError { field: field.to_owned(), message }])
            }
            AppError::Domain(DomainError::PermissionDenied(reason)) => ApiError::Forbidden(reason.to_owned()),
            AppError::Domain(e @ DomainError::InvalidTransition { .. }) => ApiError::Conflict(e.to_string()),
            AppError::Domain(DomainError::RuleViolation(msg)) => ApiError::Conflict(msg),
            AppError::NotFound { entity } => ApiError::NotFound(entity),
            AppError::Conflict(msg) => ApiError::Conflict(msg),
            AppError::Unauthorized(reason) => ApiError::Unauthorized(reason),
            AppError::RateLimited { retry_after_secs } => ApiError::RateLimited { retry_after_secs },
            AppError::Unavailable(dep) => ApiError::Unavailable(dep),
            AppError::Billing(e) => match e {
                courseflow_core::ports::BillingError::Rejected(msg) => {
                    ApiError::Conflict(format!("payment rejected: {msg}"))
                }
                other => ApiError::Unavailable(format!("billing provider ({other})")),
            },
            AppError::Internal(e) => ApiError::Internal(e),
        }
    }
}

impl From<DomainError> for ApiError {
    fn from(err: DomainError) -> Self {
        ApiError::from(AppError::Domain(err))
    }
}

impl From<JsonRejection> for ApiError {
    fn from(rejection: JsonRejection) -> Self {
        match rejection {
            JsonRejection::JsonDataError(e) => {
                ApiError::Validation(vec![FieldError { field: "body".into(), message: e.body_text() }])
            }
            JsonRejection::JsonSyntaxError(e) => ApiError::BadRequest(format!("malformed JSON: {}", e.body_text())),
            JsonRejection::MissingJsonContentType(_) => {
                ApiError::BadRequest("expected Content-Type: application/json".into())
            }
            other => ApiError::BadRequest(other.body_text()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validation_maps_to_422_with_field_errors() {
        let err: ApiError = AppError::Domain(DomainError::validation("title", "must not be empty")).into();
        assert_eq!(err.status(), StatusCode::UNPROCESSABLE_ENTITY);
        let problem = err.to_problem(Some("req-1".into()));
        assert_eq!(problem.code, "validation_failed");
        assert_eq!(problem.errors[0].field, "title");
        assert_eq!(problem.request_id.as_deref(), Some("req-1"));
    }

    #[test]
    fn internal_error_hides_details() {
        let err = ApiError::Internal(anyhow::anyhow!("db password is hunter2"));
        let problem = err.to_problem(None);
        assert_eq!(problem.status, 500);
        assert!(problem.detail.is_none());
        assert!(!serde_json::to_string(&problem).unwrap().contains("hunter2"));
    }
}
