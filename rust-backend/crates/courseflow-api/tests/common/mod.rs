//! Shared test harness: a router wired to the `#[sqlx::test]` pool, a fake
//! billing provider and a fast hasher. Requests go through
//! `tower::ServiceExt::oneshot`, so no port is bound.

#![allow(dead_code, clippy::unwrap_used, clippy::expect_used)]

use std::net::SocketAddr;
use std::sync::Arc;

use axum::Router;
use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{Method, Request, StatusCode, header};
use courseflow_api::app::{Dependencies, build_router, build_state};
use courseflow_app::auth::Argon2Hasher;
use courseflow_app::billing::FakeBillingClient;
use courseflow_app::config::Config;
use courseflow_core::ports::SystemClock;
use http_body_util::BodyExt;
use serde_json::{Value, json};
use sqlx::PgPool;
use tower::ServiceExt;

pub struct TestApp {
    pub router: Router,
    pub pool: PgPool,
    pub billing: Arc<FakeBillingClient>,
    pub state: courseflow_api::AppState,
}

pub async fn spawn(pool: PgPool) -> TestApp {
    let config = Config::for_tests("postgres://unused");
    let billing = FakeBillingClient::shared();
    let deps = Dependencies {
        pool: pool.clone(),
        redis: None,
        billing: billing.clone(),
        hasher: Arc::new(Argon2Hasher::insecure_for_tests()),
        clock: Arc::new(SystemClock),
    };
    let state = build_state(config, deps);
    let router = build_router(state.clone()).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 4444))));
    TestApp { router, pool, billing, state }
}

pub struct Response {
    pub status: StatusCode,
    pub headers: axum::http::HeaderMap,
    pub body: Value,
}

impl Response {
    pub fn assert_status(&self, expected: StatusCode) -> &Self {
        assert_eq!(self.status, expected, "unexpected status, body: {}", self.body);
        self
    }

    pub fn str(&self, key: &str) -> &str {
        self.body[key].as_str().unwrap_or_else(|| panic!("no string field {key} in {}", self.body))
    }
}

impl TestApp {
    pub async fn request(&self, method: Method, path: &str, token: Option<&str>, body: Option<Value>) -> Response {
        let mut builder = Request::builder().method(method).uri(path);
        if let Some(token) = token {
            builder = builder.header(header::AUTHORIZATION, format!("Bearer {token}"));
        }
        let request = match body {
            Some(json) => {
                builder.header(header::CONTENT_TYPE, "application/json").body(Body::from(json.to_string())).unwrap()
            }
            None => builder.body(Body::empty()).unwrap(),
        };
        self.send(request).await
    }

    pub async fn send(&self, request: Request<Body>) -> Response {
        let response = self.router.clone().oneshot(request).await.unwrap();
        let status = response.status();
        let headers = response.headers().clone();
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        let body = if bytes.is_empty() {
            Value::Null
        } else {
            serde_json::from_slice(&bytes).unwrap_or(Value::String(String::from_utf8_lossy(&bytes).into_owned()))
        };
        Response { status, headers, body }
    }

    pub async fn get(&self, path: &str, token: Option<&str>) -> Response {
        self.request(Method::GET, path, token, None).await
    }

    pub async fn post(&self, path: &str, token: Option<&str>, body: Value) -> Response {
        self.request(Method::POST, path, token, Some(body)).await
    }

    /// Registers a user and returns `(user_id, access_token, refresh_token)`.
    pub async fn register_and_login(&self, email: &str) -> (String, String, String) {
        let r = self
            .post(
                "/api/v1/auth/register",
                None,
                json!({"email": email, "display_name": "Test", "password": "correct-horse-42"}),
            )
            .await;
        r.assert_status(StatusCode::CREATED);
        let user_id = r.str("id").to_owned();
        let r = self.post("/api/v1/auth/login", None, json!({"email": email, "password": "correct-horse-42"})).await;
        r.assert_status(StatusCode::OK);
        (user_id, r.str("access_token").to_owned(), r.str("refresh_token").to_owned())
    }

    /// Promotes directly in the database: tests should not depend on an
    /// admin bootstrap flow.
    pub async fn set_role(&self, user_id: &str, role: &str) {
        sqlx::query("UPDATE users SET role = $2 WHERE id = $1::uuid")
            .bind(user_id)
            .bind(role)
            .execute(&self.pool)
            .await
            .unwrap();
    }

    pub async fn author(&self, email: &str) -> (String, String) {
        let (id, _, _) = self.register_and_login(email).await;
        self.set_role(&id, "author").await;
        // role is embedded in the token: log in again after promotion
        let r = self.post("/api/v1/auth/login", None, json!({"email": email, "password": "correct-horse-42"})).await;
        (id, r.str("access_token").to_owned())
    }

    pub async fn published_course(&self, author_token: &str, title: &str, price: &str) -> (String, Vec<String>) {
        let r = self.post("/api/v1/courses", Some(author_token), json!({"title": title, "price": price})).await;
        r.assert_status(StatusCode::CREATED);
        let course_id = r.str("id").to_owned();
        let mut lessons = vec![];
        for (i, t) in ["Intro", "Ownership"].iter().enumerate() {
            let r = self
                .post(
                    &format!("/api/v1/courses/{course_id}/lessons"),
                    Some(author_token),
                    json!({"title": t, "content_md": "# hi", "is_free_preview": i == 0}),
                )
                .await;
            r.assert_status(StatusCode::CREATED);
            lessons.push(r.str("id").to_owned());
        }
        self.post(&format!("/api/v1/courses/{course_id}/publish"), Some(author_token), json!({}))
            .await
            .assert_status(StatusCode::OK);
        (course_id, lessons)
    }
}
