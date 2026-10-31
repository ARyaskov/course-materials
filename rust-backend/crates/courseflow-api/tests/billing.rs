#![allow(clippy::unwrap_used, clippy::expect_used)]
mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode, header};
use courseflow_app::billing::sign_payload;
use secrecy::SecretString;
use serde_json::json;
use sqlx::PgPool;

fn signed_webhook(secret: &str, event_id: &str, payload: &serde_json::Value, ts: i64) -> Request<Body> {
    let body = payload.to_string();
    let signature = sign_payload(&SecretString::from(secret.to_owned()), ts, body.as_bytes());
    Request::post("/api/v1/webhooks/billing")
        .header(header::CONTENT_TYPE, "application/json")
        .header("x-billing-timestamp", ts.to_string())
        .header("x-billing-signature", signature)
        .header("x-billing-event-id", event_id)
        .body(Body::from(body))
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn checkout_requires_idempotency_key(pool: PgPool) {
    let app = common::spawn(pool).await;
    let (_, author) = app.author("seller@example.com").await;
    let (course, _) = app.published_course(&author, "Paid", "49.00").await;
    let (_, student, _) = app.register_and_login("buyer@example.com").await;
    let r = app.post(&format!("/api/v1/courses/{course}/checkout"), Some(&student), json!({})).await;
    r.assert_status(StatusCode::BAD_REQUEST);
}

#[sqlx::test(migrations = "../../migrations")]
async fn purchase_end_to_end_with_signed_webhook(pool: PgPool) {
    let app = common::spawn(pool).await;
    let (_, author) = app.author("seller@example.com").await;
    let (course, lessons) = app.published_course(&author, "Paid", "49.00").await;
    let (_, student, _) = app.register_and_login("buyer@example.com").await;

    let checkout = |key: &str| {
        Request::post(format!("/api/v1/courses/{course}/checkout"))
            .header(header::AUTHORIZATION, format!("Bearer {student}"))
            .header("idempotency-key", key)
            .body(Body::empty())
            .unwrap()
    };
    let r = app.send(checkout("order-1")).await;
    r.assert_status(StatusCode::CREATED);
    assert_eq!(r.body["purchase"]["status"], "pending");
    assert!(r.str("checkout_url").starts_with("https://billing.local/"));
    let purchase_id = r.body["purchase"]["id"].as_str().unwrap().to_owned();

    // same key → same purchase, no second provider call
    let again = app.send(checkout("order-1")).await;
    again.assert_status(StatusCode::OK);
    assert_eq!(again.body["purchase"]["id"], purchase_id);
    assert_eq!(app.billing.requests.lock().unwrap().len(), 1);

    // provider says paid (the fake client names payments `fake_<purchase_id>`)
    let event = json!({"type": "payment_succeeded", "provider_payment_id": format!("fake_{purchase_id}")});
    let now = chrono::Utc::now().timestamp();
    app.send(signed_webhook("test-webhook-secret", "evt-1", &event, now)).await.assert_status(StatusCode::NO_CONTENT);
    // duplicate delivery is acknowledged, not re-applied
    app.send(signed_webhook("test-webhook-secret", "evt-1", &event, now)).await.assert_status(StatusCode::NO_CONTENT);

    let p = app.get(&format!("/api/v1/me/purchases/{purchase_id}"), Some(&student)).await;
    assert_eq!(p.str("status"), "paid");
    let enrollments = app.get("/api/v1/me/enrollments", Some(&student)).await;
    assert_eq!(enrollments.body.as_array().unwrap().len(), 1);
    assert_eq!(enrollments.body[0]["source"]["kind"], "purchase");

    // and the student can now read gated lessons
    app.get(&format!("/api/v1/lessons/{}", lessons[1]), Some(&student)).await.assert_status(StatusCode::OK);

    // two outbox rows were queued inside the webhook transaction
    let (pending, _) = courseflow_app::outbox::pending_count(&app.pool).await.unwrap();
    assert!(pending >= 2, "expected outbox events, got {pending}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn webhook_rejects_bad_signature_and_stale_timestamp(pool: PgPool) {
    let app = common::spawn(pool).await;
    let event = json!({"type": "payment_succeeded", "provider_payment_id": "whatever"});
    let now = chrono::Utc::now().timestamp();
    app.send(signed_webhook("wrong-secret", "evt-x", &event, now)).await.assert_status(StatusCode::UNAUTHORIZED);
    app.send(signed_webhook("test-webhook-secret", "evt-y", &event, now - 3600))
        .await
        .assert_status(StatusCode::UNAUTHORIZED);
    // unsigned request never reaches the parser
    let r = app.post("/api/v1/webhooks/billing", None, event).await;
    r.assert_status(StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn provider_outage_marks_purchase_failed_and_returns_503(pool: PgPool) {
    let app = common::spawn(pool).await;
    *app.billing.fail_with.lock().unwrap() = Some("maintenance".into());
    let (_, author) = app.author("seller@example.com").await;
    let (course, _) = app.published_course(&author, "Paid", "10.00").await;
    let (_, student, _) = app.register_and_login("buyer@example.com").await;
    let r = app
        .send(
            Request::post(format!("/api/v1/courses/{course}/checkout"))
                .header(header::AUTHORIZATION, format!("Bearer {student}"))
                .header("idempotency-key", "k1")
                .body(Body::empty())
                .unwrap(),
        )
        .await;
    r.assert_status(StatusCode::SERVICE_UNAVAILABLE);
    let list = app.get("/api/v1/me/purchases", Some(&student)).await;
    assert_eq!(list.body[0]["status"], "failed");
}
