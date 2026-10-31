use chrono::{DateTime, Utc};
use courseflow_core::courses::{Course, CourseStatus, CourseTitle, Slug};
use courseflow_core::ids::{CourseId, UserId};
use courseflow_core::money::{Currency, Money};
use rust_decimal::Decimal;
use sqlx::{PgExecutor, Postgres, QueryBuilder};
use uuid::Uuid;

use crate::errors::{AppError, AppResult};
use crate::shared::pagination::{Cursor, Page, PageRequest};

#[derive(Debug, sqlx::FromRow)]
struct CourseRow {
    id: Uuid,
    author_id: Uuid,
    title: String,
    slug: String,
    description: String,
    price_amount: Decimal,
    currency: String,
    status: String,
    version: i32,
    published_at: Option<DateTime<Utc>>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

impl TryFrom<CourseRow> for Course {
    type Error = AppError;

    fn try_from(r: CourseRow) -> Result<Self, Self::Error> {
        Ok(Course {
            id: CourseId(r.id),
            author_id: UserId(r.author_id),
            title: CourseTitle::parse(&r.title)?,
            slug: Slug::parse(&r.slug)?,
            description: r.description,
            price: Money::new(r.price_amount, r.currency.parse::<Currency>()?)?,
            status: r.status.parse::<CourseStatus>()?,
            version: r.version,
            published_at: r.published_at,
            created_at: r.created_at,
            updated_at: r.updated_at,
        })
    }
}

const COLUMNS: &str = "id, author_id, title, slug, description, price_amount, currency, status, version, published_at, created_at, updated_at";

pub async fn insert(executor: impl PgExecutor<'_>, course: &Course) -> AppResult<()> {
    sqlx::query!(
        r#"INSERT INTO courses (id, author_id, title, slug, description, price_amount, currency, status, version, published_at, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)"#,
        course.id.0,
        course.author_id.0,
        course.title.as_str(),
        course.slug.as_str(),
        course.description,
        course.price.amount(),
        course.price.currency().as_str(),
        course.status.as_str(),
        course.version,
        course.published_at,
        course.created_at,
        course.updated_at,
    )
    .execute(executor)
    .await?;
    Ok(())
}

pub async fn find_by_id(executor: impl PgExecutor<'_>, id: CourseId) -> AppResult<Option<Course>> {
    let row = sqlx::query_as!(
        CourseRow,
        r#"SELECT id, author_id, title, slug, description, price_amount, currency, status, version, published_at, created_at, updated_at
           FROM courses WHERE id = $1"#,
        id.0
    )
    .fetch_optional(executor)
    .await?;
    row.map(Course::try_from).transpose()
}

/// Same as `find_by_id` but takes a row lock for the rest of the transaction:
/// used by use cases that read-modify-write a course.
pub async fn find_by_id_for_update(executor: impl PgExecutor<'_>, id: CourseId) -> AppResult<Option<Course>> {
    let row = sqlx::query_as!(
        CourseRow,
        r#"SELECT id, author_id, title, slug, description, price_amount, currency, status, version, published_at, created_at, updated_at
           FROM courses WHERE id = $1 FOR UPDATE"#,
        id.0
    )
    .fetch_optional(executor)
    .await?;
    row.map(Course::try_from).transpose()
}

/// Optimistic locking: the row is updated only if nobody else bumped
/// `version` since we read it. Zero rows affected means a lost update was
/// prevented and the caller should report a conflict.
pub async fn update(executor: impl PgExecutor<'_>, course: &Course) -> AppResult<Course> {
    let row = sqlx::query_as!(
        CourseRow,
        r#"UPDATE courses
           SET title = $2, slug = $3, description = $4, price_amount = $5, currency = $6, status = $7,
               published_at = $8, updated_at = $9, version = version + 1
           WHERE id = $1 AND version = $10
           RETURNING id, author_id, title, slug, description, price_amount, currency, status, version, published_at, created_at, updated_at"#,
        course.id.0,
        course.title.as_str(),
        course.slug.as_str(),
        course.description,
        course.price.amount(),
        course.price.currency().as_str(),
        course.status.as_str(),
        course.published_at,
        course.updated_at,
        course.version,
    )
    .fetch_optional(executor)
    .await?;
    match row {
        Some(row) => Course::try_from(row),
        None => Err(AppError::conflict("course was modified concurrently")),
    }
}

pub async fn delete_draft(executor: impl PgExecutor<'_>, id: CourseId) -> AppResult<bool> {
    let r = sqlx::query!("DELETE FROM courses WHERE id = $1 AND status = 'draft'", id.0).execute(executor).await?;
    Ok(r.rows_affected() == 1)
}

#[derive(Debug, Clone, Default)]
pub struct ListFilter {
    pub status: Option<CourseStatus>,
    pub author_id: Option<UserId>,
    pub search: Option<String>,
}

/// Dynamic filtering with `QueryBuilder`: every user value goes through
/// `push_bind`, never through string formatting.
pub async fn list(executor: impl PgExecutor<'_>, filter: &ListFilter, page: PageRequest) -> AppResult<Page<Course>> {
    let mut qb: QueryBuilder<Postgres> = QueryBuilder::new(format!("SELECT {COLUMNS} FROM courses WHERE 1 = 1"));
    if let Some(status) = filter.status {
        qb.push(" AND status = ").push_bind(status.as_str());
    }
    if let Some(author) = filter.author_id {
        qb.push(" AND author_id = ").push_bind(author.0);
    }
    if let Some(search) = filter.search.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        qb.push(" AND title ILIKE ").push_bind(format!("%{}%", search.replace(['%', '_'], "")));
    }
    if let Some(after) = page.after {
        qb.push(" AND (created_at, id) < (").push_bind(after.created_at).push(", ").push_bind(after.id).push(")");
    }
    qb.push(" ORDER BY created_at DESC, id DESC LIMIT ").push_bind(page.limit + 1);

    let rows: Vec<CourseRow> = qb.build_query_as().fetch_all(executor).await?;
    let courses = rows.into_iter().map(Course::try_from).collect::<Result<Vec<_>, _>>()?;
    Ok(Page::from_overfetched(courses, page.limit, |c| Cursor { created_at: c.created_at, id: c.id.0 }))
}

pub async fn count_lessons(executor: impl PgExecutor<'_>, course_id: CourseId) -> AppResult<i64> {
    let n = sqlx::query_scalar!(r#"SELECT count(*) AS "count!" FROM lessons WHERE course_id = $1"#, course_id.0)
        .fetch_one(executor)
        .await?;
    Ok(n)
}
