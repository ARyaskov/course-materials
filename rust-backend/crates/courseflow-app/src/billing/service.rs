use std::sync::Arc;

use courseflow_core::DomainError;
use courseflow_core::billing::{BillingEvent, PaymentRequest, Purchase, PurchaseStatus};
use courseflow_core::enrollments::{Enrollment, EnrollmentSource};
use courseflow_core::ids::{CourseId, PurchaseId};
use courseflow_core::notifications::NotificationEvent;
use courseflow_core::policy::Actor;
use courseflow_core::ports::{BillingClient, Clock};
use sqlx::PgPool;

use crate::billing::repo;
use crate::courses::repo as courses;
use crate::enrollments::repo as enrollments;
use crate::errors::{AppError, AppResult};
use crate::outbox::{self, OutboxPayload};

#[derive(Debug, Clone)]
pub struct CheckoutStarted {
    pub purchase: Purchase,
    pub checkout_url: Option<String>,
}

#[derive(Clone)]
pub struct BillingService {
    pool: PgPool,
    client: Arc<dyn BillingClient>,
    clock: Arc<dyn Clock>,
}

impl std::fmt::Debug for BillingService {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("BillingService")
    }
}

impl BillingService {
    pub fn new(pool: PgPool, client: Arc<dyn BillingClient>, clock: Arc<dyn Clock>) -> Self {
        Self { pool, client, clock }
    }

    /// Starts a purchase. The provider is called *outside* the transaction:
    /// a slow provider must not hold a database connection, and a crash in
    /// between leaves a harmless `pending` row that the webhook (or a
    /// cleanup job) resolves.
    #[tracing::instrument(skip(self), fields(actor = %actor.id))]
    pub async fn start_checkout(
        &self,
        actor: &Actor,
        course_id: CourseId,
        idempotency_key: String,
    ) -> AppResult<CheckoutStarted> {
        let now = self.clock.now();
        if let Some(existing) = repo::find_by_idempotency_key(&self.pool, actor.id, &idempotency_key).await? {
            return Ok(CheckoutStarted { purchase: existing, checkout_url: None });
        }
        let course = courses::find_by_id(&self.pool, course_id).await?.ok_or(AppError::not_found("course"))?;
        if !course.is_published() {
            return Err(AppError::not_found("course"));
        }
        if enrollments::exists(&self.pool, actor.id, course_id).await? {
            return Err(AppError::conflict("already enrolled"));
        }
        let mut purchase = Purchase::start(actor.id, course_id, course.price, idempotency_key.clone(), now)?;
        repo::insert(&self.pool, &purchase).await?;

        let created = self
            .client
            .create_payment(PaymentRequest {
                purchase_id: purchase.id,
                amount: course.price,
                description: format!("CourseFlow: {}", course.title),
                idempotency_key,
            })
            .await;

        match created {
            Ok(created) => {
                purchase.attach_provider_payment(created.provider_payment_id, self.clock.now());
                repo::update(&self.pool, &purchase).await?;
                tracing::info!(purchase_id = %purchase.id, "checkout started");
                Ok(CheckoutStarted { purchase, checkout_url: Some(created.checkout_url) })
            }
            Err(err) => {
                purchase.mark_failed(err.to_string(), self.clock.now())?;
                repo::update(&self.pool, &purchase).await?;
                tracing::warn!(purchase_id = %purchase.id, error = %err, "provider call failed");
                Err(err.into())
            }
        }
    }

    /// Applies a verified provider event. Idempotent at three levels: the
    /// event id, the purchase state machine and `ON CONFLICT DO NOTHING` on
    /// the enrollment.
    #[tracing::instrument(skip(self, event), fields(provider_event_id))]
    pub async fn apply_event(&self, provider_event_id: &str, event: BillingEvent) -> AppResult<PurchaseStatus> {
        let now = self.clock.now();
        let mut tx = self.pool.begin().await?;
        if !repo::record_event(&mut *tx, provider_event_id, &event).await? {
            tx.commit().await?;
            tracing::info!("duplicate webhook acknowledged");
            return Err(AppError::conflict("event already processed"));
        }
        let Some(mut purchase) = repo::find_by_provider_id_for_update(&mut *tx, event.provider_payment_id()).await?
        else {
            // Unknown payment: record and acknowledge, do not retry forever.
            tx.commit().await?;
            return Err(AppError::not_found("purchase"));
        };
        let course = courses::find_by_id(&mut *tx, purchase.course_id).await?.ok_or(AppError::not_found("course"))?;

        // An event that does not fit the current state (e.g. `succeeded` after
        // a timeout marked the purchase `failed`) is recorded and acknowledged
        // without side effects: the provider must not retry it forever, and an
        // operator can reconcile from `billing_events`.
        let transition = match &event {
            BillingEvent::PaymentSucceeded { .. } => purchase.mark_paid(now),
            BillingEvent::PaymentFailed { reason, .. } => purchase.mark_failed(reason.clone(), now),
            BillingEvent::PaymentRefunded { .. } => purchase.mark_refunded(now),
        };
        let changed = match transition {
            Ok(changed) => changed,
            Err(DomainError::InvalidTransition { from, to, .. }) => {
                tx.commit().await?;
                tracing::warn!(purchase_id = %purchase.id, from, to, "billing event ignored: invalid transition");
                return Ok(purchase.status);
            }
            Err(other) => return Err(other.into()),
        };
        match event {
            BillingEvent::PaymentSucceeded { .. } => {
                if changed {
                    repo::update(&mut *tx, &purchase).await?;
                    let enrollment = Enrollment::new(
                        purchase.user_id,
                        purchase.course_id,
                        EnrollmentSource::Purchase { purchase_id: purchase.id },
                        now,
                    );
                    enrollments::insert_if_absent(&mut *tx, &enrollment).await?;
                    outbox::enqueue(
                        &mut *tx,
                        &OutboxPayload::PurchasePaid {
                            purchase_id: purchase.id,
                            user_id: purchase.user_id,
                            course_id: purchase.course_id,
                        },
                        now,
                    )
                    .await?;
                    outbox::enqueue(
                        &mut *tx,
                        &OutboxPayload::Notify {
                            user_id: purchase.user_id,
                            event: NotificationEvent::PurchaseCompleted {
                                purchase_id: purchase.id,
                                course_id: purchase.course_id,
                                course_title: course.title.to_string(),
                            },
                        },
                        now,
                    )
                    .await?;
                }
            }
            BillingEvent::PaymentFailed { reason, .. } => {
                if changed {
                    repo::update(&mut *tx, &purchase).await?;
                    outbox::enqueue(
                        &mut *tx,
                        &OutboxPayload::Notify {
                            user_id: purchase.user_id,
                            event: NotificationEvent::PurchaseFailed {
                                purchase_id: purchase.id,
                                course_id: purchase.course_id,
                                reason,
                            },
                        },
                        now,
                    )
                    .await?;
                }
            }
            BillingEvent::PaymentRefunded { .. } => {
                if changed {
                    repo::update(&mut *tx, &purchase).await?;
                }
            }
        }
        tx.commit().await?;
        tracing::info!(purchase_id = %purchase.id, status = %purchase.status, "billing event applied");
        Ok(purchase.status)
    }

    pub async fn get(&self, actor: &Actor, id: PurchaseId) -> AppResult<Purchase> {
        let purchase = repo::find_by_id(&self.pool, id).await?.ok_or(AppError::not_found("purchase"))?;
        if purchase.user_id != actor.id && !actor.role.is_admin() {
            return Err(AppError::not_found("purchase"));
        }
        Ok(purchase)
    }

    pub async fn list_mine(&self, actor: &Actor) -> AppResult<Vec<Purchase>> {
        repo::list_for_user(&self.pool, actor.id).await
    }
}
