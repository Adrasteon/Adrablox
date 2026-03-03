use crate::{AppState, Config};
use axum::{
    extract::{ConnectInfo, State},
    extract::{WebSocketUpgrade, ws::{CloseFrame, Message, WebSocket, close_code}},
    http::HeaderMap,
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use mcp_core::JsonRpcRequest;
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::{net::SocketAddr, sync::Arc};
use std::time::Instant;
use tokio::sync::broadcast;
use tokio::time::{Duration, interval};
use tracing::warn;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BackpressurePolicy {
    DropOldest,
    Disconnect,
}

pub fn register_ws_routes(
    router: Router<Arc<AppState>>,
    _state: Arc<AppState>,
    _config: Config,
) -> Router<Arc<AppState>> {
    router
        .route("/mcp-stream", get(handle_ws_upgrade))
        .route("/mcp-stream/ws-rpc", get(handle_ws_rpc_upgrade))
}

pub async fn handle_ws_upgrade(
    State(state): State<Arc<AppState>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| ws_handler(socket, state))
}

async fn ws_handler(mut socket: WebSocket, state: Arc<AppState>) {
    let mut rx = state.broadcaster.subscribe();
    let mut send_queue: VecDeque<String> = VecDeque::new();
    let queue_capacity = state.config.client_send_queue_capacity.max(1);
    let policy = parse_backpressure_policy(&state.config.ws_backpressure_policy);
    let ping_interval = Duration::from_millis(state.config.ws_ping_interval_ms.max(1));
    let ping_timeout = Duration::from_millis(state.config.ws_ping_timeout_ms.max(1));
    let mut ping_tick = interval(ping_interval);
    let mut last_pong = Instant::now();

    loop {
        if let Some(next) = send_queue.pop_front() {
            if socket.send(Message::Text(next.into())).await.is_err() {
                break;
            }
            continue;
        }

        tokio::select! {
            recv_result = rx.recv() => {
                match recv_result {
                    Ok(val) => {
                        if send_queue.len() >= queue_capacity {
                            match policy {
                                BackpressurePolicy::DropOldest => {
                                    let _ = send_queue.pop_front();
                                    warn!("ws backpressure: dropping oldest queued message");
                                }
                                BackpressurePolicy::Disconnect => {
                                    let _ = socket.send(Message::Close(Some(CloseFrame{ code: close_code::POLICY, reason: "backpressure-disconnect".into() }))).await;
                                    break;
                                }
                            }
                        }
                        send_queue.push_back(val.to_string());
                    }
                    Err(broadcast::error::RecvError::Lagged(_)) => {
                        continue;
                    }
                    Err(broadcast::error::RecvError::Closed) => {
                        let _ = socket.send(Message::Close(Some(CloseFrame{ code: close_code::NORMAL, reason: "server-shutdown".into() }))).await;
                        break;
                    }
                }
            }
            inbound = socket.recv() => {
                match inbound {
                    Some(Ok(Message::Pong(_))) => {
                        last_pong = Instant::now();
                    }
                    Some(Ok(Message::Ping(payload))) => {
                        let _ = socket.send(Message::Pong(payload)).await;
                        last_pong = Instant::now();
                    }
                    Some(Ok(Message::Close(_))) | None => break,
                    Some(Ok(_)) => {}
                    Some(Err(_)) => break,
                }
            }
            _ = ping_tick.tick() => {
                if last_pong.elapsed() > ping_timeout {
                    let _ = socket.send(Message::Close(Some(CloseFrame{ code: close_code::NORMAL, reason: "ping-timeout".into() }))).await;
                    break;
                }
                if socket.send(Message::Ping(Vec::new().into())).await.is_err() {
                    break;
                }
            }
        }
    }
}

async fn handle_ws_rpc_upgrade(
    State(state): State<Arc<AppState>>,
    connect_info: Option<ConnectInfo<SocketAddr>>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    let remote = connect_info.map(|c| c.0);
    if !allow_ws_rpc_upgrade(state.config.enable_ws_rpc, remote) {
        return (
            StatusCode::FORBIDDEN,
            Json(json!({
                "error": "ws-rpc upgrade disabled for non-local clients",
                "errorCode": "WS_RPC_DISABLED"
            })),
        )
            .into_response();
    }

    if let Err(err) = validate_upgrade(&headers, &state) {
        return err.into_response();
    }

    ws.on_upgrade(move |socket| ws_rpc_handler(socket, state))
        .into_response()
}

async fn ws_rpc_handler(mut socket: WebSocket, state: Arc<AppState>) {
    let ping_interval = Duration::from_millis(state.config.ws_ping_interval_ms.max(1));
    let ping_timeout = Duration::from_millis(state.config.ws_ping_timeout_ms.max(1));
    let mut ping_tick = interval(ping_interval);
    let mut last_pong = Instant::now();

    loop {
        let message = tokio::select! {
            inbound = socket.recv() => {
                match inbound {
                    Some(Ok(msg)) => msg,
                    Some(Err(_)) | None => break,
                }
            }
            _ = ping_tick.tick() => {
                if last_pong.elapsed() > ping_timeout {
                    let _ = socket.send(Message::Close(Some(CloseFrame{ code: close_code::NORMAL, reason: "ping-timeout".into() }))).await;
                    break;
                }
                if socket.send(Message::Ping(Vec::new().into())).await.is_err() {
                    break;
                }
                continue;
            }
        };

        match message {
            Message::Text(text) => {
                if text.len() > state.config.max_ws_message_size {
                    let _ = socket
                        .send(Message::Text(
                            json!({
                                "jsonrpc": "2.0",
                                "id": null,
                                "error": {
                                    "code": -32600,
                                    "message": "request payload exceeds MCP_MAX_WS_MESSAGE_SIZE",
                                    "data": { "code": "REQUEST_TOO_LARGE" }
                                }
                            })
                            .to_string(),
                        ))
                        .await;
                    let _ = socket.close().await;
                    break;
                }

                let parsed: Value = match serde_json::from_str(&text) {
                    Ok(value) => value,
                    Err(_) => {
                        let _ = socket
                            .send(Message::Text(
                                json!({
                                    "jsonrpc": "2.0",
                                    "id": null,
                                    "error": {
                                        "code": -32600,
                                        "message": "invalid ws-rpc payload",
                                        "data": { "code": "INVALID_REQUEST" }
                                    }
                                })
                                .to_string(),
                            ))
                            .await;
                        let _ = socket.close().await;
                        break;
                    }
                };

                if parsed.get("cmd").and_then(Value::as_str) == Some("replay") {
                    let since = parsed
                        .get("since")
                        .and_then(Value::as_u64)
                        .unwrap_or(0);
                    let limit = parsed
                        .get("limit")
                        .and_then(Value::as_u64)
                        .map(|v| v as usize)
                        .unwrap_or(100)
                        .clamp(1, 1_000);
                    let (_latest_seq, events) = crate::replay_events_since(&state, since, limit);
                    for event in events {
                        if socket.send(Message::Text(event.to_string())).await.is_err() {
                            break;
                        }
                    }
                    continue;
                }

                let request: JsonRpcRequest = match serde_json::from_value(parsed) {
                    Ok(req) => req,
                    Err(_) => {
                        let _ = socket
                            .send(Message::Text(
                                json!({
                                    "jsonrpc": "2.0",
                                    "id": null,
                                    "error": {
                                        "code": -32600,
                                        "message": "invalid ws-rpc payload",
                                        "data": { "code": "INVALID_REQUEST" }
                                    }
                                })
                                .to_string(),
                            ))
                            .await;
                        let _ = socket.close().await;
                        break;
                    }
                };

                let (_status, response) = crate::handle_mcp_request(state.clone(), request).await;
                if socket.send(Message::Text(response.0.to_string())).await.is_err() {
                    break;
                }
            }
            Message::Close(_) => break,
            Message::Ping(payload) => {
                if socket.send(Message::Pong(payload)).await.is_err() {
                    break;
                }
                last_pong = Instant::now();
            }
            Message::Pong(_) => {
                last_pong = Instant::now();
                continue;
            }
            Message::Binary(_) => {
                // ignore non-text rpc payloads for now
                continue;
            }
        }
    }
}

fn parse_backpressure_policy(value: &str) -> BackpressurePolicy {
    if value.eq_ignore_ascii_case("disconnect") {
        BackpressurePolicy::Disconnect
    } else {
        BackpressurePolicy::DropOldest
    }
}

fn validate_upgrade(headers: &HeaderMap, state: &AppState) -> Result<(), (StatusCode, Json<serde_json::Value>)> {
    if !state.config.require_ws_token {
        return Ok(());
    }

    let expected = match state.config.ws_auth_token.as_deref() {
        Some(token) if !token.is_empty() => token,
        _ => {
            return Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({
                    "error": "MCP_REQUIRE_WS_TOKEN is enabled but MCP_WS_AUTH_TOKEN is not configured",
                    "errorCode": "WS_AUTH_CONFIG_MISSING"
                })),
            ));
        }
    };

    let provided = extract_ws_token(headers);
    match provided {
        Some(token) if token == expected => Ok(()),
        _ => Err((
            StatusCode::FORBIDDEN,
            Json(json!({
                "error": "ws-rpc authentication failed",
                "errorCode": "WS_AUTH_FAILED"
            })),
        )),
    }
}

fn extract_ws_token(headers: &HeaderMap) -> Option<String> {
    if let Some(auth_header) = headers.get("authorization").and_then(|v| v.to_str().ok()) {
        let trimmed = auth_header.trim();
        if let Some(rest) = trimmed.strip_prefix("Bearer ") {
            let token = rest.trim();
            if !token.is_empty() {
                return Some(token.to_string());
            }
        }
    }

    if let Some(protocol_header) = headers
        .get("sec-websocket-protocol")
        .and_then(|v| v.to_str().ok())
    {
        let parts: Vec<&str> = protocol_header.split(',').map(|p| p.trim()).collect();
        if parts.len() >= 2 && parts[0].eq_ignore_ascii_case("bearer") {
            let token = parts[1].trim();
            if !token.is_empty() {
                return Some(token.to_string());
            }
        }

        for part in parts {
            if let Some(rest) = part.strip_prefix("Bearer ") {
                let token = rest.trim();
                if !token.is_empty() {
                    return Some(token.to_string());
                }
            }
        }
    }

    None
}

fn allow_ws_rpc_upgrade(enable_ws_rpc: bool, remote: Option<SocketAddr>) -> bool {
    enable_ws_rpc || is_local_remote(remote)
}

fn is_local_remote(remote: Option<SocketAddr>) -> bool {
    remote.map(|addr| addr.ip().is_loopback()).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::{
        BackpressurePolicy, allow_ws_rpc_upgrade, extract_ws_token, is_local_remote,
        parse_backpressure_policy,
    };
    use axum::http::HeaderMap;
    use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};

    #[test]
    fn local_remote_detection() {
        let local = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 50000));
        let non_local = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(10, 0, 0, 10), 50000));

        assert!(is_local_remote(Some(local)));
        assert!(!is_local_remote(Some(non_local)));
        assert!(!is_local_remote(None));
    }

    #[test]
    fn ws_rpc_upgrade_gating() {
        let local = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 50000));
        let non_local = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(10, 0, 0, 10), 50000));

        assert!(allow_ws_rpc_upgrade(true, Some(non_local)));
        assert!(allow_ws_rpc_upgrade(false, Some(local)));
        assert!(!allow_ws_rpc_upgrade(false, Some(non_local)));
        assert!(!allow_ws_rpc_upgrade(false, None));
    }

    #[test]
    fn extract_token_from_authorization_header() {
        let mut headers = HeaderMap::new();
        headers.insert("authorization", "Bearer stage-c-token".parse().unwrap());
        assert_eq!(extract_ws_token(&headers).as_deref(), Some("stage-c-token"));
    }

    #[test]
    fn extract_token_from_websocket_protocol_header() {
        let mut headers = HeaderMap::new();
        headers.insert("sec-websocket-protocol", "bearer, stage-c-token".parse().unwrap());
        assert_eq!(extract_ws_token(&headers).as_deref(), Some("stage-c-token"));
    }

    #[test]
    fn parse_backpressure_policy_defaults_to_drop_oldest() {
        assert_eq!(
            parse_backpressure_policy("drop_oldest"),
            BackpressurePolicy::DropOldest
        );
        assert_eq!(
            parse_backpressure_policy("unknown-value"),
            BackpressurePolicy::DropOldest
        );
        assert_eq!(
            parse_backpressure_policy("disconnect"),
            BackpressurePolicy::Disconnect
        );
    }
}
