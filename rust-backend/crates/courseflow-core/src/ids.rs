//! Newtype identifiers. UUID v7 is time-ordered, which keeps B-tree indexes
//! append-friendly and makes ids sortable by creation time.

use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

macro_rules! id_type {
    ($name:ident) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
        #[cfg_attr(feature = "openapi", derive(utoipa::ToSchema))]
        #[serde(transparent)]
        pub struct $name(pub Uuid);

        impl $name {
            /// Generates a new time-ordered (v7) identifier.
            pub fn new() -> Self {
                Self(Uuid::now_v7())
            }

            pub fn as_uuid(&self) -> Uuid {
                self.0
            }
        }

        impl Default for $name {
            fn default() -> Self {
                Self::new()
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                write!(f, "{}", self.0)
            }
        }

        impl FromStr for $name {
            type Err = uuid::Error;

            fn from_str(s: &str) -> Result<Self, Self::Err> {
                Uuid::parse_str(s).map(Self)
            }
        }

        impl From<Uuid> for $name {
            fn from(value: Uuid) -> Self {
                Self(value)
            }
        }

        impl From<$name> for Uuid {
            fn from(value: $name) -> Self {
                value.0
            }
        }
    };
}

id_type!(UserId);
id_type!(CourseId);
id_type!(LessonId);
id_type!(EnrollmentId);
id_type!(PurchaseId);
id_type!(NotificationId);
id_type!(OutboxEventId);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn v7_ids_are_monotonic_in_practice() {
        let a = CourseId::new();
        let b = CourseId::new();
        assert!(a <= b, "v7 ids are time-ordered");
    }

    #[test]
    fn parses_and_displays_round_trip() {
        let id = UserId::new();
        let parsed: UserId = id.to_string().parse().unwrap();
        assert_eq!(id, parsed);
    }
}
