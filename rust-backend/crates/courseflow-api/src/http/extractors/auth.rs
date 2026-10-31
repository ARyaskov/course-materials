//! `CurrentUser`: Bearer token → verified principal. No database round-trip:
//! the role travels in the token, and an access token lives 15 minutes.

use axum::extract::{FromRef, FromRequestParts, OptionalFromRequestParts};
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use courseflow_app::auth::AuthService;
use courseflow_app::auth::jwt::JwtError;
use courseflow_core::ids::UserId;
use courseflow_core::policy::Actor;
use courseflow_core::users::Role;

use crate::http::error::ApiError;

#[derive(Debug, Clone, Copy)]
pub struct CurrentUser {
    pub id: UserId,
    pub role: Role,
}

impl CurrentUser {
    pub fn actor(&self) -> Actor {
        Actor::new(self.id, self.role)
    }
}

fn bearer(parts: &Parts) -> Result<Option<&str>, ApiError> {
    let Some(value) = parts.headers.get(AUTHORIZATION) else { return Ok(None) };
    let value = value.to_str().map_err(|_| ApiError::Unauthorized("malformed Authorization header"))?;
    let token = value.strip_prefix("Bearer ").ok_or(ApiError::Unauthorized("expected Bearer token"))?;
    Ok(Some(token.trim()))
}

fn verify(auth: &AuthService, token: &str) -> Result<CurrentUser, ApiError> {
    match auth.authenticate(token) {
        Ok((id, role)) => Ok(CurrentUser { id, role }),
        Err(JwtError::Expired) => Err(ApiError::Unauthorized("access token expired")),
        Err(JwtError::Invalid) => Err(ApiError::Unauthorized("invalid access token")),
    }
}

impl<S> FromRequestParts<S> for CurrentUser
where
    S: Send + Sync,
    AuthService: FromRef<S>,
{
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let token = bearer(parts)?.ok_or(ApiError::Unauthorized("authentication required"))?;
        let user = verify(&AuthService::from_ref(state), token)?;
        tracing::Span::current().record("user_id", tracing::field::display(user.id));
        Ok(user)
    }
}

/// Axum 0.8: `Option<CurrentUser>` in a handler goes through this impl.
/// A missing header is `None`; a *present but invalid* token is still an
/// error — silently downgrading a bad token to anonymous hides client bugs.
impl<S> OptionalFromRequestParts<S> for CurrentUser
where
    S: Send + Sync,
    AuthService: FromRef<S>,
{
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Option<Self>, Self::Rejection> {
        match bearer(parts)? {
            None => Ok(None),
            Some(token) => verify(&AuthService::from_ref(state), token).map(Some),
        }
    }
}

/// Readable alias for handlers serving both anonymous and logged-in users.
pub type MaybeUser = Option<CurrentUser>;

impl CurrentUser {
    pub fn require_role(&self, role: Role) -> Result<(), ApiError> {
        let ok = match role {
            Role::Student => true,
            Role::Author => self.role.can_author(),
            Role::Admin => self.role.is_admin(),
        };
        if ok { Ok(()) } else { Err(ApiError::Forbidden(format!("{role} role required"))) }
    }
}
