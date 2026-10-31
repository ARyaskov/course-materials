use chrono::{DateTime, Utc};
use courseflow_core::ids::UserId;
use courseflow_core::users::{Role, User};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::http::error::FieldError;
use crate::http::extractors::validated::Validate;

#[derive(Debug, Serialize, ToSchema)]
pub struct UserResponse {
    pub id: UserId,
    pub email: String,
    pub display_name: String,
    pub role: Role,
    pub email_verified: bool,
    pub created_at: DateTime<Utc>,
}

impl From<User> for UserResponse {
    fn from(u: User) -> Self {
        // a partial move of `display_name` would invalidate `u`, so read the
        // derived flag first
        let email_verified = u.is_verified();
        Self {
            id: u.id,
            email: u.email.to_string(),
            display_name: u.display_name,
            role: u.role,
            email_verified,
            created_at: u.created_at,
        }
    }
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct ChangeRoleRequest {
    pub role: Role,
}

impl Validate for ChangeRoleRequest {
    fn validate(&self) -> Vec<FieldError> {
        vec![]
    }
}
