use chrono::{DateTime, Utc};
use courseflow_core::courses::{Course, CourseStatus, CourseTitle};
use courseflow_core::ids::{CourseId, UserId};
use courseflow_core::money::{Currency, Money};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};

use crate::http::error::FieldError;
use crate::http::extractors::validated::{Errors, Validate};

#[derive(Debug, Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct CreateCourseRequest {
    #[schema(example = "Rust Backend 2026")]
    pub title: String,
    #[serde(default)]
    pub description: String,
    /// Price with at most two decimals; `0` makes the course free.
    #[schema(value_type = String, example = "49.00")]
    pub price: Decimal,
    #[serde(default = "default_currency")]
    pub currency: Currency,
}

fn default_currency() -> Currency {
    Currency::Usd
}

impl Validate for CreateCourseRequest {
    fn validate(&self) -> Vec<FieldError> {
        let mut e = Errors::default();
        if let Err(err) = CourseTitle::parse(&self.title) {
            e.push("title", err.to_string());
        }
        e.check(
            self.description.chars().count() <= Course::MAX_DESCRIPTION_LEN,
            "description",
            "must be at most 5000 characters",
        );
        e.check(!self.price.is_sign_negative(), "price", "must not be negative");
        e.check(self.price.scale() <= 2, "price", "at most two decimal places");
        e.into_vec()
    }
}

impl CreateCourseRequest {
    pub fn into_new_course(
        self,
        author_id: UserId,
    ) -> Result<courseflow_core::courses::NewCourse, courseflow_core::DomainError> {
        Ok(courseflow_core::courses::NewCourse {
            author_id,
            title: CourseTitle::parse(&self.title)?,
            description: self.description,
            price: Money::new(self.price, self.currency)?,
        })
    }
}

/// PATCH semantics: absent field = unchanged. `Option<Option<T>>` would be
/// needed to distinguish "unset" from "set to null"; no nullable field here.
#[derive(Debug, Deserialize, ToSchema, Default)]
#[serde(deny_unknown_fields)]
pub struct UpdateCourseRequest {
    pub title: Option<String>,
    pub description: Option<String>,
    #[schema(value_type = Option<String>)]
    pub price: Option<Decimal>,
    pub currency: Option<Currency>,
}

impl Validate for UpdateCourseRequest {
    fn validate(&self) -> Vec<FieldError> {
        let mut e = Errors::default();
        if let Some(title) = &self.title
            && let Err(err) = CourseTitle::parse(title)
        {
            e.push("title", err.to_string());
        }
        if let Some(price) = self.price {
            e.check(
                !price.is_sign_negative() && price.scale() <= 2,
                "price",
                "must be a non-negative amount with two decimals",
            );
        }
        e.check(
            self.title.is_some() || self.description.is_some() || self.price.is_some(),
            "body",
            "nothing to update",
        );
        e.into_vec()
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct CourseResponse {
    pub id: CourseId,
    pub author_id: UserId,
    pub title: String,
    pub slug: String,
    pub description: String,
    #[schema(value_type = String)]
    pub price: Decimal,
    pub currency: Currency,
    pub status: CourseStatus,
    pub version: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub published_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl From<Course> for CourseResponse {
    fn from(c: Course) -> Self {
        Self {
            id: c.id,
            author_id: c.author_id,
            title: c.title.to_string(),
            slug: c.slug.to_string(),
            description: c.description,
            price: c.price.amount(),
            currency: c.price.currency(),
            status: c.status,
            version: c.version,
            published_at: c.published_at,
            created_at: c.created_at,
            updated_at: c.updated_at,
        }
    }
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct CourseListQuery {
    /// Case-insensitive substring match on the title.
    pub search: Option<String>,
    pub author_id: Option<UserId>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct MyCoursesQuery {
    pub status: Option<CourseStatus>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct PageResponse<T> {
    pub items: Vec<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_cursor: Option<String>,
}

impl<T> PageResponse<T> {
    pub fn from_page<U: Into<T>>(page: courseflow_app::shared::pagination::Page<U>) -> Self {
        Self {
            items: page.items.into_iter().map(Into::into).collect(),
            next_cursor: page.next_cursor.map(|c| c.encode()),
        }
    }
}
