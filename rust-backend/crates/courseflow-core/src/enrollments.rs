use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::ids::{CourseId, EnrollmentId, PurchaseId, UserId};

/// How the student got access. Paid access references the purchase; grants are
/// issued by admins (support cases, promo codes).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum EnrollmentSource {
    Purchase { purchase_id: PurchaseId },
    Grant { granted_by: UserId },
    Free,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Enrollment {
    pub id: EnrollmentId,
    pub user_id: UserId,
    pub course_id: CourseId,
    pub source: EnrollmentSource,
    pub created_at: DateTime<Utc>,
}

impl Enrollment {
    pub fn new(user_id: UserId, course_id: CourseId, source: EnrollmentSource, now: DateTime<Utc>) -> Self {
        Self { id: EnrollmentId::new(), user_id, course_id, source, created_at: now }
    }
}
