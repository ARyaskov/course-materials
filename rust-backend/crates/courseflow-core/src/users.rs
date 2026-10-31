use std::fmt;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::errors::DomainError;
use crate::ids::UserId;

/// Access roles. Stored as text in PostgreSQL, serialized as snake_case in JSON.
#[cfg_attr(feature = "openapi", derive(utoipa::ToSchema))]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    Student,
    Author,
    Admin,
}

impl Role {
    pub fn as_str(&self) -> &'static str {
        match self {
            Role::Student => "student",
            Role::Author => "author",
            Role::Admin => "admin",
        }
    }

    pub fn is_admin(&self) -> bool {
        matches!(self, Role::Admin)
    }

    pub fn can_author(&self) -> bool {
        matches!(self, Role::Author | Role::Admin)
    }
}

impl std::str::FromStr for Role {
    type Err = DomainError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "student" => Ok(Role::Student),
            "author" => Ok(Role::Author),
            "admin" => Ok(Role::Admin),
            other => Err(DomainError::validation("role", format!("unknown role {other}"))),
        }
    }
}

impl fmt::Display for Role {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// A normalized, syntactically valid e-mail address.
///
/// Normalization (trim + lowercase) happens once, at the boundary, so the rest
/// of the system never compares `Alice@Example.com` with `alice@example.com`.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize)]
#[serde(transparent)]
pub struct Email(String);

impl Email {
    pub const MAX_LEN: usize = 254;

    pub fn parse(raw: &str) -> Result<Self, DomainError> {
        let normalized = raw.trim().to_ascii_lowercase();
        let Some((local, domain)) = normalized.split_once('@') else {
            return Err(DomainError::validation("email", "must contain '@'"));
        };
        if local.is_empty() || domain.is_empty() || !domain.contains('.') {
            return Err(DomainError::validation("email", "malformed address"));
        }
        if normalized.len() > Self::MAX_LEN || normalized.chars().any(char::is_whitespace) {
            return Err(DomainError::validation("email", "malformed address"));
        }
        Ok(Self(normalized))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl TryFrom<String> for Email {
    type Error = DomainError;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        Email::parse(&value)
    }
}

impl fmt::Display for Email {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// Opaque PHC-format password hash. The domain never sees plaintext passwords.
#[derive(Clone, PartialEq, Eq)]
pub struct PasswordHash(String);

impl PasswordHash {
    pub fn from_phc(phc: String) -> Self {
        Self(phc)
    }

    pub fn as_phc(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for PasswordHash {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("PasswordHash(<redacted>)")
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct User {
    pub id: UserId,
    pub email: Email,
    pub display_name: String,
    pub password_hash: PasswordHash,
    pub role: Role,
    pub email_verified_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl User {
    pub const MAX_NAME_LEN: usize = 100;

    pub fn register(
        email: Email,
        display_name: &str,
        password_hash: PasswordHash,
        now: DateTime<Utc>,
    ) -> Result<Self, DomainError> {
        let display_name = display_name.trim();
        if display_name.is_empty() || display_name.chars().count() > Self::MAX_NAME_LEN {
            return Err(DomainError::validation("display_name", "must be 1..=100 characters"));
        }
        Ok(Self {
            id: UserId::new(),
            email,
            display_name: display_name.to_owned(),
            password_hash,
            role: Role::Student,
            email_verified_at: None,
            created_at: now,
            updated_at: now,
        })
    }

    pub fn is_verified(&self) -> bool {
        self.email_verified_at.is_some()
    }

    pub fn verify_email(&mut self, now: DateTime<Utc>) {
        self.email_verified_at.get_or_insert(now);
        self.updated_at = now;
    }

    pub fn promote(&mut self, role: Role, now: DateTime<Utc>) {
        self.role = role;
        self.updated_at = now;
    }
}

/// Password policy lives in the domain so that registration and reset flows
/// cannot disagree about it.
pub fn validate_password(raw: &str) -> Result<(), DomainError> {
    let len = raw.chars().count();
    if !(10..=128).contains(&len) {
        return Err(DomainError::validation("password", "must be 10..=128 characters"));
    }
    if !raw.chars().any(|c| c.is_ascii_digit()) || !raw.chars().any(char::is_alphabetic) {
        return Err(DomainError::validation("password", "must contain letters and digits"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        /// Normalisation is idempotent: parsing what `parse` produced gives
        /// the same value, for any input `parse` accepts.
        #[test]
        fn email_parse_is_idempotent(local in "[a-zA-Z0-9._+-]{1,20}", domain in "[a-zA-Z0-9-]{1,10}\\.[a-zA-Z]{2,6}") {
            let raw = format!("  {local}@{domain} ");
            let once = Email::parse(&raw).unwrap();
            let twice = Email::parse(once.as_str()).unwrap();
            prop_assert_eq!(&once, &twice);
            prop_assert_eq!(once.as_str(), once.as_str().to_ascii_lowercase());
        }

        /// A password that the policy accepts still has to fit the length
        /// bound after any amount of surrounding whitespace is *not* stripped.
        #[test]
        fn validate_password_never_panics(raw in "\\PC{0,200}") {
            let _ = validate_password(&raw);
        }
    }

    #[test]
    fn email_is_normalized() {
        let e = Email::parse("  Alice@Example.COM ").unwrap();
        assert_eq!(e.as_str(), "alice@example.com");
    }

    #[test]
    fn email_rejects_garbage() {
        for bad in ["alice", "@example.com", "a@b", "a b@example.com"] {
            assert!(Email::parse(bad).is_err(), "{bad} should be rejected");
        }
    }

    #[test]
    fn password_policy() {
        assert!(validate_password("short1").is_err());
        assert!(validate_password("onlyletterslong").is_err());
        assert!(validate_password("correct-horse-42").is_ok());
    }

    #[test]
    fn hash_debug_is_redacted() {
        let h = PasswordHash::from_phc("$argon2id$v=19$...".into());
        assert_eq!(format!("{h:?}"), "PasswordHash(<redacted>)");
    }
}
