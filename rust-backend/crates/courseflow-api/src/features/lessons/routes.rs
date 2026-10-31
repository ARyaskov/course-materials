use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::get;
use axum::{Json, Router};
use courseflow_app::lessons::service::LessonInput;
use courseflow_core::ids::{CourseId, LessonId};

use crate::features::lessons::dto::*;
use crate::http::error::ApiResult;
use crate::http::extractors::{CurrentUser, MaybeUser, ValidatedJson};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/courses/{course_id}/lessons", get(list_lessons).post(add_lesson))
        .route("/lessons/{id}", get(get_lesson).put(update_lesson).delete(delete_lesson))
}

impl From<LessonRequest> for LessonInput {
    fn from(r: LessonRequest) -> Self {
        LessonInput { title: r.title, content_md: r.content_md, is_free_preview: r.is_free_preview }
    }
}

#[utoipa::path(get, path = "/api/v1/courses/{course_id}/lessons", tag = "lessons", params(("course_id" = CourseId, Path)),
    responses((status = 200, body = Vec<LessonSummary>), (status = 404)))]
pub async fn list_lessons(
    State(state): State<AppState>,
    user: MaybeUser,
    Path(course_id): Path<CourseId>,
) -> ApiResult<Json<Vec<LessonSummary>>> {
    let actor = user.map(|u| u.actor());
    let lessons = state.lessons.list(actor.as_ref(), course_id).await?;
    Ok(Json(lessons.into_iter().map(Into::into).collect()))
}

#[utoipa::path(post, path = "/api/v1/courses/{course_id}/lessons", tag = "lessons", security(("bearer" = [])),
    params(("course_id" = CourseId, Path)), request_body = LessonRequest,
    responses((status = 201, body = LessonResponse), (status = 403), (status = 404)))]
pub async fn add_lesson(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(course_id): Path<CourseId>,
    ValidatedJson(body): ValidatedJson<LessonRequest>,
) -> ApiResult<(StatusCode, Json<LessonResponse>)> {
    let lesson = state.lessons.add(&user.actor(), course_id, body.into()).await?;
    Ok((StatusCode::CREATED, Json(lesson.into())))
}

#[utoipa::path(get, path = "/api/v1/lessons/{id}", tag = "lessons", params(("id" = LessonId, Path)),
    responses((status = 200, body = LessonResponse), (status = 401), (status = 403), (status = 404)))]
pub async fn get_lesson(
    State(state): State<AppState>,
    user: MaybeUser,
    Path(id): Path<LessonId>,
) -> ApiResult<Json<LessonResponse>> {
    let actor = user.map(|u| u.actor());
    Ok(Json(state.lessons.get(actor.as_ref(), id).await?.into()))
}

#[utoipa::path(put, path = "/api/v1/lessons/{id}", tag = "lessons", security(("bearer" = [])), params(("id" = LessonId, Path)),
    request_body = LessonRequest, responses((status = 200, body = LessonResponse), (status = 403), (status = 404)))]
pub async fn update_lesson(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<LessonId>,
    ValidatedJson(body): ValidatedJson<LessonRequest>,
) -> ApiResult<Json<LessonResponse>> {
    Ok(Json(state.lessons.update(&user.actor(), id, body.into()).await?.into()))
}

#[utoipa::path(delete, path = "/api/v1/lessons/{id}", tag = "lessons", security(("bearer" = [])), params(("id" = LessonId, Path)),
    responses((status = 204), (status = 403), (status = 404), (status = 409)))]
pub async fn delete_lesson(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<LessonId>,
) -> ApiResult<StatusCode> {
    state.lessons.delete(&user.actor(), id).await?;
    Ok(StatusCode::NO_CONTENT)
}
