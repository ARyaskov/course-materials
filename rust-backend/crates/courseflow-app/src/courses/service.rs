use std::sync::Arc;

use courseflow_core::courses::{Course, CourseStatus, CourseTitle, NewCourse};
use courseflow_core::ids::{CourseId, UserId};
use courseflow_core::money::Money;
use courseflow_core::policy::{self, Actor};
use courseflow_core::ports::Clock;
use sqlx::PgPool;

use crate::cache::CourseCache;
use crate::courses::repo::{self, ListFilter};
use crate::errors::{AppError, AppResult};
use crate::shared::pagination::{Page, PageRequest};

#[derive(Debug, Clone, Default)]
pub struct CourseFilter {
    pub status: Option<CourseStatus>,
    pub author_id: Option<UserId>,
    pub search: Option<String>,
}

#[derive(Debug, Default)]
pub struct UpdateCourse {
    pub title: Option<CourseTitle>,
    pub description: Option<String>,
    pub price: Option<Money>,
}

#[derive(Clone)]
pub struct CourseService {
    pool: PgPool,
    clock: Arc<dyn Clock>,
    cache: CourseCache,
}

impl std::fmt::Debug for CourseService {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("CourseService")
    }
}

impl CourseService {
    pub fn new(pool: PgPool, clock: Arc<dyn Clock>, cache: CourseCache) -> Self {
        Self { pool, clock, cache }
    }

    #[tracing::instrument(skip(self, input), fields(actor = %actor.id))]
    pub async fn create(&self, actor: &Actor, input: NewCourse) -> AppResult<Course> {
        policy::require_author(actor)?;
        if input.author_id != actor.id {
            policy::require_admin(actor)?;
        }
        let course = Course::create(input, self.clock.now())?;
        repo::insert(&self.pool, &course).await?;
        tracing::info!(course_id = %course.id, "course created");
        Ok(course)
    }

    /// Public read: published courses are cached; drafts go to the database
    /// and are only visible to their owner.
    #[tracing::instrument(skip(self))]
    pub async fn get(&self, actor: Option<&Actor>, id: CourseId) -> AppResult<Course> {
        if let Some(course) = self.cache.get(id).await
            && course.is_published()
        {
            return Ok(course);
        }
        let course = repo::find_by_id(&self.pool, id).await?.ok_or(AppError::not_found("course"))?;
        if !policy::can_view_course(actor, &course) {
            // A draft must look like it does not exist to strangers.
            return Err(AppError::not_found("course"));
        }
        if course.is_published() {
            self.cache.put(&course).await;
        }
        Ok(course)
    }

    #[tracing::instrument(skip(self))]
    pub async fn list_public(&self, filter: CourseFilter, page: PageRequest) -> AppResult<Page<Course>> {
        let filter =
            ListFilter { status: Some(CourseStatus::Published), author_id: filter.author_id, search: filter.search };
        repo::list(&self.pool, &filter, page).await
    }

    #[tracing::instrument(skip(self))]
    pub async fn list_mine(
        &self,
        actor: &Actor,
        status: Option<CourseStatus>,
        page: PageRequest,
    ) -> AppResult<Page<Course>> {
        policy::require_author(actor)?;
        let filter = ListFilter { status, author_id: Some(actor.id), search: None };
        repo::list(&self.pool, &filter, page).await
    }

    #[tracing::instrument(skip(self, changes))]
    pub async fn update(&self, actor: &Actor, id: CourseId, changes: UpdateCourse) -> AppResult<Course> {
        let mut course = repo::find_by_id(&self.pool, id).await?.ok_or(AppError::not_found("course"))?;
        policy::require_course_owner(actor, &course)?;
        course.update_details(changes.title, changes.description, changes.price, self.clock.now())?;
        let course = repo::update(&self.pool, &course).await?;
        self.cache.invalidate(id).await;
        Ok(course)
    }

    /// Read-modify-write under a row lock: two concurrent publish requests
    /// cannot both pass the "at least one lesson" check on stale data.
    #[tracing::instrument(skip(self))]
    pub async fn publish(&self, actor: &Actor, id: CourseId) -> AppResult<Course> {
        let mut tx = self.pool.begin().await?;
        let mut course = repo::find_by_id_for_update(&mut *tx, id).await?.ok_or(AppError::not_found("course"))?;
        policy::require_course_owner(actor, &course)?;
        let lessons = repo::count_lessons(&mut *tx, id).await?;
        course.publish(lessons as usize, self.clock.now())?;
        let course = repo::update(&mut *tx, &course).await?;
        tx.commit().await?;
        self.cache.invalidate(id).await;
        tracing::info!(course_id = %id, "course published");
        Ok(course)
    }

    #[tracing::instrument(skip(self))]
    pub async fn archive(&self, actor: &Actor, id: CourseId) -> AppResult<Course> {
        let mut course = repo::find_by_id(&self.pool, id).await?.ok_or(AppError::not_found("course"))?;
        policy::require_course_owner(actor, &course)?;
        course.archive(self.clock.now())?;
        let course = repo::update(&self.pool, &course).await?;
        self.cache.invalidate(id).await;
        Ok(course)
    }

    #[tracing::instrument(skip(self))]
    pub async fn delete_draft(&self, actor: &Actor, id: CourseId) -> AppResult<()> {
        let course = repo::find_by_id(&self.pool, id).await?.ok_or(AppError::not_found("course"))?;
        policy::require_course_owner(actor, &course)?;
        if course.status != CourseStatus::Draft {
            return Err(AppError::conflict("only drafts can be deleted; archive published courses instead"));
        }
        repo::delete_draft(&self.pool, id).await?;
        Ok(())
    }
}
