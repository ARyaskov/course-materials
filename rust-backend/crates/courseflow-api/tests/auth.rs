#![allow(clippy::unwrap_used, clippy::expect_used)]
mod common;

use axum::http::StatusCode;
use serde_json::json;
use sqlx::PgPool;

#[sqlx::test(migrations = "../../migrations")]
async fn register_login_and_me(pool: PgPool) {
    let app = common::spawn(pool).await;
    let (user_id, access, _) = app.register_and_login("alice@example.com").await;

    let me = app.get("/api/v1/me", Some(&access)).await;
    me.assert_status(StatusCode::OK);
    assert_eq!(me.str("id"), user_id);
    assert_eq!(me.str("email"), "alice@example.com");
    assert_eq!(me.str("role"), "student");
}

#[sqlx::test(migrations = "../../migrations")]
async fn duplicate_email_is_409_problem(pool: PgPool) {
    let app = common::spawn(pool).await;
    app.register_and_login("bob@example.com").await;
    let r = app
        .post(
            "/api/v1/auth/register",
            None,
            json!({"email": "BOB@example.com", "display_name": "Bob", "password": "correct-horse-42"}),
        )
        .await;
    r.assert_status(StatusCode::CONFLICT);
    assert_eq!(r.headers["content-type"], "application/problem+json");
    assert_eq!(r.str("code"), "conflict");
    assert!(r.body["request_id"].is_string(), "problem carries request id: {}", r.body);
}

#[sqlx::test(migrations = "../../migrations")]
async fn weak_password_is_422_with_field_errors(pool: PgPool) {
    let app = common::spawn(pool).await;
    let r = app
        .post(
            "/api/v1/auth/register",
            None,
            json!({"email": "x@example.com", "display_name": "X", "password": "short"}),
        )
        .await;
    r.assert_status(StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(r.body["errors"][0]["field"], "password");
}

#[sqlx::test(migrations = "../../migrations")]
async fn wrong_password_and_unknown_user_look_the_same(pool: PgPool) {
    let app = common::spawn(pool).await;
    app.register_and_login("carol@example.com").await;
    let wrong =
        app.post("/api/v1/auth/login", None, json!({"email": "carol@example.com", "password": "wrong-horse-42"})).await;
    let unknown = app
        .post("/api/v1/auth/login", None, json!({"email": "nobody@example.com", "password": "wrong-horse-42"}))
        .await;
    wrong.assert_status(StatusCode::UNAUTHORIZED);
    unknown.assert_status(StatusCode::UNAUTHORIZED);
    assert_eq!(wrong.body["detail"], unknown.body["detail"]);
}

#[sqlx::test(migrations = "../../migrations")]
async fn refresh_rotates_and_detects_reuse(pool: PgPool) {
    let app = common::spawn(pool).await;
    let (_, _, refresh1) = app.register_and_login("dave@example.com").await;

    let r = app.post("/api/v1/auth/refresh", None, json!({"refresh_token": refresh1})).await;
    r.assert_status(StatusCode::OK);
    let refresh2 = r.str("refresh_token").to_owned();
    assert_ne!(refresh1, refresh2);

    // Replaying the rotated token is treated as theft: the family dies.
    app.post("/api/v1/auth/refresh", None, json!({"refresh_token": refresh1}))
        .await
        .assert_status(StatusCode::UNAUTHORIZED);
    app.post("/api/v1/auth/refresh", None, json!({"refresh_token": refresh2}))
        .await
        .assert_status(StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn expired_or_garbage_token_is_401(pool: PgPool) {
    let app = common::spawn(pool).await;
    app.get("/api/v1/me", Some("not.a.jwt")).await.assert_status(StatusCode::UNAUTHORIZED);
    app.get("/api/v1/me", None).await.assert_status(StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn password_reset_flow(pool: PgPool) {
    let app = common::spawn(pool.clone()).await;
    let (user_id, _, _) = app.register_and_login("erin@example.com").await;
    app.post("/api/v1/auth/forgot-password", None, json!({"email": "erin@example.com"}))
        .await
        .assert_status(StatusCode::ACCEPTED);
    // unknown e-mail: same answer, nothing leaks
    app.post("/api/v1/auth/forgot-password", None, json!({"email": "ghost@example.com"}))
        .await
        .assert_status(StatusCode::ACCEPTED);

    // The token only exists as a hash; the test mints its own through the
    // service to avoid parsing logs.
    let secret = courseflow_app::auth::tokens::generate_secret();
    let now = chrono::Utc::now();
    courseflow_app::auth::refresh::insert_action_token(
        &pool,
        courseflow_core::ids::UserId(user_id.parse().unwrap()),
        courseflow_app::auth::refresh::ActionPurpose::PasswordReset,
        &courseflow_app::auth::tokens::digest(&secret),
        now + chrono::Duration::minutes(10),
    )
    .await
    .unwrap();

    app.post("/api/v1/auth/reset-password", None, json!({"token": secret, "new_password": "new-horse-4242"}))
        .await
        .assert_status(StatusCode::NO_CONTENT);
    // single use
    app.post("/api/v1/auth/reset-password", None, json!({"token": secret, "new_password": "new-horse-4242"}))
        .await
        .assert_status(StatusCode::UNAUTHORIZED);
    app.post("/api/v1/auth/login", None, json!({"email": "erin@example.com", "password": "correct-horse-42"}))
        .await
        .assert_status(StatusCode::UNAUTHORIZED);
    app.post("/api/v1/auth/login", None, json!({"email": "erin@example.com", "password": "new-horse-4242"}))
        .await
        .assert_status(StatusCode::OK);
}
