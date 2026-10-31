use thiserror::Error;

/// Errors produced by the domain: rule violations that the application layer
/// maps to HTTP 4xx codes. Infrastructure failures never appear here.
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum DomainError {
    #[error("{field}: {message}")]
    Validation { field: &'static str, message: String },

    #[error("invalid state transition: {entity} cannot go from {from} to {to}")]
    InvalidTransition { entity: &'static str, from: &'static str, to: &'static str },

    #[error("{0}")]
    RuleViolation(String),

    #[error("permission denied: {0}")]
    PermissionDenied(&'static str),
}

impl DomainError {
    pub fn validation(field: &'static str, message: impl Into<String>) -> Self {
        Self::Validation { field, message: message.into() }
    }

    pub fn rule(message: impl Into<String>) -> Self {
        Self::RuleViolation(message.into())
    }
}
