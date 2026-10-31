use axum::extract::{Path, State};
use axum::routing::{get, patch};
use axum::{Json, Router};
use courseflow_core::ids::UserId;

use crate::features::users::dto::*;
use crate::http::error::ApiResult;
use crate::http::extractors::{CurrentUser, ValidatedJson};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new().route("/me", get(me))
}

/// Mounted under `/admin` with the role guard from `http::middleware`.
pub fn admin_router() -> Router<AppState> {
    Router::new().route("/users/{id}/role", patch(change_role))
}

#[utoipa::path(get, path = "/api/v1/me", tag = "users", security(("bearer" = [])), responses((status = 200, body = UserResponse), (status = 401)))]
pub async fn me(State(state): State<AppState>, user: CurrentUser) -> ApiResult<Json<UserResponse>> {
    Ok(Json(state.users.get(user.id).await?.into()))
}

#[utoipa::path(patch, path = "/api/v1/admin/users/{id}/role", tag = "users", security(("bearer" = [])),
    params(("id" = UserId, Path)), request_body = ChangeRoleRequest,
    responses((status = 200, body = UserResponse), (status = 403), (status = 404)))]
pub async fn change_role(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<UserId>,
    ValidatedJson(body): ValidatedJson<ChangeRoleRequest>,
) -> ApiResult<Json<UserResponse>> {
    let updated = state.users.change_role(&user.actor(), id, body.role).await?;
    Ok(Json(updated.into()))
}
