use std::fmt;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::errors::DomainError;
use crate::ids::{CourseId, UserId};
use crate::money::Money;

#[cfg_attr(feature = "openapi", derive(utoipa::ToSchema))]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CourseStatus {
    Draft,
    Published,
    Archived,
}

impl CourseStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            CourseStatus::Draft => "draft",
            CourseStatus::Published => "published",
            CourseStatus::Archived => "archived",
        }
    }
}

impl std::str::FromStr for CourseStatus {
    type Err = DomainError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "draft" => Ok(CourseStatus::Draft),
            "published" => Ok(CourseStatus::Published),
            "archived" => Ok(CourseStatus::Archived),
            other => Err(DomainError::validation("status", format!("unknown status {other}"))),
        }
    }
}

impl fmt::Display for CourseStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Non-empty, trimmed title with a length limit. Constructed only through
/// `parse`, so a `CourseTitle` in a struct is always valid.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(transparent)]
pub struct CourseTitle(String);

impl CourseTitle {
    pub const MAX_LEN: usize = 200;

    pub fn parse(raw: &str) -> Result<Self, DomainError> {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            return Err(DomainError::validation("title", "must not be empty"));
        }
        if trimmed.chars().count() > Self::MAX_LEN {
            return Err(DomainError::validation("title", "must be at most 200 characters"));
        }
        Ok(Self(trimmed.to_owned()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl TryFrom<String> for CourseTitle {
    type Error = DomainError;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        CourseTitle::parse(&value)
    }
}

impl fmt::Display for CourseTitle {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// URL-friendly identifier derived from the title: `rust-backend-2026`.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize)]
#[serde(transparent)]
pub struct Slug(String);

impl Slug {
    pub const MAX_LEN: usize = 80;

    pub fn from_title(title: &CourseTitle) -> Self {
        let mut out = String::with_capacity(title.as_str().len());
        let mut prev_dash = true;
        for ch in title.as_str().chars() {
            let ch = ch.to_ascii_lowercase();
            if ch.is_ascii_alphanumeric() {
                out.push(ch);
                prev_dash = false;
            } else if !prev_dash {
                out.push('-');
                prev_dash = true;
            }
        }
        // `parse` caps a slug at MAX_LEN; a 200-character title must still
        // produce something `parse` accepts when the row is read back.
        if out.len() > Self::MAX_LEN {
            out.truncate(Self::MAX_LEN);
        }
        let trimmed = out.trim_end_matches('-');
        Self(if trimmed.is_empty() { "course".to_owned() } else { trimmed.to_owned() })
    }

    pub fn parse(raw: &str) -> Result<Self, DomainError> {
        let ok = !raw.is_empty()
            && raw.len() <= Self::MAX_LEN
            && raw.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
            && !raw.starts_with('-')
            && !raw.ends_with('-');
        if ok {
            Ok(Self(raw.to_owned()))
        } else {
            Err(DomainError::validation("slug", "lowercase letters, digits and dashes only"))
        }
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for Slug {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Course {
    pub id: CourseId,
    pub author_id: UserId,
    pub title: CourseTitle,
    pub slug: Slug,
    pub description: String,
    pub price: Money,
    pub status: CourseStatus,
    /// Optimistic-locking version, incremented on every persisted change.
    pub version: i32,
    pub published_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug)]
pub struct NewCourse {
    pub author_id: UserId,
    pub title: CourseTitle,
    pub description: String,
    pub price: Money,
}

impl Course {
    pub const MAX_DESCRIPTION_LEN: usize = 5_000;

    pub fn create(input: NewCourse, now: DateTime<Utc>) -> Result<Self, DomainError> {
        if input.description.chars().count() > Self::MAX_DESCRIPTION_LEN {
            return Err(DomainError::validation("description", "must be at most 5000 characters"));
        }
        let slug = Slug::from_title(&input.title);
        Ok(Self {
            id: CourseId::new(),
            author_id: input.author_id,
            title: input.title,
            slug,
            description: input.description,
            price: input.price,
            status: CourseStatus::Draft,
            version: 1,
            published_at: None,
            created_at: now,
            updated_at: now,
        })
    }

    pub fn is_published(&self) -> bool {
        self.status == CourseStatus::Published
    }

    pub fn is_owned_by(&self, user: UserId) -> bool {
        self.author_id == user
    }

    /// Draft → Published. A course without lessons cannot be published: that
    /// invariant is checked here, with the lesson count supplied by the caller.
    pub fn publish(&mut self, lesson_count: usize, now: DateTime<Utc>) -> Result<(), DomainError> {
        match self.status {
            CourseStatus::Draft => {}
            from => {
                return Err(DomainError::InvalidTransition { entity: "course", from: from.as_str(), to: "published" });
            }
        }
        if lesson_count == 0 {
            return Err(DomainError::rule("a course needs at least one lesson to be published"));
        }
        self.status = CourseStatus::Published;
        self.published_at = Some(now);
        self.updated_at = now;
        Ok(())
    }

    /// Published → Archived. Drafts are deleted, not archived.
    pub fn archive(&mut self, now: DateTime<Utc>) -> Result<(), DomainError> {
        if self.status != CourseStatus::Published {
            return Err(DomainError::InvalidTransition {
                entity: "course",
                from: self.status.as_str(),
                to: "archived",
            });
        }
        self.status = CourseStatus::Archived;
        self.updated_at = now;
        Ok(())
    }

    pub fn update_details(
        &mut self,
        title: Option<CourseTitle>,
        description: Option<String>,
        price: Option<Money>,
        now: DateTime<Utc>,
    ) -> Result<(), DomainError> {
        if self.status == CourseStatus::Archived {
            return Err(DomainError::rule("archived course cannot be edited"));
        }
        if let Some(description) = &description
            && description.chars().count() > Self::MAX_DESCRIPTION_LEN
        {
            return Err(DomainError::validation("description", "must be at most 5000 characters"));
        }
        if let Some(title) = title {
            self.slug = Slug::from_title(&title);
            self.title = title;
        }
        if let Some(description) = description {
            self.description = description;
        }
        if let Some(price) = price {
            self.price = price;
        }
        self.updated_at = now;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        /// Whatever the title, the slug is non-empty, lowercase ASCII with
        /// single dashes and no dash at either end — and it round-trips
        /// through `Slug::parse`, i.e. it is a valid slug by construction.
        #[test]
        fn slug_from_title_is_always_valid(title in "[\\PC ]{1,200}") {
            let Ok(title) = CourseTitle::parse(&title) else { return Ok(()) };
            let slug = Slug::from_title(&title);
            let s = slug.as_str();
            prop_assert!(!s.is_empty());
            prop_assert!(s.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-'));
            prop_assert!(!s.starts_with('-') && !s.ends_with('-') && !s.contains("--"));
            let reparsed = Slug::parse(s).unwrap();
            prop_assert_eq!(reparsed.as_str(), s);
        }
    }
    use crate::money::Currency;

    fn course() -> Course {
        Course::create(
            NewCourse {
                author_id: UserId::new(),
                title: CourseTitle::parse("Rust Backend 2026: Axum & SQLx").unwrap(),
                description: String::new(),
                price: Money::free(Currency::Usd),
            },
            Utc::now(),
        )
        .unwrap()
    }

    #[test]
    fn slug_from_title() {
        assert_eq!(course().slug.as_str(), "rust-backend-2026-axum-sqlx");
    }

    #[test]
    fn publish_requires_lessons() {
        let mut c = course();
        assert!(matches!(c.publish(0, Utc::now()), Err(DomainError::RuleViolation(_))));
        c.publish(3, Utc::now()).unwrap();
        assert!(c.is_published());
        assert!(matches!(c.publish(3, Utc::now()), Err(DomainError::InvalidTransition { .. })));
    }

    #[test]
    fn archive_only_published() {
        let mut c = course();
        assert!(c.archive(Utc::now()).is_err());
        c.publish(1, Utc::now()).unwrap();
        c.archive(Utc::now()).unwrap();
        assert!(c.update_details(None, Some("x".into()), None, Utc::now()).is_err());
    }
}
