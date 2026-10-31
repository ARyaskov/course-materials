#![allow(clippy::unwrap_used, clippy::expect_used)]
mod common;

use axum::http::StatusCode;
use serde_json::json;
use sqlx::PgPool;

#[sqlx::test(migrations = "../../migrations")]
async fn completing_all_lessons_issues_certificate_once(pool: PgPool) {
    let app = common::spawn(pool).await;
    let (_, author) = app.author("t@example.com").await;
    let (course, lessons) = app.published_course(&author, "Finish me", "0").await;
    let (_, student, _) = app.register_and_login("s@example.com").await;

    // not enrolled yet
    app.post(&format!("/api/v1/lessons/{}/complete", lessons[0]), Some(&student), json!({}))
        .await
        .assert_status(StatusCode::FORBIDDEN);
    app.post(&format!("/api/v1/courses/{course}/enroll"), Some(&student), json!({}))
        .await
        .assert_status(StatusCode::CREATED);

    let r = app.post(&format!("/api/v1/lessons/{}/complete", lessons[0]), Some(&student), json!({})).await;
    r.assert_status(StatusCode::OK);
    assert_eq!(r.body["progress"]["percent"], 50);
    assert!(r.body["certificate"].is_null());

    let r = app.post(&format!("/api/v1/lessons/{}/complete", lessons[1]), Some(&student), json!({})).await;
    assert_eq!(r.body["progress"]["percent"], 100);
    let code = r.body["certificate"]["code"].as_str().unwrap().to_owned();
    assert!(code.starts_with("CF-"));

    // idempotent: completing again keeps the same certificate
    let r = app.post(&format!("/api/v1/lessons/{}/complete", lessons[1]), Some(&student), json!({})).await;
    assert_eq!(r.body["newly_completed"], false);
    assert_eq!(r.body["certificate"]["code"], code);

    // public verification
    let v = app.get(&format!("/api/v1/certificates/{code}"), None).await;
    v.assert_status(StatusCode::OK);
    app.get("/api/v1/certificates/CF-NOPE-0000", None).await.assert_status(StatusCode::NOT_FOUND);
}
