use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use courseflow_core::ids::CourseId;

use crate::features::enrollments::dto::*;
use crate::http::error::ApiResult;
use crate::http::extractors::{CurrentUser, ValidatedJson};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new().route("/courses/{course_id}/enroll", post(enroll_free)).route("/me/enrollments", get(my_enrollments))
}

/// Mounted under `/admin` with the role guard from `http::middleware`.
pub fn admin_router() -> Router<AppState> {
    Router::new().route("/courses/{course_id}/grants", post(grant))
}

#[utoipa::path(post, path = "/api/v1/courses/{course_id}/enroll", tag = "enrollments", security(("bearer" = [])),
    params(("course_id" = CourseId, Path)), responses((status = 201, body = EnrollmentResponse), (status = 404), (status = 409)))]
pub async fn enroll_free(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(course_id): Path<CourseId>,
) -> ApiResult<(StatusCode, Json<EnrollmentResponse>)> {
    let e = state.enrollments.enroll_free(&user.actor(), course_id).await?;
    Ok((StatusCode::CREATED, Json(e.into())))
}

#[utoipa::path(post, path = "/api/v1/admin/courses/{course_id}/grants", tag = "enrollments", security(("bearer" = [])),
    params(("course_id" = CourseId, Path)), request_body = GrantRequest,
    responses((status = 201, body = EnrollmentResponse), (status = 403), (status = 409)))]
pub async fn grant(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(course_id): Path<CourseId>,
    ValidatedJson(body): ValidatedJson<GrantRequest>,
) -> ApiResult<(StatusCode, Json<EnrollmentResponse>)> {
    let e = state.enrollments.grant(&user.actor(), body.user_id, course_id).await?;
    Ok((StatusCode::CREATED, Json(e.into())))
}

#[utoipa::path(get, path = "/api/v1/me/enrollments", tag = "enrollments", security(("bearer" = [])),
    responses((status = 200, body = Vec<EnrollmentResponse>)))]
pub async fn my_enrollments(
    State(state): State<AppState>,
    user: CurrentUser,
) -> ApiResult<Json<Vec<EnrollmentResponse>>> {
    let list = state.enrollments.list_mine(&user.actor()).await?;
    Ok(Json(list.into_iter().map(Into::into).collect()))
}
