//! Typed HTTP client for the billing provider (reqwest 0.13) plus a fake for
//! tests. The rest of the application only ever sees `PaymentRequest` /
//! `PaymentCreated` / `BillingError`.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use courseflow_core::billing::{PaymentCreated, PaymentRequest};
use courseflow_core::ports::{BillingClient, BillingError, BoxFuture};
use secrecy::ExposeSecret;
use serde::{Deserialize, Serialize};
use tokio::sync::Semaphore;

use crate::config::BillingConfig;
use crate::resilience::{CircuitBreaker, RetryPolicy, retry};

#[derive(Debug, Serialize)]
struct CreatePaymentBody<'a> {
    amount: rust_decimal::Decimal,
    currency: &'a str,
    description: &'a str,
    reference: String,
    callback_url: &'a str,
}

#[derive(Debug, Deserialize)]
struct CreatePaymentResponse {
    payment_id: String,
    checkout_url: String,
}

#[derive(Debug, Deserialize)]
struct ProviderError {
    message: String,
}

#[derive(Debug)]
pub struct HttpBillingClient {
    http: reqwest::Client,
    base_url: String,
    api_key: secrecy::SecretString,
    callback_url: String,
    retry: RetryPolicy,
    breaker: CircuitBreaker,
    /// Bulkhead: at most N in-flight calls to the provider per process.
    permits: Semaphore,
}

impl HttpBillingClient {
    pub fn new(config: &BillingConfig, callback_url: String) -> Result<Self, reqwest::Error> {
        let http = reqwest::Client::builder()
            .timeout(config.timeout)
            .connect_timeout(Duration::from_secs(2))
            .user_agent(concat!("courseflow/", env!("CARGO_PKG_VERSION")))
            .pool_idle_timeout(Duration::from_secs(60))
            .build()?;
        Ok(Self {
            http,
            base_url: config.base_url.trim_end_matches('/').to_owned(),
            api_key: config.api_key.clone(),
            callback_url,
            retry: RetryPolicy::new(config.max_retries.max(1)),
            breaker: CircuitBreaker::new("billing", 5, Duration::from_secs(30)),
            permits: Semaphore::new(16),
        })
    }

    pub fn breaker(&self) -> &CircuitBreaker {
        &self.breaker
    }

    async fn call_once(&self, request: &PaymentRequest) -> Result<PaymentCreated, BillingError> {
        let body = CreatePaymentBody {
            amount: request.amount.amount(),
            currency: request.amount.currency().as_str(),
            description: &request.description,
            reference: request.purchase_id.to_string(),
            callback_url: &self.callback_url,
        };
        let response = self
            .http
            .post(format!("{}/payments", self.base_url))
            .bearer_auth(self.api_key.expose_secret())
            .header("Idempotency-Key", &request.idempotency_key)
            .json(&body)
            .send()
            .await
            .map_err(
                |e| if e.is_timeout() { BillingError::Timeout } else { BillingError::Unavailable(e.to_string()) },
            )?;

        let status = response.status();
        if status.is_success() {
            let parsed: CreatePaymentResponse =
                response.json().await.map_err(|e| BillingError::Unavailable(format!("malformed response: {e}")))?;
            return Ok(PaymentCreated { provider_payment_id: parsed.payment_id, checkout_url: parsed.checkout_url });
        }
        let message =
            response.json::<ProviderError>().await.map(|e| e.message).unwrap_or_else(|_| format!("http {status}"));
        if status.is_server_error() || status.as_u16() == 429 {
            Err(BillingError::Unavailable(message))
        } else {
            Err(BillingError::Rejected(message))
        }
    }
}

fn is_retryable(err: &BillingError) -> bool {
    matches!(err, BillingError::Unavailable(_) | BillingError::Timeout)
}

impl BillingClient for HttpBillingClient {
    fn create_payment(&self, request: PaymentRequest) -> BoxFuture<'_, Result<PaymentCreated, BillingError>> {
        Box::pin(async move {
            if !self.breaker.allow() {
                metrics::counter!("courseflow_billing_calls_total", "outcome" => "circuit_open").increment(1);
                return Err(BillingError::CircuitOpen);
            }
            let _permit =
                self.permits.acquire().await.map_err(|_| BillingError::Unavailable("bulkhead closed".into()))?;
            let started = std::time::Instant::now();
            let result = retry(self.retry, is_retryable, |attempt| {
                let request = &request;
                async move {
                    if attempt > 0 {
                        tracing::warn!(attempt, purchase_id = %request.purchase_id, "retrying billing call");
                    }
                    self.call_once(request).await
                }
            })
            .await;
            metrics::histogram!("courseflow_billing_call_seconds").record(started.elapsed().as_secs_f64());
            match &result {
                Ok(_) | Err(BillingError::Rejected(_)) => self.breaker.record_success(),
                Err(_) => self.breaker.record_failure(),
            }
            metrics::counter!("courseflow_billing_calls_total", "outcome" => if result.is_ok() { "ok" } else { "error" }).increment(1);
            result
        })
    }
}

/// Test double: records requests and answers with a canned result.
#[derive(Debug, Default)]
pub struct FakeBillingClient {
    pub requests: Mutex<Vec<PaymentRequest>>,
    pub fail_with: Mutex<Option<String>>,
}

impl FakeBillingClient {
    pub fn shared() -> Arc<Self> {
        Arc::new(Self::default())
    }
}

impl BillingClient for FakeBillingClient {
    fn create_payment(&self, request: PaymentRequest) -> BoxFuture<'_, Result<PaymentCreated, BillingError>> {
        Box::pin(async move {
            if let Some(reason) = self.fail_with.lock().unwrap_or_else(|e| e.into_inner()).clone() {
                return Err(BillingError::Unavailable(reason));
            }
            let id = format!("fake_{}", request.purchase_id);
            self.requests.lock().unwrap_or_else(|e| e.into_inner()).push(request);
            Ok(PaymentCreated {
                provider_payment_id: id.clone(),
                checkout_url: format!("https://billing.local/checkout/{id}"),
            })
        })
    }
}
