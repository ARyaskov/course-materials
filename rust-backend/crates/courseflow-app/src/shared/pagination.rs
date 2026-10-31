//! Keyset (cursor) pagination over `(created_at DESC, id DESC)`. Stable under
//! inserts, no `OFFSET` scans, and the cursor is opaque to clients.

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::errors::AppError;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Cursor {
    pub created_at: DateTime<Utc>,
    pub id: Uuid,
}

impl Cursor {
    pub fn encode(&self) -> String {
        // serde_json on a two-field struct cannot fail
        let json = serde_json::to_vec(self).unwrap_or_default();
        URL_SAFE_NO_PAD.encode(json)
    }

    pub fn decode(raw: &str) -> Result<Self, AppError> {
        let bytes = URL_SAFE_NO_PAD
            .decode(raw)
            .map_err(|_| AppError::Domain(courseflow_core::DomainError::validation("cursor", "malformed cursor")))?;
        serde_json::from_slice(&bytes)
            .map_err(|_| AppError::Domain(courseflow_core::DomainError::validation("cursor", "malformed cursor")))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PageRequest {
    pub limit: i64,
    pub after: Option<Cursor>,
}

impl PageRequest {
    pub const DEFAULT_LIMIT: i64 = 20;
    pub const MAX_LIMIT: i64 = 100;

    pub fn new(limit: Option<i64>, after: Option<Cursor>) -> Result<Self, AppError> {
        let limit = limit.unwrap_or(Self::DEFAULT_LIMIT);
        if !(1..=Self::MAX_LIMIT).contains(&limit) {
            return Err(AppError::Domain(courseflow_core::DomainError::validation("limit", "must be 1..=100")));
        }
        Ok(Self { limit, after })
    }

    pub fn first(limit: i64) -> Self {
        Self { limit, after: None }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Page<T> {
    pub items: Vec<T>,
    pub next_cursor: Option<Cursor>,
}

impl<T> Page<T> {
    /// Repositories fetch `limit + 1` rows; the extra row tells whether a next
    /// page exists without a `COUNT(*)`.
    pub fn from_overfetched(mut rows: Vec<T>, limit: i64, cursor_of: impl Fn(&T) -> Cursor) -> Self {
        let has_more = rows.len() as i64 > limit;
        if has_more {
            rows.truncate(limit as usize);
        }
        let next_cursor = if has_more { rows.last().map(cursor_of) } else { None };
        Self { items: rows, next_cursor }
    }

    pub fn map<U>(self, f: impl FnMut(T) -> U) -> Page<U> {
        Page { items: self.items.into_iter().map(f).collect(), next_cursor: self.next_cursor }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cursor_round_trip() {
        let c = Cursor { created_at: Utc::now(), id: Uuid::now_v7() };
        assert_eq!(Cursor::decode(&c.encode()).unwrap(), c);
        assert!(Cursor::decode("not-a-cursor").is_err());
    }

    #[test]
    fn overfetch_detects_next_page() {
        let rows: Vec<i32> = (1..=4).collect();
        let page = Page::from_overfetched(rows, 3, |_| Cursor { created_at: Utc::now(), id: Uuid::nil() });
        assert_eq!(page.items, vec![1, 2, 3]);
        assert!(page.next_cursor.is_some());
        let page = Page::from_overfetched(vec![1, 2], 3, |_| Cursor { created_at: Utc::now(), id: Uuid::nil() });
        assert!(page.next_cursor.is_none());
    }
}
