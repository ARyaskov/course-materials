use chrono::{DateTime, Utc};
use courseflow_core::ids::{CourseId, LessonId, UserId};
use courseflow_core::progress::{Certificate, CourseProgress};
use serde::Serialize;
use utoipa::ToSchema;

#[derive(Debug, Serialize, ToSchema)]
pub struct ProgressResponse {
    pub course_id: CourseId,
    pub completed_lessons: u32,
    pub total_lessons: u32,
    pub percent: u8,
    pub completed_lesson_ids: Vec<LessonId>,
}

impl ProgressResponse {
    pub fn new(p: CourseProgress, completed_lesson_ids: Vec<LessonId>) -> Self {
        Self {
            course_id: p.course_id,
            completed_lessons: p.completed_lessons,
            total_lessons: p.total_lessons,
            percent: p.percent(),
            completed_lesson_ids,
        }
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct CertificateResponse {
    pub user_id: UserId,
    pub course_id: CourseId,
    pub code: String,
    pub issued_at: DateTime<Utc>,
}

impl From<Certificate> for CertificateResponse {
    fn from(c: Certificate) -> Self {
        Self { user_id: c.user_id, course_id: c.course_id, code: c.code, issued_at: c.issued_at }
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct CompletionResponse {
    pub newly_completed: bool,
    pub progress: ProgressResponse,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub certificate: Option<CertificateResponse>,
}
