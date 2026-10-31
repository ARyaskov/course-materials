use secrecy::SecretString;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::http::error::FieldError;
use crate::http::extractors::validated::{Errors, Validate};

#[derive(Debug, Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct RegisterRequest {
    #[schema(example = "alice@example.com")]
    pub email: String,
    #[schema(example = "Alice")]
    pub display_name: String,
    #[schema(value_type = String, example = "correct-horse-42")]
    pub password: SecretString,
}

impl Validate for RegisterRequest {
    fn validate(&self) -> Vec<FieldError> {
        use secrecy::ExposeSecret;
        let mut e = Errors::default();
        e.check(self.email.contains('@'), "email", "must be an e-mail address");
        e.check(!self.display_name.trim().is_empty(), "display_name", "must not be empty");
        e.check(self.password.expose_secret().chars().count() >= 10, "password", "must be at least 10 characters");
        e.into_vec()
    }
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct LoginRequest {
    pub email: String,
    #[schema(value_type = String)]
    pub password: SecretString,
}

impl Validate for LoginRequest {
    fn validate(&self) -> Vec<FieldError> {
        let mut e = Errors::default();
        e.check(!self.email.trim().is_empty(), "email", "must not be empty");
        e.into_vec()
    }
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct RefreshRequest {
    #[schema(value_type = String)]
    pub refresh_token: SecretString,
}

impl Validate for RefreshRequest {
    fn validate(&self) -> Vec<FieldError> {
        vec![]
    }
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct ForgotPasswordRequest {
    pub email: String,
}

impl Validate for ForgotPasswordRequest {
    fn validate(&self) -> Vec<FieldError> {
        vec![]
    }
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct ResetPasswordRequest {
    #[schema(value_type = String)]
    pub token: SecretString,
    #[schema(value_type = String)]
    pub new_password: SecretString,
}

impl Validate for ResetPasswordRequest {
    fn validate(&self) -> Vec<FieldError> {
        vec![]
    }
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct VerifyEmailRequest {
    #[schema(value_type = String)]
    pub token: SecretString,
}

impl Validate for VerifyEmailRequest {
    fn validate(&self) -> Vec<FieldError> {
        vec![]
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct TokenResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: &'static str,
    pub expires_in: u64,
}

impl From<courseflow_app::auth::TokenPair> for TokenResponse {
    fn from(pair: courseflow_app::auth::TokenPair) -> Self {
        use secrecy::ExposeSecret;
        Self {
            access_token: pair.access_token,
            refresh_token: pair.refresh_token.expose_secret().to_owned(),
            token_type: "Bearer",
            expires_in: pair.access_expires_in.as_secs(),
        }
    }
}
