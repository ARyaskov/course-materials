//! billing-mock: the payment provider CourseFlow integrates with.
//!
//! `POST /payments` creates a payment and, after a short delay, delivers a
//! signed webhook to `callback_url`. Behaviour is steered per request by the
//! `X-Mock-Scenario` header (or by the amount, see `scenario_for`):
//!
//! * `success` (default) — webhook `payment_succeeded`
//! * `fail`              — webhook `payment_failed`
//! * `slow`              — response delayed by 6 s (exceeds CourseFlow's timeout)
//! * `error`             — HTTP 503 from the provider
//! * `duplicate`         — the success webhook is delivered twice
//! * `refund`            — success, then `payment_refunded` a bit later

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use axum::extract::{Path, State};
use axum::http::{HeaderMap, StatusCode};
use axum::routing::{get, post};
use axum::{Json, Router};
use courseflow_app::billing::sign_payload;
use rust_decimal::Decimal;
use secrecy::SecretString;
use serde::{Deserialize, Serialize};

#[derive(Clone)]
struct Mock {
    http: reqwest::Client,
    webhook_secret: SecretString,
    api_key: String,
    payments: Arc<Mutex<HashMap<String, PaymentRecord>>>,
    webhook_delay: Duration,
}

#[derive(Debug, Clone, Serialize)]
struct PaymentRecord {
    payment_id: String,
    reference: String,
    amount: Decimal,
    currency: String,
    status: String,
    callback_url: String,
}

#[derive(Debug, Deserialize)]
struct CreatePayment {
    amount: Decimal,
    currency: String,
    #[allow(dead_code)]
    description: String,
    reference: String,
    callback_url: String,
}

#[derive(Debug, Serialize)]
struct Created {
    payment_id: String,
    checkout_url: String,
}

#[derive(Debug, Serialize)]
struct ProviderError {
    message: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Scenario {
    Success,
    Fail,
    Slow,
    Error,
    Duplicate,
    Refund,
}

/// Header wins; otherwise the cents encode the scenario so that a plain
/// CourseFlow checkout can trigger any path without extra tooling:
/// `.13` → fail, `.55` → slow, `.99` → error, `.22` → duplicate, `.77` → refund.
fn scenario_for(headers: &HeaderMap, amount: Decimal) -> Scenario {
    if let Some(v) = headers.get("x-mock-scenario").and_then(|v| v.to_str().ok()) {
        return match v {
            "fail" => Scenario::Fail,
            "slow" => Scenario::Slow,
            "error" => Scenario::Error,
            "duplicate" => Scenario::Duplicate,
            "refund" => Scenario::Refund,
            _ => Scenario::Success,
        };
    }
    let cents = (amount.fract() * Decimal::from(100)).to_string();
    match cents.as_str() {
        "13" => Scenario::Fail,
        "55" => Scenario::Slow,
        "99" => Scenario::Error,
        "22" => Scenario::Duplicate,
        "77" => Scenario::Refund,
        _ => Scenario::Success,
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::dotenv();
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let webhook_secret =
        std::env::var("COURSEFLOW_BILLING_WEBHOOK_SECRET").unwrap_or_else(|_| "dev-webhook-secret".into());
    let api_key = std::env::var("COURSEFLOW_BILLING_API_KEY").unwrap_or_else(|_| "dev-api-key".into());
    let addr: std::net::SocketAddr =
        std::env::var("BILLING_MOCK_ADDR").unwrap_or_else(|_| "127.0.0.1:8090".into()).parse()?;
    let webhook_delay = Duration::from_millis(
        std::env::var("BILLING_MOCK_WEBHOOK_DELAY_MS").ok().and_then(|v| v.parse().ok()).unwrap_or(1500),
    );

    let mock = Mock {
        http: reqwest::Client::builder().timeout(Duration::from_secs(5)).build()?,
        webhook_secret: SecretString::from(webhook_secret),
        api_key,
        payments: Arc::new(Mutex::new(HashMap::new())),
        webhook_delay,
    };

    let app = Router::new()
        .route("/health/live", get(|| async { "ok" }))
        .route("/payments", post(create_payment))
        .route("/payments/{id}", get(get_payment))
        .with_state(mock);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!(%addr, "billing-mock listening");
    axum::serve(listener, app).await?;
    Ok(())
}

async fn create_payment(
    State(mock): State<Mock>,
    headers: HeaderMap,
    Json(body): Json<CreatePayment>,
) -> Result<(StatusCode, Json<Created>), (StatusCode, Json<ProviderError>)> {
    let auth_ok =
        headers.get("authorization").and_then(|v| v.to_str().ok()) == Some(&format!("Bearer {}", mock.api_key));
    if !auth_ok {
        return Err((StatusCode::UNAUTHORIZED, Json(ProviderError { message: "invalid api key".into() })));
    }
    let scenario = scenario_for(&headers, body.amount);
    tracing::info!(reference = %body.reference, ?scenario, amount = %body.amount, "payment requested");

    match scenario {
        Scenario::Error => {
            return Err((
                StatusCode::SERVICE_UNAVAILABLE,
                Json(ProviderError { message: "provider maintenance".into() }),
            ));
        }
        Scenario::Slow => tokio::time::sleep(Duration::from_secs(6)).await,
        _ => {}
    }

    // Provider-side idempotency: same Idempotency-Key → same payment.
    let idem = headers.get("idempotency-key").and_then(|v| v.to_str().ok()).map(str::to_owned);
    let payment_id = idem
        .map(|k| format!("pay_{}", uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, k.as_bytes()).simple()))
        .unwrap_or_else(|| format!("pay_{}", uuid::Uuid::now_v7().simple()));

    let record = PaymentRecord {
        payment_id: payment_id.clone(),
        reference: body.reference.clone(),
        amount: body.amount,
        currency: body.currency.clone(),
        status: "pending".into(),
        callback_url: body.callback_url.clone(),
    };
    let is_new =
        mock.payments.lock().unwrap_or_else(|e| e.into_inner()).insert(payment_id.clone(), record.clone()).is_none();

    if is_new {
        let mock2 = mock.clone();
        tokio::spawn(async move { deliver(mock2, record, scenario).await });
    }
    Ok((
        StatusCode::CREATED,
        Json(Created {
            payment_id: payment_id.clone(),
            checkout_url: format!("https://billing.local/checkout/{payment_id}"),
        }),
    ))
}

async fn get_payment(State(mock): State<Mock>, Path(id): Path<String>) -> Result<Json<PaymentRecord>, StatusCode> {
    mock.payments.lock().unwrap_or_else(|e| e.into_inner()).get(&id).cloned().map(Json).ok_or(StatusCode::NOT_FOUND)
}

async fn deliver(mock: Mock, payment: PaymentRecord, scenario: Scenario) {
    tokio::time::sleep(mock.webhook_delay).await;
    let (event, status) = match scenario {
        Scenario::Fail => (
            serde_json::json!({"type": "payment_failed", "provider_payment_id": payment.payment_id, "reason": "card declined"}),
            "failed",
        ),
        _ => (serde_json::json!({"type": "payment_succeeded", "provider_payment_id": payment.payment_id}), "paid"),
    };
    if let Some(p) = mock.payments.lock().unwrap_or_else(|e| e.into_inner()).get_mut(&payment.payment_id) {
        p.status = status.into();
    }
    let event_id = format!("evt_{}", uuid::Uuid::now_v7().simple());
    send_webhook(&mock, &payment.callback_url, &event_id, &event).await;
    if scenario == Scenario::Duplicate {
        tokio::time::sleep(Duration::from_millis(300)).await;
        send_webhook(&mock, &payment.callback_url, &event_id, &event).await;
    }
    if scenario == Scenario::Refund {
        tokio::time::sleep(Duration::from_secs(2)).await;
        let refund = serde_json::json!({"type": "payment_refunded", "provider_payment_id": payment.payment_id});
        send_webhook(&mock, &payment.callback_url, &format!("evt_{}", uuid::Uuid::now_v7().simple()), &refund).await;
    }
}

/// Retries a few times: CourseFlow acknowledges duplicates, so redelivery is safe.
async fn send_webhook(mock: &Mock, url: &str, event_id: &str, event: &serde_json::Value) {
    let body = serde_json::to_vec(event).unwrap_or_default();
    for attempt in 0..5u32 {
        let ts = chrono::Utc::now().timestamp();
        let signature = sign_payload(&mock.webhook_secret, ts, &body);
        let result = mock
            .http
            .post(url)
            .header("content-type", "application/json")
            .header("x-billing-timestamp", ts.to_string())
            .header("x-billing-signature", signature)
            .header("x-billing-event-id", event_id)
            .body(body.clone())
            .send()
            .await;
        match result {
            Ok(resp) if resp.status().is_success() => {
                tracing::info!(event_id, attempt, status = %resp.status(), "webhook delivered");
                return;
            }
            Ok(resp) if resp.status().is_client_error() => {
                tracing::warn!(event_id, status = %resp.status(), "webhook rejected, not retrying");
                return;
            }
            Ok(resp) => tracing::warn!(event_id, attempt, status = %resp.status(), "webhook failed, retrying"),
            Err(err) => tracing::warn!(event_id, attempt, error = %err, "webhook delivery error, retrying"),
        }
        tokio::time::sleep(Duration::from_millis(500 * 2u64.pow(attempt))).await;
    }
    tracing::error!(event_id, "webhook delivery gave up");
}
