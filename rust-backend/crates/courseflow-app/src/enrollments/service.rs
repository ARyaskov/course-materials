use std::sync::Arc;

use courseflow_core::enrollments::{Enrollment, EnrollmentSource};
use courseflow_core::ids::{CourseId, UserId};
use courseflow_core::policy::{self, Actor};
use courseflow_core::ports::Clock;
use sqlx::PgPool;

use crate::courses::repo as courses;
use crate::enrollments::repo;
use crate::errors::{AppError, AppResult};

#[derive(Clone)]
pub struct EnrollmentService {
    pool: PgPool,
    clock: Arc<dyn Clock>,
}

impl std::fmt::Debug for EnrollmentService {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("EnrollmentService")
    }
}

impl EnrollmentService {
    pub fn new(pool: PgPool, clock: Arc<dyn Clock>) -> Self {
        Self { pool, clock }
    }

    /// Free courses are joined directly; paid ones go through `BillingService`.
    #[tracing::instrument(skip(self), fields(actor = %actor.id))]
    pub async fn enroll_free(&self, actor: &Actor, course_id: CourseId) -> AppResult<Enrollment> {
        let course = courses::find_by_id(&self.pool, course_id).await?.ok_or(AppError::not_found("course"))?;
        if !course.is_published() {
            return Err(AppError::not_found("course"));
        }
        if !course.price.is_free() {
            return Err(AppError::conflict("this course requires a purchase"));
        }
        let enrollment = Enrollment::new(actor.id, course_id, EnrollmentSource::Free, self.clock.now());
        repo::insert(&self.pool, &enrollment).await?;
        Ok(enrollment)
    }

    /// Admin grant: support case, promo, refund goodwill.
    #[tracing::instrument(skip(self))]
    pub async fn grant(&self, actor: &Actor, user_id: UserId, course_id: CourseId) -> AppResult<Enrollment> {
        policy::require_admin(actor)?;
        courses::find_by_id(&self.pool, course_id).await?.ok_or(AppError::not_found("course"))?;
        let enrollment =
            Enrollment::new(user_id, course_id, EnrollmentSource::Grant { granted_by: actor.id }, self.clock.now());
        repo::insert(&self.pool, &enrollment).await?;
        Ok(enrollment)
    }

    pub async fn list_mine(&self, actor: &Actor) -> AppResult<Vec<Enrollment>> {
        repo::list_for_user(&self.pool, actor.id).await
    }

    pub async fn is_enrolled(&self, user_id: UserId, course_id: CourseId) -> AppResult<bool> {
        repo::exists(&self.pool, user_id, course_id).await
    }
}
