use std::fmt;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::errors::DomainError;
use crate::ids::{CourseId, PurchaseId, UserId};
use crate::money::Money;

#[cfg_attr(feature = "openapi", derive(utoipa::ToSchema))]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PurchaseStatus {
    Pending,
    Paid,
    Failed,
    Refunded,
}

impl PurchaseStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            PurchaseStatus::Pending => "pending",
            PurchaseStatus::Paid => "paid",
            PurchaseStatus::Failed => "failed",
            PurchaseStatus::Refunded => "refunded",
        }
    }
}

impl std::str::FromStr for PurchaseStatus {
    type Err = DomainError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "pending" => Ok(Self::Pending),
            "paid" => Ok(Self::Paid),
            "failed" => Ok(Self::Failed),
            "refunded" => Ok(Self::Refunded),
            other => Err(DomainError::validation("status", format!("unknown purchase status {other}"))),
        }
    }
}

impl fmt::Display for PurchaseStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// A purchase is the bridge between CourseFlow and the billing provider.
/// It is created `Pending` before the provider is called and finalized by a
/// webhook, so the state machine must tolerate duplicate and late events.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Purchase {
    pub id: PurchaseId,
    pub user_id: UserId,
    pub course_id: CourseId,
    pub amount: Money,
    pub status: PurchaseStatus,
    /// Identifier assigned by the provider once the payment was created.
    pub provider_payment_id: Option<String>,
    pub idempotency_key: String,
    pub failure_reason: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Purchase {
    pub fn start(
        user_id: UserId,
        course_id: CourseId,
        amount: Money,
        idempotency_key: String,
        now: DateTime<Utc>,
    ) -> Result<Self, DomainError> {
        if amount.is_free() {
            return Err(DomainError::rule("free courses are enrolled directly, not purchased"));
        }
        if idempotency_key.trim().is_empty() || idempotency_key.len() > 128 {
            return Err(DomainError::validation("idempotency_key", "must be 1..=128 characters"));
        }
        Ok(Self {
            id: PurchaseId::new(),
            user_id,
            course_id,
            amount,
            status: PurchaseStatus::Pending,
            provider_payment_id: None,
            idempotency_key,
            failure_reason: None,
            created_at: now,
            updated_at: now,
        })
    }

    pub fn attach_provider_payment(&mut self, provider_payment_id: String, now: DateTime<Utc>) {
        self.provider_payment_id = Some(provider_payment_id);
        self.updated_at = now;
    }

    /// Idempotent: a second `paid` webhook is a no-op, not an error.
    pub fn mark_paid(&mut self, now: DateTime<Utc>) -> Result<bool, DomainError> {
        match self.status {
            PurchaseStatus::Paid => Ok(false),
            PurchaseStatus::Pending => {
                self.status = PurchaseStatus::Paid;
                self.updated_at = now;
                Ok(true)
            }
            from => Err(DomainError::InvalidTransition { entity: "purchase", from: from.as_str(), to: "paid" }),
        }
    }

    pub fn mark_failed(&mut self, reason: String, now: DateTime<Utc>) -> Result<bool, DomainError> {
        match self.status {
            PurchaseStatus::Failed => Ok(false),
            PurchaseStatus::Pending => {
                self.status = PurchaseStatus::Failed;
                self.failure_reason = Some(reason);
                self.updated_at = now;
                Ok(true)
            }
            from => Err(DomainError::InvalidTransition { entity: "purchase", from: from.as_str(), to: "failed" }),
        }
    }

    pub fn mark_refunded(&mut self, now: DateTime<Utc>) -> Result<bool, DomainError> {
        match self.status {
            PurchaseStatus::Refunded => Ok(false),
            PurchaseStatus::Paid => {
                self.status = PurchaseStatus::Refunded;
                self.updated_at = now;
                Ok(true)
            }
            from => Err(DomainError::InvalidTransition { entity: "purchase", from: from.as_str(), to: "refunded" }),
        }
    }
}

/// What the application asks the billing provider to do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PaymentRequest {
    pub purchase_id: PurchaseId,
    pub amount: Money,
    pub description: String,
    pub idempotency_key: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PaymentCreated {
    pub provider_payment_id: String,
    /// Where the client should be redirected to finish paying (mock: a URL).
    pub checkout_url: String,
}

/// Provider-side event delivered through a webhook, already verified and
/// parsed by the HTTP layer.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum BillingEvent {
    PaymentSucceeded { provider_payment_id: String },
    PaymentFailed { provider_payment_id: String, reason: String },
    PaymentRefunded { provider_payment_id: String },
}

impl BillingEvent {
    /// Stable name of the event type, as stored in `billing_events.event_type`.
    pub fn kind(&self) -> &'static str {
        match self {
            BillingEvent::PaymentSucceeded { .. } => "payment_succeeded",
            BillingEvent::PaymentFailed { .. } => "payment_failed",
            BillingEvent::PaymentRefunded { .. } => "payment_refunded",
        }
    }

    pub fn provider_payment_id(&self) -> &str {
        match self {
            BillingEvent::PaymentSucceeded { provider_payment_id }
            | BillingEvent::PaymentFailed { provider_payment_id, .. }
            | BillingEvent::PaymentRefunded { provider_payment_id } => provider_payment_id,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::money::Currency;
    use rust_decimal::dec;

    fn purchase() -> Purchase {
        Purchase::start(
            UserId::new(),
            CourseId::new(),
            Money::new(dec!(49.00), Currency::Usd).unwrap(),
            "key-1".into(),
            Utc::now(),
        )
        .unwrap()
    }

    #[test]
    fn paid_twice_is_noop() {
        let mut p = purchase();
        assert!(p.mark_paid(Utc::now()).unwrap());
        assert!(!p.mark_paid(Utc::now()).unwrap());
    }

    #[test]
    fn failed_after_paid_is_invalid() {
        let mut p = purchase();
        p.mark_paid(Utc::now()).unwrap();
        assert!(matches!(p.mark_failed("x".into(), Utc::now()), Err(DomainError::InvalidTransition { .. })));
    }

    #[test]
    fn free_course_cannot_be_purchased() {
        let r = Purchase::start(UserId::new(), CourseId::new(), Money::free(Currency::Usd), "k".into(), Utc::now());
        assert!(r.is_err());
    }
}
