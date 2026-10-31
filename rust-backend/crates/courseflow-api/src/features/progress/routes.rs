use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use courseflow_core::ids::{CourseId, LessonId};

use crate::features::progress::dto::*;
use crate::http::error::{ApiError, ApiResult};
use crate::http::extractors::CurrentUser;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/lessons/{id}/complete", post(complete_lesson))
        .route("/me/courses/{course_id}/progress", get(course_progress))
        .route("/me/courses/{course_id}/certificate", get(my_certificate))
        .route("/certificates/{code}", get(verify_certificate))
}

#[utoipa::path(post, path = "/api/v1/lessons/{id}/complete", tag = "progress", security(("bearer" = [])),
    params(("id" = LessonId, Path)), responses((status = 200, body = CompletionResponse), (status = 403), (status = 404)))]
pub async fn complete_lesson(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<LessonId>,
) -> ApiResult<Json<CompletionResponse>> {
    let outcome = state.progress.complete_lesson(&user.actor(), id).await?;
    let (_, completed_ids) = state.progress.course_progress(user.id, outcome.progress.course_id).await?;
    Ok(Json(CompletionResponse {
        newly_completed: outcome.newly_completed,
        progress: ProgressResponse::new(outcome.progress, completed_ids),
        certificate: outcome.certificate.map(Into::into),
    }))
}

#[utoipa::path(get, path = "/api/v1/me/courses/{course_id}/progress", tag = "progress", security(("bearer" = [])),
    params(("course_id" = CourseId, Path)), responses((status = 200, body = ProgressResponse)))]
pub async fn course_progress(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(course_id): Path<CourseId>,
) -> ApiResult<Json<ProgressResponse>> {
    let (progress, ids) = state.progress.course_progress(user.id, course_id).await?;
    Ok(Json(ProgressResponse::new(progress, ids)))
}

#[utoipa::path(get, path = "/api/v1/me/courses/{course_id}/certificate", tag = "progress", security(("bearer" = [])),
    params(("course_id" = CourseId, Path)), responses((status = 200, body = CertificateResponse), (status = 404)))]
pub async fn my_certificate(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(course_id): Path<CourseId>,
) -> ApiResult<Json<CertificateResponse>> {
    let cert = state.progress.certificate(user.id, course_id).await?.ok_or(ApiError::NotFound("certificate"))?;
    Ok(Json(cert.into()))
}

#[utoipa::path(get, path = "/api/v1/certificates/{code}", tag = "progress", params(("code" = String, Path)),
    responses((status = 200, body = CertificateResponse), (status = 404)))]
pub async fn verify_certificate(
    State(state): State<AppState>,
    Path(code): Path<String>,
) -> ApiResult<Json<CertificateResponse>> {
    Ok(Json(state.progress.verify_certificate(&code).await?.into()))
}
