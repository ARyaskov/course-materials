//! One error type for the application layer. HTTP mapping lives in the API
//! crate; here we only classify.

use courseflow_core::DomainError;
use courseflow_core::ports::{BillingError, HashError};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    /// Domain rule broken: 4xx after mapping.
    #[error(transparent)]
    Domain(#[from] DomainError),

    #[error("{entity} not found")]
    NotFound { entity: &'static str },

    /// Uniqueness or state conflict: 409.
    #[error("conflict: {0}")]
    Conflict(String),

    /// Caller is not authenticated (or the credentials are wrong): 401.
    #[error("unauthorized: {0}")]
    Unauthorized(&'static str),

    /// Too many requests: 429 with a retry hint in seconds.
    #[error("rate limited, retry after {retry_after_secs}s")]
    RateLimited { retry_after_secs: u64 },

    /// A dependency is down and the operation cannot be completed: 503.
    #[error("service unavailable: {0}")]
    Unavailable(String),

    #[error(transparent)]
    Billing(#[from] BillingError),

    /// Anything we did not expect: 500, logged with the full source chain.
    #[error("internal error: {0}")]
    Internal(#[from] anyhow::Error),
}

impl AppError {
    pub fn not_found(entity: &'static str) -> Self {
        Self::NotFound { entity }
    }

    pub fn conflict(message: impl Into<String>) -> Self {
        Self::Conflict(message.into())
    }
}

impl From<sqlx::Error> for AppError {
    fn from(err: sqlx::Error) -> Self {
        match &err {
            sqlx::Error::RowNotFound => AppError::NotFound { entity: "row" },
            sqlx::Error::Database(db)
                if db.is_unique_violation() || matches!(db.kind(), sqlx::error::ErrorKind::ExclusionViolation) =>
            {
                AppError::Conflict(db.constraint().unwrap_or("unique constraint").to_owned())
            }
            sqlx::Error::Database(db) if db.is_foreign_key_violation() => {
                AppError::Conflict("referenced entity does not exist".to_owned())
            }
            // Domain validation rejects these first; the CHECK is the last line
            // of defence against writes that bypass the domain.
            sqlx::Error::Database(db) if db.is_check_violation() => AppError::Domain(DomainError::validation(
                "body",
                format!("violates {}", db.constraint().unwrap_or("check constraint")),
            )),
            sqlx::Error::PoolTimedOut | sqlx::Error::PoolClosed | sqlx::Error::Io(_) => {
                AppError::Unavailable("database".to_owned())
            }
            _ => AppError::Internal(anyhow::Error::new(err).context("database error")),
        }
    }
}

impl From<redis::RedisError> for AppError {
    fn from(err: redis::RedisError) -> Self {
        if err.is_io_error() || err.is_timeout() || err.is_connection_dropped() {
            AppError::Unavailable("redis".to_owned())
        } else {
            AppError::Internal(anyhow::Error::new(err).context("redis error"))
        }
    }
}

impl From<HashError> for AppError {
    fn from(err: HashError) -> Self {
        AppError::Internal(anyhow::Error::new(err))
    }
}

impl From<serde_json::Error> for AppError {
    fn from(err: serde_json::Error) -> Self {
        AppError::Internal(anyhow::Error::new(err).context("json"))
    }
}

pub type AppResult<T> = Result<T, AppError>;
