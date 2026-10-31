use chrono::{DateTime, Utc};
use courseflow_core::billing::{BillingEvent, Purchase, PurchaseStatus};
use courseflow_core::ids::{CourseId, PurchaseId, UserId};
use courseflow_core::money::Currency;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct PurchaseResponse {
    pub id: PurchaseId,
    pub user_id: UserId,
    pub course_id: CourseId,
    #[schema(value_type = String)]
    pub amount: Decimal,
    pub currency: Currency,
    pub status: PurchaseStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub failure_reason: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl From<Purchase> for PurchaseResponse {
    fn from(p: Purchase) -> Self {
        Self {
            id: p.id,
            user_id: p.user_id,
            course_id: p.course_id,
            amount: p.amount.amount(),
            currency: p.amount.currency(),
            status: p.status,
            failure_reason: p.failure_reason,
            created_at: p.created_at,
            updated_at: p.updated_at,
        }
    }
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct CheckoutResponse {
    pub purchase: PurchaseResponse,
    /// Present only when a new payment was created; a replay returns the
    /// original purchase without a fresh checkout link.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub checkout_url: Option<String>,
}

/// Incoming provider webhook: the body is exactly the provider's schema,
/// deserialized only after the signature has been verified.
#[derive(Debug, Deserialize, ToSchema)]
pub struct BillingWebhook {
    #[serde(flatten)]
    #[schema(value_type = Object)]
    pub event: BillingEvent,
}
