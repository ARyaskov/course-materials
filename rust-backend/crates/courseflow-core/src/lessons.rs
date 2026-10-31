use chrono::{DateTime, Utc};

use crate::errors::DomainError;
use crate::ids::{CourseId, LessonId};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Lesson {
    pub id: LessonId,
    pub course_id: CourseId,
    /// 1-based position inside the course; unique per course.
    pub position: i32,
    pub title: String,
    pub content_md: String,
    /// Free-preview lessons are readable without enrollment.
    pub is_free_preview: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug)]
pub struct NewLesson {
    pub course_id: CourseId,
    pub position: i32,
    pub title: String,
    pub content_md: String,
    pub is_free_preview: bool,
}

impl Lesson {
    pub const MAX_TITLE_LEN: usize = 200;
    pub const MAX_CONTENT_LEN: usize = 200_000;

    pub fn create(input: NewLesson, now: DateTime<Utc>) -> Result<Self, DomainError> {
        let title = input.title.trim().to_owned();
        if title.is_empty() || title.chars().count() > Self::MAX_TITLE_LEN {
            return Err(DomainError::validation("title", "must be 1..=200 characters"));
        }
        if input.position < 1 {
            return Err(DomainError::validation("position", "must be >= 1"));
        }
        if input.content_md.len() > Self::MAX_CONTENT_LEN {
            return Err(DomainError::validation("content_md", "content is too large"));
        }
        Ok(Self {
            id: LessonId::new(),
            course_id: input.course_id,
            position: input.position,
            title,
            content_md: input.content_md,
            is_free_preview: input.is_free_preview,
            created_at: now,
            updated_at: now,
        })
    }
}
