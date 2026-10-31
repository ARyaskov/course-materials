//! Cache-aside for published courses. Errors are logged and swallowed: the
//! database is the source of truth, Redis only makes it cheaper to read.

use std::time::Duration;

use courseflow_core::courses::Course;
use courseflow_core::ids::CourseId;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};

use crate::cache::RedisHandle;

/// Cache representation is versioned separately from the API DTO: changing
/// either one must not silently corrupt the other.
#[derive(Debug, Serialize, Deserialize)]
struct CachedCourse {
    id: CourseId,
    author_id: courseflow_core::ids::UserId,
    title: String,
    slug: String,
    description: String,
    price_amount: rust_decimal::Decimal,
    currency: courseflow_core::money::Currency,
    status: courseflow_core::courses::CourseStatus,
    version: i32,
    published_at: Option<chrono::DateTime<chrono::Utc>>,
    created_at: chrono::DateTime<chrono::Utc>,
    updated_at: chrono::DateTime<chrono::Utc>,
}

impl From<&Course> for CachedCourse {
    fn from(c: &Course) -> Self {
        Self {
            id: c.id,
            author_id: c.author_id,
            title: c.title.as_str().to_owned(),
            slug: c.slug.as_str().to_owned(),
            description: c.description.clone(),
            price_amount: c.price.amount(),
            currency: c.price.currency(),
            status: c.status,
            version: c.version,
            published_at: c.published_at,
            created_at: c.created_at,
            updated_at: c.updated_at,
        }
    }
}

impl TryFrom<CachedCourse> for Course {
    type Error = courseflow_core::DomainError;

    fn try_from(c: CachedCourse) -> Result<Self, Self::Error> {
        Ok(Course {
            id: c.id,
            author_id: c.author_id,
            title: courseflow_core::courses::CourseTitle::parse(&c.title)?,
            slug: courseflow_core::courses::Slug::parse(&c.slug)?,
            description: c.description,
            price: courseflow_core::money::Money::new(c.price_amount, c.currency)?,
            status: c.status,
            version: c.version,
            published_at: c.published_at,
            created_at: c.created_at,
            updated_at: c.updated_at,
        })
    }
}

#[derive(Debug, Clone)]
pub struct CourseCache {
    redis: Option<RedisHandle>,
    ttl: Duration,
}

impl CourseCache {
    /// Key schema version: bump when `CachedCourse` changes shape.
    const VERSION: &'static str = "v1";

    pub fn new(redis: Option<RedisHandle>, ttl: Duration) -> Self {
        Self { redis, ttl }
    }

    pub fn disabled() -> Self {
        Self { redis: None, ttl: Duration::ZERO }
    }

    fn key(&self, redis: &RedisHandle, id: CourseId) -> String {
        redis.key(&["course", Self::VERSION, &id.to_string()])
    }

    pub async fn get(&self, id: CourseId) -> Option<Course> {
        let redis = self.redis.as_ref()?;
        let mut conn = redis.conn();
        let key = self.key(redis, id);
        match conn.get::<_, Option<String>>(&key).await {
            Ok(Some(json)) => match serde_json::from_str::<CachedCourse>(&json).map(Course::try_from) {
                Ok(Ok(course)) => {
                    metrics::counter!("courseflow_cache_hits_total", "cache" => "course").increment(1);
                    Some(course)
                }
                _ => {
                    tracing::warn!(%key, "corrupt cache entry, dropping");
                    let _ = conn.del::<_, ()>(&key).await;
                    None
                }
            },
            Ok(None) => {
                metrics::counter!("courseflow_cache_misses_total", "cache" => "course").increment(1);
                None
            }
            Err(err) => {
                tracing::warn!(error = %err, "cache read failed, falling back to database");
                None
            }
        }
    }

    pub async fn put(&self, course: &Course) {
        let Some(redis) = &self.redis else { return };
        let Ok(json) = serde_json::to_string(&CachedCourse::from(course)) else { return };
        let mut conn = redis.conn();
        let key = self.key(redis, course.id);
        // Jitter spreads expirations so that a popular list does not expire all at once.
        let ttl = self.ttl.as_secs() + u64::from(course.id.0.as_u128() as u8 % 30);
        if let Err(err) = conn.set_ex::<_, _, ()>(&key, json, ttl).await {
            tracing::warn!(error = %err, "cache write failed");
        }
    }

    /// Invalidation = delete, never "update": the next reader repopulates
    /// from the database and there is no stale-write race.
    pub async fn invalidate(&self, id: CourseId) {
        let Some(redis) = &self.redis else { return };
        let mut conn = redis.conn();
        let key = self.key(redis, id);
        if let Err(err) = conn.del::<_, ()>(&key).await {
            tracing::warn!(error = %err, "cache invalidation failed");
        }
    }
}
