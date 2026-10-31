use chrono::{DateTime, Utc};
use courseflow_core::enrollments::{Enrollment, EnrollmentSource};
use courseflow_core::ids::{CourseId, EnrollmentId, UserId};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::http::error::FieldError;
use crate::http::extractors::validated::Validate;

#[derive(Debug, Serialize, ToSchema)]
pub struct EnrollmentResponse {
    pub id: EnrollmentId,
    pub user_id: UserId,
    pub course_id: CourseId,
    #[schema(value_type = Object)]
    pub source: EnrollmentSource,
    pub created_at: DateTime<Utc>,
}

impl From<Enrollment> for EnrollmentResponse {
    fn from(e: Enrollment) -> Self {
        Self { id: e.id, user_id: e.user_id, course_id: e.course_id, source: e.source, created_at: e.created_at }
    }
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct GrantRequest {
    pub user_id: UserId,
}

impl Validate for GrantRequest {
    fn validate(&self) -> Vec<FieldError> {
        vec![]
    }
}
