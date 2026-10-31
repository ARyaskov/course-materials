//! `ValidatedJson<T>`: parse JSON, then run `T::validate`. Handlers receive
//! a value that is syntactically and semantically acceptable, or the client
//! already got a 400/422 problem response.

use axum::Json;
use axum::extract::{FromRequest, Request};

use crate::http::error::{ApiError, FieldError};

pub trait Validate {
    fn validate(&self) -> Vec<FieldError>;
}

/// Small helper so DTO impls read like a checklist.
#[derive(Debug, Default)]
pub struct Errors(Vec<FieldError>);

impl Errors {
    pub fn push(&mut self, field: &str, message: impl Into<String>) {
        self.0.push(FieldError { field: field.to_owned(), message: message.into() });
    }

    pub fn check(&mut self, ok: bool, field: &str, message: &str) {
        if !ok {
            self.push(field, message);
        }
    }

    pub fn into_vec(self) -> Vec<FieldError> {
        self.0
    }
}

#[derive(Debug, Clone)]
pub struct ValidatedJson<T>(pub T);

impl<T, S> FromRequest<S> for ValidatedJson<T>
where
    T: serde::de::DeserializeOwned + Validate,
    S: Send + Sync,
{
    type Rejection = ApiError;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        let Json(value) = Json::<T>::from_request(req, state).await?;
        let errors = value.validate();
        if !errors.is_empty() {
            return Err(ApiError::Validation(errors));
        }
        Ok(ValidatedJson(value))
    }
}
