use axum::extract::{Path, Query, State};
use axum::http::{StatusCode, header};
use axum::response::IntoResponse;
use axum::routing::{get, post};
use axum::{Json, Router};
use courseflow_app::courses::{CourseFilter, UpdateCourse};
use courseflow_core::courses::CourseTitle;
use courseflow_core::ids::CourseId;
use courseflow_core::money::Money;

use crate::features::courses::dto::*;
use crate::http::error::ApiResult;
use crate::http::extractors::{CurrentUser, MaybeUser, Pagination, ValidatedJson};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/courses", get(list_courses).post(create_course))
        .route("/courses/{id}", get(get_course).patch(update_course).delete(delete_course))
        .route("/courses/{id}/publish", post(publish_course))
        .route("/courses/{id}/archive", post(archive_course))
        .route("/me/courses", get(my_courses))
}

#[utoipa::path(get, path = "/api/v1/courses", tag = "courses",
    params(CourseListQuery, crate::http::extractors::pagination::PaginationQuery),
    responses((status = 200, body = PageResponse<CourseResponse>)))]
pub async fn list_courses(
    State(state): State<AppState>,
    Query(q): Query<CourseListQuery>,
    Pagination(page): Pagination,
) -> ApiResult<Json<PageResponse<CourseResponse>>> {
    let filter = CourseFilter { status: None, author_id: q.author_id, search: q.search };
    let page = state.courses.list_public(filter, page).await?;
    Ok(Json(PageResponse::from_page(page)))
}

#[utoipa::path(get, path = "/api/v1/me/courses", tag = "courses", security(("bearer" = [])),
    params(MyCoursesQuery, crate::http::extractors::pagination::PaginationQuery),
    responses((status = 200, body = PageResponse<CourseResponse>), (status = 403)))]
pub async fn my_courses(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(q): Query<MyCoursesQuery>,
    Pagination(page): Pagination,
) -> ApiResult<Json<PageResponse<CourseResponse>>> {
    let page = state.courses.list_mine(&user.actor(), q.status, page).await?;
    Ok(Json(PageResponse::from_page(page)))
}

#[utoipa::path(post, path = "/api/v1/courses", tag = "courses", security(("bearer" = [])), request_body = CreateCourseRequest,
    responses((status = 201, body = CourseResponse, headers(("Location" = String))), (status = 403), (status = 422)))]
pub async fn create_course(
    State(state): State<AppState>,
    user: CurrentUser,
    ValidatedJson(body): ValidatedJson<CreateCourseRequest>,
) -> ApiResult<impl IntoResponse> {
    let input = body.into_new_course(user.id)?;
    let course = state.courses.create(&user.actor(), input).await?;
    let location = format!("/api/v1/courses/{}", course.id);
    Ok((StatusCode::CREATED, [(header::LOCATION, location)], Json(CourseResponse::from(course))))
}

#[utoipa::path(get, path = "/api/v1/courses/{id}", tag = "courses", params(("id" = CourseId, Path)),
    responses((status = 200, body = CourseResponse), (status = 404)))]
pub async fn get_course(
    State(state): State<AppState>,
    user: MaybeUser,
    Path(id): Path<CourseId>,
) -> ApiResult<Json<CourseResponse>> {
    let actor = user.map(|u| u.actor());
    let course = state.courses.get(actor.as_ref(), id).await?;
    Ok(Json(course.into()))
}

#[utoipa::path(patch, path = "/api/v1/courses/{id}", tag = "courses", security(("bearer" = [])), params(("id" = CourseId, Path)),
    request_body = UpdateCourseRequest, responses((status = 200, body = CourseResponse), (status = 403), (status = 404), (status = 409)))]
pub async fn update_course(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<CourseId>,
    ValidatedJson(body): ValidatedJson<UpdateCourseRequest>,
) -> ApiResult<Json<CourseResponse>> {
    let current = state.courses.get(Some(&user.actor()), id).await?;
    let changes = UpdateCourse {
        title: body.title.as_deref().map(CourseTitle::parse).transpose()?,
        description: body.description,
        price: body.price.map(|p| Money::new(p, body.currency.unwrap_or(current.price.currency()))).transpose()?,
    };
    let course = state.courses.update(&user.actor(), id, changes).await?;
    Ok(Json(course.into()))
}

#[utoipa::path(post, path = "/api/v1/courses/{id}/publish", tag = "courses", security(("bearer" = [])), params(("id" = CourseId, Path)),
    responses((status = 200, body = CourseResponse), (status = 403), (status = 409)))]
pub async fn publish_course(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<CourseId>,
) -> ApiResult<Json<CourseResponse>> {
    Ok(Json(state.courses.publish(&user.actor(), id).await?.into()))
}

#[utoipa::path(post, path = "/api/v1/courses/{id}/archive", tag = "courses", security(("bearer" = [])), params(("id" = CourseId, Path)),
    responses((status = 200, body = CourseResponse), (status = 403), (status = 409)))]
pub async fn archive_course(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<CourseId>,
) -> ApiResult<Json<CourseResponse>> {
    Ok(Json(state.courses.archive(&user.actor(), id).await?.into()))
}

#[utoipa::path(delete, path = "/api/v1/courses/{id}", tag = "courses", security(("bearer" = [])), params(("id" = CourseId, Path)),
    responses((status = 204), (status = 403), (status = 404), (status = 409)))]
pub async fn delete_course(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<CourseId>,
) -> ApiResult<StatusCode> {
    state.courses.delete_draft(&user.actor(), id).await?;
    Ok(StatusCode::NO_CONTENT)
}
