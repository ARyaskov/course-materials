use std::time::Duration;

use axum::extract::{ConnectInfo, State};
use axum::http::StatusCode;
use axum::routing::post;
use axum::{Json, Router};
use courseflow_app::cache::RateLimitDecision;
use courseflow_core::users::Email;
use std::net::SocketAddr;

use crate::features::auth::dto::*;
use crate::features::users::dto::UserResponse;
use crate::http::error::{ApiError, ApiResult};
use crate::http::extractors::ValidatedJson;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        .route("/auth/refresh", post(refresh))
        .route("/auth/logout", post(logout))
        .route("/auth/forgot-password", post(forgot_password))
        .route("/auth/reset-password", post(reset_password))
        .route("/auth/verify-email", post(verify_email))
}

/// Brute-force protection keyed by client IP. Behind a proxy the real IP
/// must come from `X-Forwarded-For` — configured at the proxy, not trusted
/// blindly here.
async fn limit(state: &AppState, scope: &str, addr: SocketAddr, limit: u64, window_secs: u64) -> ApiResult<()> {
    match state.rate_limiter.check(scope, &addr.ip().to_string(), limit, Duration::from_secs(window_secs)).await {
        RateLimitDecision::Allowed { .. } => Ok(()),
        RateLimitDecision::Limited { retry_after_secs } => Err(ApiError::RateLimited { retry_after_secs }),
    }
}

#[utoipa::path(post, path = "/api/v1/auth/register", tag = "auth", request_body = RegisterRequest,
    responses((status = 201, body = UserResponse), (status = 409, description = "e-mail already registered"), (status = 422)))]
pub async fn register(
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    ValidatedJson(body): ValidatedJson<RegisterRequest>,
) -> ApiResult<(StatusCode, Json<UserResponse>)> {
    limit(&state, "register", addr, 10, 3600).await?;
    let email = Email::parse(&body.email)?;
    let user = state.auth.register(email, &body.display_name, &body.password).await?;
    Ok((StatusCode::CREATED, Json(user.into())))
}

#[utoipa::path(post, path = "/api/v1/auth/login", tag = "auth", request_body = LoginRequest,
    responses((status = 200, body = TokenResponse), (status = 401), (status = 429)))]
pub async fn login(
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    ValidatedJson(body): ValidatedJson<LoginRequest>,
) -> ApiResult<Json<TokenResponse>> {
    limit(&state, "login", addr, 20, 300).await?;
    let email = Email::parse(&body.email).map_err(|_| ApiError::Unauthorized("invalid credentials"))?;
    let (_user, pair) = state.auth.login(&email, &body.password).await?;
    Ok(Json(pair.into()))
}

#[utoipa::path(post, path = "/api/v1/auth/refresh", tag = "auth", request_body = RefreshRequest,
    responses((status = 200, body = TokenResponse), (status = 401)))]
pub async fn refresh(
    State(state): State<AppState>,
    ValidatedJson(body): ValidatedJson<RefreshRequest>,
) -> ApiResult<Json<TokenResponse>> {
    let (_user, pair) = state.auth.refresh(&body.refresh_token).await?;
    Ok(Json(pair.into()))
}

#[utoipa::path(post, path = "/api/v1/auth/logout", tag = "auth", request_body = RefreshRequest, responses((status = 204)))]
pub async fn logout(
    State(state): State<AppState>,
    ValidatedJson(body): ValidatedJson<RefreshRequest>,
) -> ApiResult<StatusCode> {
    state.auth.logout(&body.refresh_token).await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/auth/forgot-password", tag = "auth", request_body = ForgotPasswordRequest, responses((status = 202)))]
pub async fn forgot_password(
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    ValidatedJson(body): ValidatedJson<ForgotPasswordRequest>,
) -> ApiResult<StatusCode> {
    limit(&state, "forgot", addr, 5, 3600).await?;
    if let Ok(email) = Email::parse(&body.email) {
        state.auth.request_password_reset(&email).await?;
    }
    // 202 regardless: the response must not reveal whether the account exists.
    Ok(StatusCode::ACCEPTED)
}

#[utoipa::path(post, path = "/api/v1/auth/reset-password", tag = "auth", request_body = ResetPasswordRequest, responses((status = 204), (status = 401)))]
pub async fn reset_password(
    State(state): State<AppState>,
    ValidatedJson(body): ValidatedJson<ResetPasswordRequest>,
) -> ApiResult<StatusCode> {
    state.auth.reset_password(&body.token, &body.new_password).await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/api/v1/auth/verify-email", tag = "auth", request_body = VerifyEmailRequest, responses((status = 200, body = UserResponse), (status = 401)))]
pub async fn verify_email(
    State(state): State<AppState>,
    ValidatedJson(body): ValidatedJson<VerifyEmailRequest>,
) -> ApiResult<Json<UserResponse>> {
    let user = state.auth.verify_email(&body.token).await?;
    Ok(Json(user.into()))
}
