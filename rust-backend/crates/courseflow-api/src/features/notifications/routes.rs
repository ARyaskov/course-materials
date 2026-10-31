//! Three delivery paths for the same events: REST (`GET /notifications`),
//! WebSocket (`/ws`) and SSE (`/notifications/stream`). REST is the record;
//! the two push channels only tell clients "something new arrived".

use std::convert::Infallible;
use std::time::Duration;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::routing::{get, post};
use axum::{Json, Router};
use courseflow_app::notifications::WireEvent;
use courseflow_core::ids::{NotificationId, UserId};
use futures::stream::Stream;
use futures::{SinkExt, StreamExt};
use serde::Deserialize;
use tokio::sync::broadcast;

use crate::features::notifications::dto::*;
use crate::http::error::{ApiError, ApiResult};
use crate::http::extractors::CurrentUser;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/notifications", get(list))
        .route("/notifications/unread", get(unread))
        .route("/notifications/{id}/read", post(mark_read))
        .route("/notifications/stream", get(sse_stream))
        .route("/ws", get(ws_upgrade))
}

#[utoipa::path(get, path = "/api/v1/notifications", tag = "notifications", security(("bearer" = [])),
    responses((status = 200, body = Vec<NotificationResponse>)))]
pub async fn list(State(state): State<AppState>, user: CurrentUser) -> ApiResult<Json<Vec<NotificationResponse>>> {
    let items = state.notifications.list_recent(user.id, 50).await?;
    Ok(Json(items.into_iter().map(Into::into).collect()))
}

#[utoipa::path(get, path = "/api/v1/notifications/unread", tag = "notifications", security(("bearer" = [])),
    responses((status = 200, body = UnreadResponse)))]
pub async fn unread(State(state): State<AppState>, user: CurrentUser) -> ApiResult<Json<UnreadResponse>> {
    Ok(Json(UnreadResponse { unread: state.notifications.unread_count(user.id).await? }))
}

#[utoipa::path(post, path = "/api/v1/notifications/{id}/read", tag = "notifications", security(("bearer" = [])),
    params(("id" = NotificationId, Path)), responses((status = 204), (status = 404)))]
pub async fn mark_read(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<NotificationId>,
) -> ApiResult<StatusCode> {
    if state.notifications.mark_read(user.id, id).await? {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ApiError::NotFound("notification"))
    }
}

/// Server-Sent Events: one-directional, plain HTTP, reconnects for free in
/// browsers. Enough for notifications; WebSocket below exists for clients
/// that also need to send.
#[utoipa::path(get, path = "/api/v1/notifications/stream", tag = "notifications", security(("bearer" = [])),
    responses((status = 200, description = "text/event-stream")))]
pub async fn sse_stream(
    State(state): State<AppState>,
    user: CurrentUser,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let rx = state.notifications.bus().subscribe_local();
    let stream = user_events(rx, user.id).map(|event| {
        let data = serde_json::to_string(&event).unwrap_or_default();
        Ok(Event::default().id(event.id.to_string()).event(event.event.kind()).data(data))
    });
    Sse::new(stream).keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("ping"))
}

/// Browsers cannot set `Authorization` on the WebSocket handshake, so the
/// token may also come as `?token=`. It is verified before the upgrade is
/// accepted: an unauthenticated socket never exists.
#[derive(Debug, Deserialize)]
pub struct WsQuery {
    token: Option<String>,
}

pub async fn ws_upgrade(
    State(state): State<AppState>,
    ws: WebSocketUpgrade,
    user: Option<CurrentUser>,
    Query(q): Query<WsQuery>,
) -> ApiResult<impl IntoResponse> {
    let user_id = match (user, q.token) {
        (Some(u), _) => u.id,
        (None, Some(token)) => {
            state.auth.authenticate(&token).map(|(id, _)| id).map_err(|_| ApiError::Unauthorized("invalid token"))?
        }
        (None, None) => return Err(ApiError::Unauthorized("authentication required")),
    };
    let rx = state.notifications.bus().subscribe_local();
    metrics::gauge!("courseflow_ws_connections").increment(1.0);
    Ok(ws.on_upgrade(move |socket| async move {
        handle_socket(socket, user_id, rx).await;
        metrics::gauge!("courseflow_ws_connections").decrement(1.0);
    }))
}

async fn handle_socket(socket: WebSocket, user_id: UserId, rx: broadcast::Receiver<WireEvent>) {
    let (mut sink, mut source) = socket.split();
    let mut events = Box::pin(user_events(rx, user_id));
    let mut heartbeat = tokio::time::interval(Duration::from_secs(30));
    heartbeat.tick().await; // first tick fires immediately; skip it

    // One task, one loop, `select!` over three sources: outgoing events,
    // incoming frames (close / pong), heartbeat. Nothing here blocks.
    loop {
        tokio::select! {
            event = events.next() => {
                let Some(event) = event else { break };
                let Ok(text) = serde_json::to_string(&event) else { continue };
                if sink.send(Message::Text(text.into())).await.is_err() {
                    break;
                }
            }
            frame = source.next() => {
                match frame {
                    Some(Ok(Message::Close(_))) | None | Some(Err(_)) => break,
                    Some(Ok(Message::Ping(payload))) => {
                        if sink.send(Message::Pong(payload)).await.is_err() { break; }
                    }
                    Some(Ok(_)) => {} // clients do not send commands in v1; ignore
                }
            }
            _ = heartbeat.tick() => {
                if sink.send(Message::Ping(Vec::new().into())).await.is_err() {
                    break;
                }
            }
        }
    }
    tracing::debug!(%user_id, "websocket closed");
}

/// Filters the process-wide broadcast down to one user's events. A lagging
/// consumer skips missed messages instead of breaking the connection: the
/// REST endpoint remains the source of truth.
fn user_events(rx: broadcast::Receiver<WireEvent>, user_id: UserId) -> impl Stream<Item = WireEvent> {
    futures::stream::unfold(rx, move |mut rx| async move {
        loop {
            match rx.recv().await {
                Ok(event) if event.user_id == user_id => return Some((event, rx)),
                Ok(_) => continue,
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    tracing::warn!(%user_id, skipped = n, "notification stream lagged");
                    continue;
                }
                Err(broadcast::error::RecvError::Closed) => return None,
            }
        }
    })
}
