use chrono::{DateTime, Utc};

use crate::ids::{CourseId, LessonId, UserId};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LessonProgress {
    pub user_id: UserId,
    pub lesson_id: LessonId,
    pub completed_at: DateTime<Utc>,
}

/// Aggregated view over a course: pure arithmetic, trivially unit-testable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CourseProgress {
    pub course_id: CourseId,
    pub completed_lessons: u32,
    pub total_lessons: u32,
}

impl CourseProgress {
    pub fn percent(&self) -> u8 {
        if self.total_lessons == 0 {
            return 0;
        }
        let pct = (u64::from(self.completed_lessons) * 100) / u64::from(self.total_lessons);
        // completed can never exceed total, but a stale read must not panic
        pct.min(100) as u8
    }

    pub fn is_complete(&self) -> bool {
        self.total_lessons > 0 && self.completed_lessons >= self.total_lessons
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Certificate {
    pub user_id: UserId,
    pub course_id: CourseId,
    pub issued_at: DateTime<Utc>,
    /// Public verification code, e.g. `CF-7Q2M-9K1X`.
    pub code: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn percent_math() {
        let p = CourseProgress { course_id: CourseId::new(), completed_lessons: 1, total_lessons: 3 };
        assert_eq!(p.percent(), 33);
        assert!(!p.is_complete());
        let done = CourseProgress { completed_lessons: 3, ..p };
        assert_eq!(done.percent(), 100);
        assert!(done.is_complete());
        let empty = CourseProgress { completed_lessons: 0, total_lessons: 0, ..p };
        assert_eq!(empty.percent(), 0);
        assert!(!empty.is_complete());
    }
}
