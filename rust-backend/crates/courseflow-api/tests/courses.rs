#![allow(clippy::unwrap_used, clippy::expect_used)]
mod common;

use axum::http::{Method, StatusCode};
use serde_json::json;
use sqlx::PgPool;

#[sqlx::test(migrations = "../../migrations")]
async fn student_cannot_create_course(pool: PgPool) {
    let app = common::spawn(pool).await;
    let (_, token, _) = app.register_and_login("s@example.com").await;
    let r = app.post("/api/v1/courses", Some(&token), json!({"title": "Nope", "price": "0"})).await;
    r.assert_status(StatusCode::FORBIDDEN);
    assert_eq!(r.str("code"), "forbidden");
}

#[sqlx::test(migrations = "../../migrations")]
async fn course_lifecycle_draft_publish_archive(pool: PgPool) {
    let app = common::spawn(pool).await;
    let (_, author) = app.author("author@example.com").await;

    let r = app.post("/api/v1/courses", Some(&author), json!({"title": "Rust Backend 2026", "price": "49.00"})).await;
    r.assert_status(StatusCode::CREATED);
    assert!(r.headers["location"].to_str().unwrap().starts_with("/api/v1/courses/"));
    let id = r.str("id").to_owned();
    assert_eq!(r.str("status"), "draft");
    assert_eq!(r.str("slug"), "rust-backend-2026");

    // drafts are invisible to strangers
    app.get(&format!("/api/v1/courses/{id}"), None).await.assert_status(StatusCode::NOT_FOUND);
    // and cannot be published without lessons
    let r = app.post(&format!("/api/v1/courses/{id}/publish"), Some(&author), json!({})).await;
    r.assert_status(StatusCode::CONFLICT);

    app.post(&format!("/api/v1/courses/{id}/lessons"), Some(&author), json!({"title": "Intro"}))
        .await
        .assert_status(StatusCode::CREATED);
    let r = app.post(&format!("/api/v1/courses/{id}/publish"), Some(&author), json!({})).await;
    r.assert_status(StatusCode::OK);
    assert_eq!(r.str("status"), "published");

    // now public
    app.get(&format!("/api/v1/courses/{id}"), None).await.assert_status(StatusCode::OK);
    let list = app.get("/api/v1/courses", None).await;
    assert_eq!(list.body["items"].as_array().unwrap().len(), 1);

    // PATCH bumps the version (optimistic locking)
    let r = app
        .request(
            Method::PATCH,
            &format!("/api/v1/courses/{id}"),
            Some(&author),
            Some(json!({"description": "updated"})),
        )
        .await;
    r.assert_status(StatusCode::OK);
    assert_eq!(r.body["version"], 3);

    app.post(&format!("/api/v1/courses/{id}/archive"), Some(&author), json!({})).await.assert_status(StatusCode::OK);
    app.request(Method::PATCH, &format!("/api/v1/courses/{id}"), Some(&author), Some(json!({"description": "x"})))
        .await
        .assert_status(StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn other_author_cannot_edit(pool: PgPool) {
    let app = common::spawn(pool).await;
    let (_, a1) = app.author("a1@example.com").await;
    let (_, a2) = app.author("a2@example.com").await;
    let (course, _) = app.published_course(&a1, "Mine", "0").await;
    let r = app
        .request(Method::PATCH, &format!("/api/v1/courses/{course}"), Some(&a2), Some(json!({"title": "Hijacked"})))
        .await;
    r.assert_status(StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn cursor_pagination_is_stable(pool: PgPool) {
    let app = common::spawn(pool).await;
    let (_, author) = app.author("pager@example.com").await;
    for i in 0..5 {
        app.published_course(&author, &format!("Course {i}"), "0").await;
    }
    let first = app.get("/api/v1/courses?limit=2", None).await;
    first.assert_status(StatusCode::OK);
    let items = first.body["items"].as_array().unwrap();
    assert_eq!(items.len(), 2);
    let cursor = first.str("next_cursor").to_owned();

    let second = app.get(&format!("/api/v1/courses?limit=2&cursor={cursor}"), None).await;
    second.assert_status(StatusCode::OK);
    let ids1: Vec<_> = items.iter().map(|c| c["id"].as_str().unwrap()).collect();
    let ids2: Vec<_> = second.body["items"].as_array().unwrap().iter().map(|c| c["id"].as_str().unwrap()).collect();
    assert!(ids1.iter().all(|id| !ids2.contains(id)), "pages overlap");

    let third = app.get(&format!("/api/v1/courses?limit=2&cursor={}", second.str("next_cursor")), None).await;
    assert_eq!(third.body["items"].as_array().unwrap().len(), 1);
    assert!(third.body["next_cursor"].is_null());

    app.get("/api/v1/courses?limit=500", None).await.assert_status(StatusCode::UNPROCESSABLE_ENTITY);
    app.get("/api/v1/courses?cursor=garbage", None).await.assert_status(StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn unknown_json_field_is_rejected(pool: PgPool) {
    let app = common::spawn(pool).await;
    let (_, author) = app.author("strict@example.com").await;
    let r = app.post("/api/v1/courses", Some(&author), json!({"title": "X", "price": "0", "colour": "red"})).await;
    r.assert_status(StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(r.body["errors"][0]["field"], "body");
}

#[sqlx::test(migrations = "../../migrations")]
async fn lesson_body_requires_enrollment_unless_preview(pool: PgPool) {
    let app = common::spawn(pool).await;
    let (_, author) = app.author("teach@example.com").await;
    let (course, lessons) = app.published_course(&author, "Gated", "0").await;
    let (_, student, _) = app.register_and_login("learner@example.com").await;

    // toc is public, preview lesson is public, second lesson is gated
    app.get(&format!("/api/v1/courses/{course}/lessons"), None).await.assert_status(StatusCode::OK);
    app.get(&format!("/api/v1/lessons/{}", lessons[0]), None).await.assert_status(StatusCode::OK);
    app.get(&format!("/api/v1/lessons/{}", lessons[1]), None).await.assert_status(StatusCode::UNAUTHORIZED);
    app.get(&format!("/api/v1/lessons/{}", lessons[1]), Some(&student)).await.assert_status(StatusCode::FORBIDDEN);

    app.post(&format!("/api/v1/courses/{course}/enroll"), Some(&student), json!({}))
        .await
        .assert_status(StatusCode::CREATED);
    app.get(&format!("/api/v1/lessons/{}", lessons[1]), Some(&student)).await.assert_status(StatusCode::OK);
    // enrolling twice is a conflict, not a crash
    app.post(&format!("/api/v1/courses/{course}/enroll"), Some(&student), json!({}))
        .await
        .assert_status(StatusCode::CONFLICT);
}
