//! Authorization rules as pure functions: easy to test, impossible to forget
//! in one handler and remember in another.

use crate::courses::Course;
use crate::errors::DomainError;
use crate::ids::UserId;
use crate::users::Role;

/// The authenticated principal as seen by the domain: no HTTP, no tokens.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Actor {
    pub id: UserId,
    pub role: Role,
}

impl Actor {
    pub fn new(id: UserId, role: Role) -> Self {
        Self { id, role }
    }
}

pub fn require_author(actor: &Actor) -> Result<(), DomainError> {
    if actor.role.can_author() { Ok(()) } else { Err(DomainError::PermissionDenied("author role required")) }
}

pub fn require_admin(actor: &Actor) -> Result<(), DomainError> {
    if actor.role.is_admin() { Ok(()) } else { Err(DomainError::PermissionDenied("admin role required")) }
}

/// Authors edit only their own courses; admins edit anything.
pub fn require_course_owner(actor: &Actor, course: &Course) -> Result<(), DomainError> {
    if actor.role.is_admin() || course.is_owned_by(actor.id) {
        Ok(())
    } else {
        Err(DomainError::PermissionDenied("not the course owner"))
    }
}

/// Reading a course: published courses are public; drafts are visible to the
/// owner and admins only.
pub fn can_view_course(actor: Option<&Actor>, course: &Course) -> bool {
    course.is_published() || actor.is_some_and(|a| require_course_owner(a, course).is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::courses::{CourseTitle, NewCourse};
    use crate::money::{Currency, Money};
    use chrono::Utc;

    fn course_of(author: UserId) -> Course {
        Course::create(
            NewCourse {
                author_id: author,
                title: CourseTitle::parse("x").unwrap(),
                description: String::new(),
                price: Money::free(Currency::Usd),
            },
            Utc::now(),
        )
        .unwrap()
    }

    #[test]
    fn owner_and_admin_can_edit() {
        let author = Actor::new(UserId::new(), Role::Author);
        let other = Actor::new(UserId::new(), Role::Author);
        let admin = Actor::new(UserId::new(), Role::Admin);
        let course = course_of(author.id);
        assert!(require_course_owner(&author, &course).is_ok());
        assert!(require_course_owner(&other, &course).is_err());
        assert!(require_course_owner(&admin, &course).is_ok());
    }

    #[test]
    fn drafts_are_private() {
        let author = Actor::new(UserId::new(), Role::Author);
        let student = Actor::new(UserId::new(), Role::Student);
        let mut course = course_of(author.id);
        assert!(!can_view_course(None, &course));
        assert!(!can_view_course(Some(&student), &course));
        assert!(can_view_course(Some(&author), &course));
        course.publish(1, Utc::now()).unwrap();
        assert!(can_view_course(None, &course));
    }
}
