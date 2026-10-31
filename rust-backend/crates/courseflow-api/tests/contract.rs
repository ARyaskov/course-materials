#![allow(clippy::unwrap_used, clippy::expect_used)]
//! Contract-level checks that do not need a database: health, OpenAPI
//! snapshot, 404 problem shape.

mod common;

use axum::http::StatusCode;
use sqlx::PgPool;

#[sqlx::test(migrations = "../../migrations")]
async fn health_and_openapi(pool: PgPool) {
    let app = common::spawn(pool).await;
    app.get("/health/live", None).await.assert_status(StatusCode::OK);
    let ready = app.get("/health/ready", None).await;
    ready.assert_status(StatusCode::OK);
    assert_eq!(ready.body["checks"][0]["name"], "postgres");

    let doc = app.get("/api/docs/openapi.json", None).await;
    doc.assert_status(StatusCode::OK);
    let paths: Vec<&str> = doc.body["paths"].as_object().unwrap().keys().map(String::as_str).collect();
    // The route list is part of the contract: a renamed path fails here first.
    insta::assert_json_snapshot!("openapi_paths", paths);
}

#[sqlx::test(migrations = "../../migrations")]
async fn unknown_route_is_problem_json(pool: PgPool) {
    let app = common::spawn(pool).await;
    let r = app.get("/api/v1/nope", None).await;
    r.assert_status(StatusCode::NOT_FOUND);
    assert_eq!(r.headers["content-type"], "application/problem+json");
    assert_eq!(r.str("type"), "https://courseflow.dev/errors/not_found");
}
