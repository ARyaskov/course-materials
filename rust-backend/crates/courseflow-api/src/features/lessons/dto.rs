use chrono::{DateTime, Utc};
use courseflow_core::ids::{CourseId, LessonId};
use courseflow_core::lessons::Lesson;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::http::error::FieldError;
use crate::http::extractors::validated::{Errors, Validate};

#[derive(Debug, Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct LessonRequest {
    pub title: String,
    #[serde(default)]
    pub content_md: String,
    #[serde(default)]
    pub is_free_preview: bool,
}

impl Validate for LessonRequest {
    fn validate(&self) -> Vec<FieldError> {
        let mut e = Errors::default();
        let len = self.title.trim().chars().count();
        e.check((1..=Lesson::MAX_TITLE_LEN).contains(&len), "title", "must be 1..=200 characters");
        e.check(self.content_md.len() <= Lesson::MAX_CONTENT_LEN, "content_md", "content is too large");
        e.into_vec()
    }
}

/// Table-of-contents entry: no body, safe to show to anyone.
#[derive(Debug, Serialize, ToSchema)]
pub struct LessonSummary {
    pub id: LessonId,
    pub course_id: CourseId,
    pub position: i32,
    pub title: String,
    pub is_free_preview: bool,
}

impl From<Lesson> for LessonSummary {
    fn from(l: Lesson) -> Self {
        Self {
            id: l.id,
            course_id: l.course_id,
            position: l.position,
            title: l.title,
            is_free_preview: l.is_free_preview,
        }
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct LessonResponse {
    pub id: LessonId,
    pub course_id: CourseId,
    pub position: i32,
    pub title: String,
    pub content_md: String,
    pub is_free_preview: bool,
    pub updated_at: DateTime<Utc>,
}

impl From<Lesson> for LessonResponse {
    fn from(l: Lesson) -> Self {
        Self {
            id: l.id,
            course_id: l.course_id,
            position: l.position,
            title: l.title,
            content_md: l.content_md,
            is_free_preview: l.is_free_preview,
            updated_at: l.updated_at,
        }
    }
}
