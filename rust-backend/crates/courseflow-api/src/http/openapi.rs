//! OpenAPI 3.1 document generated from the handlers' `#[utoipa::path]`
//! attributes. Served at `/api/docs/openapi.json`; a snapshot test keeps it
//! from drifting silently.

use utoipa::openapi::security::{HttpAuthScheme, HttpBuilder, SecurityScheme};
use utoipa::{Modify, OpenApi};

use crate::features::{auth, billing, courses, enrollments, lessons, notifications, progress, users};
use crate::http::error::Problem;
use crate::http::health;

struct BearerAuth;

impl Modify for BearerAuth {
    fn modify(&self, openapi: &mut utoipa::openapi::OpenApi) {
        if let Some(components) = openapi.components.as_mut() {
            components.add_security_scheme(
                "bearer",
                SecurityScheme::Http(HttpBuilder::new().scheme(HttpAuthScheme::Bearer).bearer_format("JWT").build()),
            );
        }
    }
}

#[derive(Debug, OpenApi)]
#[openapi(
    info(title = "CourseFlow API", version = "1.0.0", description = "Online course platform backend. Errors use RFC 9457 problem details."),
    paths(
        health::live, health::ready,
        auth::routes::register, auth::routes::login, auth::routes::refresh, auth::routes::logout,
        auth::routes::forgot_password, auth::routes::reset_password, auth::routes::verify_email,
        users::routes::me, users::routes::change_role,
        courses::routes::list_courses, courses::routes::my_courses, courses::routes::create_course, courses::routes::get_course,
        courses::routes::update_course, courses::routes::publish_course, courses::routes::archive_course, courses::routes::delete_course,
        lessons::routes::list_lessons, lessons::routes::add_lesson, lessons::routes::get_lesson, lessons::routes::update_lesson, lessons::routes::delete_lesson,
        enrollments::routes::enroll_free, enrollments::routes::grant, enrollments::routes::my_enrollments,
        progress::routes::complete_lesson, progress::routes::course_progress, progress::routes::my_certificate, progress::routes::verify_certificate,
        billing::routes::checkout, billing::routes::my_purchases, billing::routes::get_purchase, billing::routes::billing_webhook,
        notifications::routes::list, notifications::routes::unread, notifications::routes::mark_read, notifications::routes::sse_stream,
    ),
    components(schemas(Problem)),
    modifiers(&BearerAuth),
    tags(
        (name = "health"), (name = "auth"), (name = "users"), (name = "courses"), (name = "lessons"),
        (name = "enrollments"), (name = "progress"), (name = "billing"), (name = "notifications"),
    )
)]
pub struct ApiDoc;

pub async fn openapi_json() -> axum::Json<utoipa::openapi::OpenApi> {
    axum::Json(ApiDoc::openapi())
}
