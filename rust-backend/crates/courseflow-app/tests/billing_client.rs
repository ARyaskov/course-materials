//! `HttpBillingClient` against wiremock: success, provider error with retry,
//! timeout, and the circuit opening after repeated failures.

#![allow(clippy::unwrap_used)]

use std::time::Duration;

use courseflow_app::billing::HttpBillingClient;
use courseflow_app::config::BillingConfig;
use courseflow_app::resilience::BreakerState;
use courseflow_core::billing::PaymentRequest;
use courseflow_core::ids::PurchaseId;
use courseflow_core::money::{Currency, Money};
use courseflow_core::ports::{BillingClient, BillingError};
use rust_decimal::dec;
use secrecy::SecretString;
use wiremock::matchers::{header, method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

fn client(server: &MockServer, retries: u32) -> HttpBillingClient {
    let config = BillingConfig {
        base_url: server.uri(),
        api_key: SecretString::from("k"),
        webhook_secret: SecretString::from("s"),
        timeout: Duration::from_millis(300),
        max_retries: retries,
    };
    HttpBillingClient::new(&config, "http://cf.local/webhook".into()).unwrap()
}

fn request() -> PaymentRequest {
    PaymentRequest {
        purchase_id: PurchaseId::new(),
        amount: Money::new(dec!(49.00), Currency::Usd).unwrap(),
        description: "test".into(),
        idempotency_key: "idem-1".into(),
    }
}

#[tokio::test]
async fn success_maps_provider_response() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/payments"))
        .and(header("authorization", "Bearer k"))
        .and(header("idempotency-key", "idem-1"))
        .respond_with(
            ResponseTemplate::new(201)
                .set_body_json(serde_json::json!({"payment_id": "pay_1", "checkout_url": "https://x/1"})),
        )
        .expect(1)
        .mount(&server)
        .await;
    let created = client(&server, 1).create_payment(request()).await.unwrap();
    assert_eq!(created.provider_payment_id, "pay_1");
}

#[tokio::test]
async fn server_error_is_retried_then_reported() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/payments"))
        .respond_with(ResponseTemplate::new(503).set_body_json(serde_json::json!({"message": "down"})))
        .expect(3)
        .mount(&server)
        .await;
    let err = client(&server, 3).create_payment(request()).await.unwrap_err();
    assert!(matches!(err, BillingError::Unavailable(m) if m == "down"));
}

#[tokio::test]
async fn client_error_is_not_retried() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/payments"))
        .respond_with(ResponseTemplate::new(422).set_body_json(serde_json::json!({"message": "bad currency"})))
        .expect(1)
        .mount(&server)
        .await;
    let err = client(&server, 3).create_payment(request()).await.unwrap_err();
    assert!(matches!(err, BillingError::Rejected(_)));
}

#[tokio::test]
async fn timeout_becomes_billing_timeout() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/payments"))
        .respond_with(ResponseTemplate::new(201).set_delay(Duration::from_secs(2)))
        .mount(&server)
        .await;
    let err = client(&server, 1).create_payment(request()).await.unwrap_err();
    assert!(matches!(err, BillingError::Timeout));
}

#[tokio::test]
async fn circuit_opens_after_repeated_failures() {
    let server = MockServer::start().await;
    Mock::given(method("POST")).and(path("/payments")).respond_with(ResponseTemplate::new(500)).mount(&server).await;
    let client = client(&server, 1);
    for _ in 0..5 {
        let _ = client.create_payment(request()).await;
    }
    assert_eq!(client.breaker().state(), BreakerState::Open);
    assert!(matches!(client.create_payment(request()).await.unwrap_err(), BillingError::CircuitOpen));
}
