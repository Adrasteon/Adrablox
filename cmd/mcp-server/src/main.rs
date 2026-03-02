use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use mcp_core::{initialize_result, invalid_request, InitializeParams, JsonRpcRequest};
use rojo_adapter::RojoAdapter;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::{
    collections::VecDeque,
    collections::HashMap,
    fs,
    net::SocketAddr,
    sync::{Arc, Mutex},
};
use tokio::sync::broadcast;
use tracing::info;
mod config;
use config::Config;
mod ws;

#[derive(Clone)]
struct AppState {
    adapter: RojoAdapter,
    server_version: String,
    sessions: Arc<Mutex<HashMap<String, SessionState>>>,
    broadcaster: broadcast::Sender<serde_json::Value>,
    replay: Arc<Mutex<ReplayState>>,
    config: Config,
}

#[derive(Debug, Clone)]
struct ReplayState {
    next_seq: u64,
    events: VecDeque<Value>,
}

impl ReplayState {
    fn new() -> Self {
        Self {
            next_seq: 0,
            events: VecDeque::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
struct InstanceNode {
    #[serde(rename = "Id")]
    id: String,
    #[serde(rename = "Parent")]
    parent: Option<String>,
    #[serde(rename = "Name")]
    name: String,
    #[serde(rename = "ClassName")]
    class_name: String,
    #[serde(rename = "Properties")]
    properties: Map<String, Value>,
    #[serde(rename = "Children")]
    children: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
struct UpdatedInstance {
    id: String,
    #[serde(rename = "changedName", skip_serializing_if = "Option::is_none")]
    changed_name: Option<String>,
    #[serde(rename = "changedProperties")]
    changed_properties: Map<String, Value>,
}

#[derive(Debug, Clone)]
struct ChangeBatch {
    cursor: u64,
    added: HashMap<String, InstanceNode>,
    updated: Vec<UpdatedInstance>,
    removed: Vec<String>,
}

#[derive(Debug, Clone)]
struct SessionState {
    cursor: u64,
    applied_patches: HashMap<String, u64>,
    property_last_write: HashMap<String, u64>,
    project_path: String,
    root_id: String,
    instances: HashMap<String, InstanceNode>,
    file_paths: HashMap<String, String>,
    changes: Vec<ChangeBatch>,
}

#[derive(Debug, Deserialize)]
struct RojoOpenRequest {
    #[serde(rename = "projectPath")]
    project_path: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ReadQuery {
    #[serde(rename = "sessionId")]
    session_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ReplayQuery {
    since: Option<String>,
    limit: Option<usize>,
}

const SESSION_NOT_FOUND_CODE: &str = "SESSION_NOT_FOUND";
const CONFLICT_WRITE_STALE_CURSOR: &str = "CONFLICT_WRITE_STALE_CURSOR";
const UNSUPPORTED_FILE_BACKED_MUTATION: &str = "UNSUPPORTED_FILE_BACKED_MUTATION";
const SOURCE_WRITE_FAILED: &str = "SOURCE_WRITE_FAILED";
const SOURCE_PATH_MISSING: &str = "SOURCE_PATH_MISSING";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            std::env::var("RUST_LOG")
                .unwrap_or_else(|_| "mcp_server=debug,axum=debug,tower_http=debug".to_string()),
        )
        .init();

    let (bcast_tx, _) = broadcast::channel(128);

    // Load runtime configuration (env-driven). Defaults favor localhost development.
    let cfg = Config::from_env();

    let state = Arc::new(AppState {
        adapter: RojoAdapter::new(),
        server_version: env!("CARGO_PKG_VERSION").to_string(),
        sessions: Arc::new(Mutex::new(HashMap::new())),
        broadcaster: bcast_tx,
        replay: Arc::new(Mutex::new(ReplayState::new())),
        config: cfg.clone(),
    });

    let app = Router::new()
        .route("/health", get(health))
        .route("/mcp", post(handle_mcp))
        .route("/api/rojo", post(handle_rojo_open))
        .route("/api/read/:instance_id", get(handle_rojo_read_by_instance))
        .route(
            "/api/read/:session_id/:instance_id",
            get(handle_rojo_read_by_session_and_instance),
        )
        .route("/api/subscribe/:session_id", get(handle_rojo_subscribe))
        .route(
            "/api/subscribe/:session_id/:cursor",
            get(handle_rojo_subscribe_with_cursor),
        )
        .route("/mcp/replay", get(handle_mcp_replay));
    let app = ws::register_ws_routes(app, state.clone(), cfg.clone());
    let app = app.with_state(state.clone());

    let addr: SocketAddr = cfg.bind_addr.parse()?;
    info!(%addr, "mcp-server listening");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>()).await?;
    Ok(())
}

async fn health() -> impl IntoResponse {
    Json(json!({"ok": true, "service": "mcp-server"}))
}

fn tool_ok(id: Value, payload: Value) -> (StatusCode, Json<Value>) {
    (
        StatusCode::OK,
        Json(json!({
            "jsonrpc": "2.0",
            "id": id,
            "result": {
                "content": [{
                    "type": "text",
                    "text": payload.to_string()
                }],
                "structuredContent": payload
            }
        })),
    )
}

fn sanitize_tool_name(orig: &str) -> String {
    let mut out = String::with_capacity(orig.len());
    for c in orig.chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c.to_ascii_lowercase());
        } else {
            out.push('-');
        }
    }
    // collapse consecutive hyphens
    let mut compact = String::with_capacity(out.len());
    let mut last_dash = false;
    for ch in out.chars() {
        if ch == '-' {
            if !last_dash {
                compact.push(ch);
                last_dash = true;
            }
        } else {
            compact.push(ch);
            last_dash = false;
        }
    }
    compact.trim_matches('-').to_string()
}

fn session_not_found_rpc(id: Value) -> (StatusCode, Json<Value>) {
    (
        StatusCode::BAD_REQUEST,
        Json(json!({
            "jsonrpc": "2.0",
            "id": id,
            "error": {
                "code": -32001,
                "message": "session does not exist",
                "data": {
                    "code": SESSION_NOT_FOUND_CODE
                }
            }
        })),
    )
}

fn session_not_found_http() -> (StatusCode, Json<Value>) {
    (
        StatusCode::BAD_REQUEST,
        Json(json!({
            "error": "session does not exist",
            "errorCode": SESSION_NOT_FOUND_CODE
        })),
    )
}

#[cfg(test)]
fn make_default_session() -> SessionState {
    let root_id = "ref_root".to_string();
    let replicated_storage = "ref_replicated_storage".to_string();
    let server_script_service = "ref_server_script_service".to_string();

    let mut instances = HashMap::new();
    instances.insert(
        root_id.clone(),
        InstanceNode {
            id: root_id.clone(),
            parent: None,
            name: "Game".to_string(),
            class_name: "DataModel".to_string(),
            properties: Map::new(),
            children: vec![replicated_storage.clone(), server_script_service.clone()],
        },
    );
    instances.insert(
        replicated_storage.clone(),
        InstanceNode {
            id: replicated_storage,
            parent: Some(root_id.clone()),
            name: "ReplicatedStorage".to_string(),
            class_name: "ReplicatedStorage".to_string(),
            properties: Map::new(),
            children: vec![],
        },
    );
    instances.insert(
        server_script_service.clone(),
        InstanceNode {
            id: server_script_service,
            parent: Some(root_id.clone()),
            name: "ServerScriptService".to_string(),
            class_name: "ServerScriptService".to_string(),
            properties: Map::new(),
            children: vec![],
        },
    );

    SessionState {
        cursor: 0,
        applied_patches: HashMap::new(),
        property_last_write: HashMap::new(),
        project_path: "default.project.json".to_string(),
        root_id,
        instances,
        file_paths: HashMap::new(),
        changes: vec![],
    }
}

fn make_session_from_snapshot(project_path: &str, snapshot: rojo_adapter::ProjectSnapshot) -> SessionState {
    let instances = snapshot
        .instances
        .into_iter()
        .map(|(id, node)| {
            (
                id,
                InstanceNode {
                    id: node.id,
                    parent: node.parent,
                    name: node.name,
                    class_name: node.class_name,
                    properties: node.properties,
                    children: node.children,
                },
            )
        })
        .collect();

    SessionState {
        cursor: 0,
        applied_patches: HashMap::new(),
        property_last_write: HashMap::new(),
        project_path: project_path.to_string(),
        root_id: snapshot.root_id,
        instances,
        file_paths: snapshot.file_paths,
        changes: vec![],
    }
}

fn field_key(instance_id: &str, property: &str) -> String {
    format!("{}:{}", instance_id, property)
}

fn has_write_conflict(last_write_cursor: Option<u64>, base_cursor: u64) -> bool {
    matches!(last_write_cursor, Some(cursor) if cursor > base_cursor)
}

fn collect_subtree(instance_id: &str, instances: &HashMap<String, InstanceNode>, out: &mut Vec<String>) {
    out.push(instance_id.to_string());
    if let Some(node) = instances.get(instance_id) {
        for child in &node.children {
            collect_subtree(child, instances, out);
        }
    }
}

#[cfg(test)]
fn remove_subtree(instance_id: &str, instances: &mut HashMap<String, InstanceNode>, removed: &mut Vec<String>) {
    if let Some(node) = instances.get(instance_id).cloned() {
        for child in node.children {
            remove_subtree(&child, instances, removed);
        }
    }

    if let Some(node) = instances.remove(instance_id) {
        if let Some(parent_id) = node.parent {
            if let Some(parent) = instances.get_mut(&parent_id) {
                parent.children.retain(|child| child != instance_id);
            }
        }
        removed.push(instance_id.to_string());
    }
}

fn compute_filesystem_delta(
    session: &SessionState,
    next_instances: &HashMap<String, InstanceNode>,
) -> (HashMap<String, InstanceNode>, Vec<UpdatedInstance>, Vec<String>, Vec<String>) {
    let mut added = HashMap::new();
    let mut updated = vec![];
    let mut removed = vec![];
    let mut touched_fields = vec![];

    for (instance_id, next_node) in next_instances {
        match session.instances.get(instance_id) {
            None => {
                added.insert(instance_id.clone(), next_node.clone());
                touched_fields.push(field_key(instance_id, "Name"));
                for property in next_node.properties.keys() {
                    touched_fields.push(field_key(instance_id, property));
                }
            }
            Some(prev_node) => {
                let mut changed_name = None;
                let mut changed_properties = Map::new();

                if prev_node.name != next_node.name {
                    changed_name = Some(next_node.name.clone());
                    touched_fields.push(field_key(instance_id, "Name"));
                }

                for (property, value) in &next_node.properties {
                    let previous = prev_node.properties.get(property);
                    if previous != Some(value) {
                        changed_properties.insert(property.clone(), value.clone());
                        touched_fields.push(field_key(instance_id, property));
                    }
                }

                if !changed_properties.is_empty() || changed_name.is_some() {
                    updated.push(UpdatedInstance {
                        id: instance_id.clone(),
                        changed_name,
                        changed_properties,
                    });
                }
            }
        }
    }

    for instance_id in session.instances.keys() {
        if !next_instances.contains_key(instance_id) {
            removed.push(instance_id.clone());
        }
    }

    (added, updated, removed, touched_fields)
}

fn session_capabilities_payload() -> Value {
    json!({
        "supportsStructuralOps": false,
        "fileBackedMutationPolicy": {
            "allowSetName": false,
            "allowedSetProperty": ["Source"]
        }
    })
}

fn validate_snapshot(snapshot: &rojo_adapter::ProjectSnapshot) -> Vec<String> {
    let mut issues = Vec::new();
    if snapshot.instances.is_empty() {
        issues.push("snapshot has no instances".to_string());
    }
    if !snapshot.instances.contains_key(&snapshot.root_id) {
        issues.push("rootId missing in instances".to_string());
    }
    for key in snapshot.file_paths.keys() {
        if !snapshot.instances.contains_key(key) {
            issues.push(format!("filePaths references unknown instance {}", key));
        }
    }
    issues
}

fn normalize_event_to_envelope(seq: u64, event: Value) -> Value {
    let mut payload = match event {
        Value::Object(map) => map,
        other => {
            let mut map = Map::new();
            map.insert("data".to_string(), other);
            map
        }
    };

    let event_type = payload
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or("event")
        .to_string();
    let session_id = payload
        .get("sessionId")
        .and_then(Value::as_str)
        .map(|s| s.to_string());

    payload.remove("type");
    payload.remove("sessionId");

    let mut envelope = json!({
        "seq": seq,
        "type": event_type,
        "payload": Value::Object(payload),
    });

    if let Some(session_id) = session_id {
        envelope["sessionId"] = json!(session_id);
    }

    envelope
}

fn publish_event_with_replay(
    broadcaster: &broadcast::Sender<Value>,
    replay: Option<&Arc<Mutex<ReplayState>>>,
    seq_retention: usize,
    event: Value,
) {
    let outbound = if let Some(replay_state) = replay {
        let mut replay_state = replay_state.lock().expect("replay lock poisoned");
        replay_state.next_seq += 1;
        let envelope = normalize_event_to_envelope(replay_state.next_seq, event);
        replay_state.events.push_back(envelope.clone());
        while replay_state.events.len() > seq_retention {
            replay_state.events.pop_front();
        }
        envelope
    } else {
        event
    };

    let _ = broadcaster.send(outbound);
}

pub(crate) fn replay_events_since(state: &AppState, since: u64, limit: usize) -> (u64, Vec<Value>) {
    let replay_state = state.replay.lock().expect("replay lock poisoned");
    let latest_seq = replay_state.next_seq;
    let events = replay_state
        .events
        .iter()
        .filter(|event| event.get("seq").and_then(Value::as_u64).unwrap_or(0) > since)
        .take(limit)
        .cloned()
        .collect::<Vec<_>>();
    (latest_seq, events)
}

fn apply_snapshot_to_session(
    session: &mut SessionState,
    snapshot: rojo_adapter::ProjectSnapshot,
    chunk_size: usize,
    broadcaster: Option<&broadcast::Sender<serde_json::Value>>,
    replay: Option<&Arc<Mutex<ReplayState>>>,
    seq_retention: usize,
) -> (u64, usize, usize, usize) {
    // Convert instances hashmap into a vector for deterministic chunking
    let entries: Vec<(String, InstanceNode)> = snapshot
        .instances
        .into_iter()
        .map(|(id, node)| {
            (
                id,
                InstanceNode {
                    id: node.id,
                    parent: node.parent,
                    name: node.name,
                    class_name: node.class_name,
                    properties: node.properties,
                    children: node.children,
                },
            )
        })
        .collect();

    let total = entries.len();
    let mut chunks = 0_usize;
    let mut applied_cursor = session.cursor;

    for chunk in entries.chunks(chunk_size) {
        let mut added: HashMap<String, InstanceNode> = HashMap::new();
        for (id, node) in chunk {
            added.insert(id.clone(), node.clone());
        }

        applied_cursor = std::cmp::max(applied_cursor, session.cursor) + 1;
        // update property last write for Name and properties touched
        for (id, node) in &added {
            // Name
            session.property_last_write.insert(field_key(id, "Name"), applied_cursor);
            // properties
            for prop in node.properties.keys() {
                session.property_last_write.insert(field_key(id, prop), applied_cursor);
            }
        }

        session.changes.push(ChangeBatch {
            cursor: applied_cursor,
            added: added.clone(),
            updated: vec![],
            removed: vec![],
        });

        // Emit progress event for this chunk if broadcaster is available
        if let Some(tx) = broadcaster {
            let event = json!({
                "type": "importProgress",
                "sessionId": session.root_id.clone(),
                "chunk": chunks + 1,
                "appliedCursor": applied_cursor.to_string(),
                "addedCount": added.len()
            });
            publish_event_with_replay(tx, replay, seq_retention, event);
        }

        // merge added into session.instances
        for (id, node) in added.into_iter() {
            session.instances.insert(id, node);
        }

        session.cursor = applied_cursor;
        chunks += 1;
    }

    let file_backed = snapshot.file_paths.len();

    // merge file_paths
    for (k, v) in snapshot.file_paths.into_iter() {
        session.file_paths.insert(k, v);
    }

    (applied_cursor, total, file_backed, chunks)
}

fn open_session_for_project(state: &AppState, project_path: &str) -> Result<Value, String> {
    let mut result = state
        .adapter
        .open_session(project_path)
        .map_err(|err| err.to_string())?;

    let snapshot = state
        .adapter
        .snapshot_project(project_path)
        .map_err(|err| err.to_string())?;

    let session_id = result
        .get("sessionId")
        .and_then(Value::as_str)
        .ok_or_else(|| "missing sessionId from adapter".to_string())?
        .to_string();

    let file_backed_ids: Vec<String> = snapshot.file_paths.keys().cloned().collect();

    if let Some(map) = result.as_object_mut() {
        map.insert("sessionCapabilities".to_string(), session_capabilities_payload());
        map.insert("fileBackedInstanceIds".to_string(), json!(file_backed_ids));
    }

    let mut sessions = state.sessions.lock().expect("session lock poisoned");
    sessions.insert(session_id, make_session_from_snapshot(project_path, snapshot));

    Ok(result)
}

fn refresh_session_from_source(state: &AppState, session: &mut SessionState) {
    if let Ok(snapshot) = state.adapter.snapshot_project(&session.project_path) {
        let next_instances: HashMap<String, InstanceNode> = snapshot
            .instances
            .into_iter()
            .map(|(instance_id, node)| {
                (
                    instance_id,
                    InstanceNode {
                        id: node.id,
                        parent: node.parent,
                        name: node.name,
                        class_name: node.class_name,
                        properties: node.properties,
                        children: node.children,
                    },
                )
            })
            .collect();

        let (added, updated, removed, touched_fields) = compute_filesystem_delta(session, &next_instances);

        if !added.is_empty() || !updated.is_empty() || !removed.is_empty() {
            session.cursor += 1;
            for field in touched_fields {
                session.property_last_write.insert(field, session.cursor);
            }
            session.changes.push(ChangeBatch {
                cursor: session.cursor,
                added,
                updated,
                removed,
            });
            session.instances = next_instances;
            session.root_id = snapshot.root_id;
            session.file_paths = snapshot.file_paths;
        }
    }
}

fn read_tree_result(session: &SessionState, requested: Option<&str>, session_id: &str) -> Result<Value, String> {
    let instance_id = requested.unwrap_or(&session.root_id);
    if !session.instances.contains_key(instance_id) {
        return Err("instance does not exist".to_string());
    }

    let mut subtree_ids = vec![];
    collect_subtree(instance_id, &session.instances, &mut subtree_ids);

    let mut instance_map = Map::new();
    for node_id in subtree_ids {
        if let Some(node) = session.instances.get(&node_id) {
            instance_map.insert(node_id, serde_json::to_value(node).unwrap_or(json!({})));
        }
    }

    let file_backed_ids: Vec<String> = instance_map
        .keys()
        .filter(|node_id| session.file_paths.contains_key((*node_id).as_str()))
        .cloned()
        .collect();

    Ok(json!({
        "sessionId": session_id,
        "cursor": session.cursor.to_string(),
        "instanceId": instance_id,
        "instances": instance_map,
        "sessionCapabilities": session_capabilities_payload(),
        "fileBackedInstanceIds": file_backed_ids
    }))
}

fn subscribe_result(session: &SessionState, requested_cursor: u64, session_id: &str) -> Value {
    let mut added = Map::new();
    let mut updated: Vec<Value> = vec![];
    let mut removed: Vec<Value> = vec![];

    for batch in session.changes.iter().filter(|batch| batch.cursor > requested_cursor) {
        for (key, value) in &batch.added {
            added.insert(key.clone(), serde_json::to_value(value).unwrap_or(json!({})));
        }

        for value in &batch.updated {
            updated.push(serde_json::to_value(value).unwrap_or(json!({})));
        }

        for value in &batch.removed {
            removed.push(json!(value));
        }
    }

    let file_backed_ids: Vec<String> = session.file_paths.keys().cloned().collect();

    json!({
        "sessionId": session_id,
        "cursor": session.cursor.to_string(),
        "added": added,
        "updated": updated,
        "removed": removed,
        "sessionCapabilities": session_capabilities_payload(),
        "fileBackedInstanceIds": file_backed_ids
    })
}

fn resolve_session_id(requested: Option<&str>, sessions: &HashMap<String, SessionState>) -> Option<String> {
    if let Some(session_id) = requested {
        return Some(session_id.to_string());
    }

    sessions.keys().next().cloned()
}

async fn handle_rojo_open(
    State(state): State<Arc<AppState>>,
    Json(body): Json<RojoOpenRequest>,
) -> impl IntoResponse {
    let project_path = body.project_path.as_deref().unwrap_or("src");

    match open_session_for_project(&state, project_path) {
        Ok(result) => (StatusCode::OK, Json(result)),
        Err(_) => (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "failed to open source project"})),
        ),
    }
}

async fn handle_rojo_read_by_instance(
    State(state): State<Arc<AppState>>,
    Path(instance_id): Path<String>,
    Query(query): Query<ReadQuery>,
) -> impl IntoResponse {
    let mut sessions = state.sessions.lock().expect("session lock poisoned");
    let session_id = match resolve_session_id(query.session_id.as_deref(), &sessions) {
        Some(value) => value,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "sessionId is required"})),
            );
        }
    };

    let session = match sessions.get_mut(&session_id) {
        Some(value) => value,
        None => return session_not_found_http(),
    };

    refresh_session_from_source(&state, session);

    match read_tree_result(session, Some(&instance_id), &session_id) {
        Ok(result) => (StatusCode::OK, Json(result)),
        Err(message) => (StatusCode::BAD_REQUEST, Json(json!({"error": message}))),
    }
}

async fn handle_rojo_read_by_session_and_instance(
    State(state): State<Arc<AppState>>,
    Path((session_id, instance_id)): Path<(String, String)>,
) -> impl IntoResponse {
    let mut sessions = state.sessions.lock().expect("session lock poisoned");
    let session = match sessions.get_mut(&session_id) {
        Some(value) => value,
        None => return session_not_found_http(),
    };

    refresh_session_from_source(&state, session);

    match read_tree_result(session, Some(&instance_id), &session_id) {
        Ok(result) => (StatusCode::OK, Json(result)),
        Err(message) => (StatusCode::BAD_REQUEST, Json(json!({"error": message}))),
    }
}

async fn handle_rojo_subscribe(
    State(state): State<Arc<AppState>>,
    Path(session_id): Path<String>,
) -> impl IntoResponse {
    let mut sessions = state.sessions.lock().expect("session lock poisoned");
    let session = match sessions.get_mut(&session_id) {
        Some(value) => value,
        None => return session_not_found_http(),
    };

    refresh_session_from_source(&state, session);
    (StatusCode::OK, Json(subscribe_result(session, 0, &session_id)))
}

async fn handle_rojo_subscribe_with_cursor(
    State(state): State<Arc<AppState>>,
    Path((session_id, cursor)): Path<(String, String)>,
) -> impl IntoResponse {
    let requested_cursor = cursor.parse::<u64>().unwrap_or(0);
    let mut sessions = state.sessions.lock().expect("session lock poisoned");
    let session = match sessions.get_mut(&session_id) {
        Some(value) => value,
        None => return session_not_found_http(),
    };

    refresh_session_from_source(&state, session);
    (
        StatusCode::OK,
        Json(subscribe_result(session, requested_cursor, &session_id)),
    )
}

async fn handle_mcp_replay(
    State(state): State<Arc<AppState>>,
    Query(query): Query<ReplayQuery>,
) -> impl IntoResponse {
    let since = query
        .since
        .as_deref()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(0);
    let limit = query.limit.unwrap_or(100).clamp(1, 1_000);

    let (latest_seq, events) = replay_events_since(&state, since, limit);
    (
        StatusCode::OK,
        Json(json!({
            "since": since,
            "latestSeq": latest_seq,
            "count": events.len(),
            "events": events,
        })),
    )
}

async fn handle_mcp(
    State(state): State<Arc<AppState>>,
    Json(request): Json<JsonRpcRequest>,
) -> impl IntoResponse {
    handle_mcp_request(state, request).await
}

pub(crate) async fn handle_mcp_request(
    state: Arc<AppState>,
    request: JsonRpcRequest,
) -> (StatusCode, Json<Value>) {
    let id = request.id.clone().unwrap_or(json!(null));

    // Log incoming JSON-RPC requests for diagnostics (method, id, params)
    info!(method = %request.method, id = ?id, params = %request.params, "received mcp json-rpc request");

    match request.method.as_str() {
        "initialize" => {
            let params: InitializeParams = match serde_json::from_value(request.params) {
                Ok(value) => value,
                Err(_) => {
                    return (
                        StatusCode::BAD_REQUEST,
                        Json(json!(invalid_request(id, "initialize params are invalid"))),
                    );
                }
            };

            let result = initialize_result(params, &state.server_version);
            (
                StatusCode::OK,
                Json(json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": result
                })),
            )
        }
        "tools/list" => {
            // Provide sanitized tool names that conform to the extension's
            // allowed pattern ([a-z0-9_-]) while mapping back to the
            // canonical MCP tool names for dispatch.
            let canonical = [
                ("roblox.openSession", "Open a Rojo-backed session"),
                ("roblox.readTree", "Read a tree/subtree snapshot"),
                ("roblox.subscribeChanges", "Subscribe to incremental changes"),
                ("roblox.applyPatch", "Apply a mutation patch"),
                ("roblox.closeSession", "Close session"),
                ("roblox.exportSnapshot", "Export a session snapshot"),
                ("roblox.importSnapshot", "Import a session snapshot"),
            ];

            let tools: Vec<Value> = canonical
                .iter()
                .map(|(name, desc)| {
                    let sanitized = sanitize_tool_name(name);
                    json!({"name": sanitized, "description": desc})
                })
                .collect();

            (
                StatusCode::OK,
                Json(json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": { "tools": tools }
                })),
            )
        }
        "tools/call" => {
            let mut name = request
                .params
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();

            // Allow clients to call the sanitized tool name that was
            // advertised in `tools/list`. If the client provided a
            // sanitized name, map it back to the canonical MCP tool name.
            let canonical = vec![
                ("roblox.openSession", "Open a Rojo-backed session"),
                ("roblox.readTree", "Read a tree/subtree snapshot"),
                ("roblox.subscribeChanges", "Subscribe to incremental changes"),
                ("roblox.applyPatch", "Apply a mutation patch"),
                ("roblox.closeSession", "Close session"),
                ("roblox.exportSnapshot", "Export a session snapshot"),
                ("roblox.importSnapshot", "Import a session snapshot"),
            ];
            for (orig, _desc) in &canonical {
                if sanitize_tool_name(orig) == name {
                    name = orig.to_string();
                    break;
                }
            }
            let args = request
                .params
                .get("arguments")
                .cloned()
                .unwrap_or_else(|| json!({}));

            match name.as_str() {
                "roblox.openSession" => {
                    let project_path = args
                        .get("projectPath")
                        .and_then(Value::as_str)
                        .unwrap_or("src");

                    match open_session_for_project(&state, project_path) {
                        Ok(result) => tool_ok(id, result),
                        Err(_) => (
                            StatusCode::BAD_REQUEST,
                            Json(json!(invalid_request(id, "failed to open source project"))),
                        ),
                    }
                }
                "roblox.readTree" => {
                    let session_id = args
                        .get("sessionId")
                        .and_then(Value::as_str)
                        .unwrap_or("sess:default.project.json");
                    let requested = args.get("instanceId").and_then(Value::as_str);

                    let result = {
                        let mut sessions = state.sessions.lock().expect("session lock poisoned");
                        let session = match sessions.get_mut(session_id) {
                            Some(session) => session,
                            None => return session_not_found_rpc(id),
                        };

                        refresh_session_from_source(&state, session);

                        match read_tree_result(session, requested, session_id) {
                            Ok(value) => value,
                            Err(_) => {
                                return (
                                    StatusCode::BAD_REQUEST,
                                    Json(json!(invalid_request(id, "instance does not exist"))),
                                );
                            }
                        }
                    };

                    tool_ok(id, result)
                }
                "roblox.subscribeChanges" => {
                    let session_id = args
                        .get("sessionId")
                        .and_then(Value::as_str)
                        .unwrap_or("sess:default.project.json");
                    let cursor = args.get("cursor").and_then(Value::as_str);

                    let requested_cursor = cursor
                        .and_then(|value| value.parse::<u64>().ok())
                        .unwrap_or(0);

                    let result = {
                        let mut sessions = state.sessions.lock().expect("session lock poisoned");
                        let session = match sessions.get_mut(session_id) {
                            Some(value) => value,
                            None => return session_not_found_rpc(id),
                        };

                        refresh_session_from_source(&state, session);
                        subscribe_result(session, requested_cursor, session_id)
                    };

                    tool_ok(id, result)
                }
                "roblox.applyPatch" => {
                    let session_id = args
                        .get("sessionId")
                        .and_then(Value::as_str)
                        .unwrap_or("sess:default.project.json");
                    let patch_id = args
                        .get("patchId")
                        .and_then(Value::as_str)
                        .unwrap_or("patch-default");
                    let patch_origin = args
                        .get("origin")
                        .and_then(Value::as_str)
                        .unwrap_or("unknown");

                    let apply_result = {
                        let mut sessions = state.sessions.lock().expect("session lock poisoned");
                        let session = match sessions.get_mut(session_id) {
                            Some(value) => value,
                            None => return session_not_found_rpc(id),
                        };

                        if let Some(existing_cursor) = session.applied_patches.get(patch_id).copied() {
                            json!({
                                "accepted": true,
                                "idempotent": true,
                                "appliedCursor": existing_cursor.to_string(),
                                "origin": patch_origin,
                                "conflicts": []
                            })
                        } else {
                            let operations = args
                                .get("operations")
                                .and_then(Value::as_array)
                                .cloned()
                                .unwrap_or_default();
                            let base_cursor = args
                                .get("baseCursor")
                                .and_then(Value::as_str)
                                .and_then(|value| value.parse::<u64>().ok())
                                .unwrap_or(session.cursor);

                            let added = HashMap::<String, InstanceNode>::new();
                            let mut updated = vec![];
                            let removed = vec![];
                            let mut conflicts = vec![];
                            let mut conflict_details: Vec<Value> = vec![];
                            let mut touched_fields: Vec<String> = vec![];

                            for operation in operations {
                                let op_name = operation.get("op").and_then(Value::as_str).unwrap_or("");

                                match op_name {
                                    "setProperty" => {
                                        let instance_id = operation
                                            .get("instanceId")
                                            .and_then(Value::as_str)
                                            .unwrap_or("");
                                        let property = operation
                                            .get("property")
                                            .and_then(Value::as_str)
                                            .unwrap_or("");
                                        let value = operation.get("value").cloned().unwrap_or(json!(null));
                                        let key = field_key(instance_id, property);

                                        if has_write_conflict(
                                            session.property_last_write.get(&key).copied(),
                                            base_cursor,
                                        ) {
                                            let last_write = session
                                                .property_last_write
                                                .get(&key)
                                                .copied()
                                                .unwrap_or(base_cursor);
                                            conflicts.push(format!("conflict on {} at baseCursor {}", key, base_cursor));
                                            conflict_details.push(json!({
                                                "instanceId": instance_id,
                                                "property": property,
                                                "reason": CONFLICT_WRITE_STALE_CURSOR,
                                                "baseCursor": base_cursor.to_string(),
                                                "lastWriteCursor": last_write.to_string()
                                            }));
                                            continue;
                                        }

                                        if let Some(node) = session.instances.get_mut(instance_id) {
                                            if session.file_paths.contains_key(instance_id) && property != "Source" {
                                                conflicts.push(format!(
                                                    "setProperty {} is not supported for file-backed instance {}",
                                                    property, instance_id
                                                ));
                                                conflict_details.push(json!({
                                                    "operation": "setProperty",
                                                    "instanceId": instance_id,
                                                    "property": property,
                                                    "reason": UNSUPPORTED_FILE_BACKED_MUTATION
                                                }));
                                                continue;
                                            }

                                            if property == "Source" {
                                                if let Some(path) = session.file_paths.get(instance_id) {
                                                    let source = value.as_str().unwrap_or("").to_string();
                                                    if fs::write(path, source).is_err() {
                                                        conflicts.push(format!("failed writing Source to {}", path));
                                                        conflict_details.push(json!({
                                                            "operation": "setProperty",
                                                            "instanceId": instance_id,
                                                            "property": property,
                                                            "reason": SOURCE_WRITE_FAILED,
                                                            "path": path
                                                        }));
                                                        continue;
                                                    }
                                                } else {
                                                    conflicts.push(format!(
                                                        "Source update requested for non file-backed instance {}",
                                                        instance_id
                                                    ));
                                                    conflict_details.push(json!({
                                                        "operation": "setProperty",
                                                        "instanceId": instance_id,
                                                        "property": property,
                                                        "reason": SOURCE_PATH_MISSING
                                                    }));
                                                    continue;
                                                }
                                            }

                                            node.properties.insert(property.to_string(), value.clone());
                                            let mut changed_props = Map::new();
                                            changed_props.insert(property.to_string(), value);
                                            updated.push(UpdatedInstance {
                                                id: instance_id.to_string(),
                                                changed_name: None,
                                                changed_properties: changed_props,
                                            });
                                            touched_fields.push(key);
                                        } else {
                                            conflicts.push(format!("instance {} not found", instance_id));
                                        }
                                    }
                                    "setName" => {
                                        let instance_id = operation
                                            .get("instanceId")
                                            .and_then(Value::as_str)
                                            .unwrap_or("");
                                        let name = operation
                                            .get("name")
                                            .and_then(Value::as_str)
                                            .unwrap_or("");
                                        let key = field_key(instance_id, "Name");

                                        if has_write_conflict(
                                            session.property_last_write.get(&key).copied(),
                                            base_cursor,
                                        ) {
                                            let last_write = session
                                                .property_last_write
                                                .get(&key)
                                                .copied()
                                                .unwrap_or(base_cursor);
                                            conflicts.push(format!("conflict on {} at baseCursor {}", key, base_cursor));
                                            conflict_details.push(json!({
                                                "instanceId": instance_id,
                                                "property": "Name",
                                                "reason": CONFLICT_WRITE_STALE_CURSOR,
                                                "baseCursor": base_cursor.to_string(),
                                                "lastWriteCursor": last_write.to_string()
                                            }));
                                            continue;
                                        }

                                        if let Some(node) = session.instances.get_mut(instance_id) {
                                            if session.file_paths.contains_key(instance_id) {
                                                conflicts.push(format!(
                                                    "setName is not supported for file-backed instance {}",
                                                    instance_id
                                                ));
                                                conflict_details.push(json!({
                                                    "operation": "setName",
                                                    "instanceId": instance_id,
                                                    "property": "Name",
                                                    "reason": UNSUPPORTED_FILE_BACKED_MUTATION
                                                }));
                                                continue;
                                            }

                                            node.name = name.to_string();
                                            updated.push(UpdatedInstance {
                                                id: instance_id.to_string(),
                                                changed_name: Some(name.to_string()),
                                                changed_properties: Map::new(),
                                            });
                                            touched_fields.push(key);
                                        } else {
                                            conflicts.push(format!("instance {} not found", instance_id));
                                        }
                                    }
                                    "addInstance" => {
                                        conflicts.push(
                                            "addInstance is not supported for file-backed sessions".to_string(),
                                        );
                                        conflict_details.push(json!({
                                            "operation": "addInstance",
                                            "reason": UNSUPPORTED_FILE_BACKED_MUTATION
                                        }));
                                        continue;
                                    }
                                    "removeInstance" => {
                                        conflicts.push(
                                            "removeInstance is not supported for file-backed sessions".to_string(),
                                        );
                                        conflict_details.push(json!({
                                            "operation": "removeInstance",
                                            "reason": UNSUPPORTED_FILE_BACKED_MUTATION
                                        }));
                                        continue;
                                    }
                                    _ => {
                                        conflicts.push(format!("unsupported op {}", op_name));
                                    }
                                }
                            }

                            let has_changes = !added.is_empty() || !updated.is_empty() || !removed.is_empty();
                            if has_changes {
                                session.cursor += 1;
                                for field in touched_fields {
                                    session.property_last_write.insert(field, session.cursor);
                                }
                                session.changes.push(ChangeBatch {
                                    cursor: session.cursor,
                                    added: added.clone(),
                                    updated: updated.clone(),
                                    removed: removed.clone(),
                                });
                            }

                            let applied_cursor = session.cursor;
                            session.applied_patches.insert(patch_id.to_string(), applied_cursor);

                            json!({
                                "accepted": conflicts.is_empty(),
                                "idempotent": false,
                                "origin": patch_origin,
                                "baseCursor": base_cursor.to_string(),
                                "appliedCursor": applied_cursor.to_string(),
                                "added": added,
                                "updated": updated,
                                "removed": removed,
                                "conflicts": conflicts,
                                "conflictDetails": conflict_details
                            })
                        }
                    };

                    tool_ok(id, apply_result)
                }
                "roblox.exportSnapshot" => {
                    let session_id = args
                        .get("sessionId")
                        .and_then(Value::as_str)
                        .unwrap_or("sess:default.project.json");

                    let result = {
                        let sessions_lock = state.sessions.lock().expect("session lock poisoned");
                        let session = match sessions_lock.get(session_id) {
                            Some(s) => s,
                            None => return session_not_found_rpc(id),
                        };

                        // Build ProjectSnapshot-like value from session
                        let mut instances_map = Map::new();
                        for (k, v) in &session.instances {
                            instances_map.insert(k.clone(), serde_json::to_value(v).unwrap_or(json!({})));
                        }

                        json!({
                            "root_id": session.root_id,
                            "instances": instances_map,
                            "file_paths": session.file_paths
                        })
                    };

                    tool_ok(id, result)
                }
                "roblox.importSnapshot" => {
                    let session_id = args
                        .get("sessionId")
                        .and_then(Value::as_str)
                        .unwrap_or("");

                    if session_id.is_empty() {
                        return (
                            StatusCode::BAD_REQUEST,
                            Json(json!(invalid_request(id, "sessionId is required for import"))),
                        );
                    }

                    let snapshot_val = args.get("snapshot").cloned().unwrap_or(json!({}));
                    let snapshot: Result<rojo_adapter::ProjectSnapshot, _> = serde_json::from_value(snapshot_val);
                    let snapshot = match snapshot {
                        Ok(s) => s,
                        Err(e) => {
                            let msg = format!("invalid snapshot: {}", e);
                            return (
                                StatusCode::BAD_REQUEST,
                                Json(json!(invalid_request(id, msg.as_str()))),
                            );
                        }
                    };

                    // validate snapshot structure before applying
                    let issues = validate_snapshot(&snapshot);
                    if !issues.is_empty() {
                        return (
                            StatusCode::BAD_REQUEST,
                            Json(json!({
                                "jsonrpc": "2.0",
                                "id": id,
                                "error": {
                                    "code": -32003,
                                    "message": "snapshot validation failed",
                                    "data": { "issues": issues }
                                }
                            })),
                        );
                    }

                    let mut sessions = state.sessions.lock().expect("session lock poisoned");
                    let existing = match sessions.get(session_id) {
                        Some(sess) => sess.project_path.clone(),
                        None => return session_not_found_rpc(id),
                    };

                    // Replace session state with snapshot-derived session and apply in chunks
                    let mut new_session = make_session_from_snapshot(&existing, snapshot.clone());

                    // choose chunk size from args, default to 100
                    let chunk_size = args
                        .get("chunkSize")
                        .and_then(Value::as_u64)
                        .map(|v| v as usize)
                        .unwrap_or(100);

                    let (applied_cursor, imported_count, file_backed, chunks) =
                        apply_snapshot_to_session(
                            &mut new_session,
                            snapshot,
                            chunk_size,
                            Some(&state.broadcaster),
                            Some(&state.replay),
                            state.config.seq_retention,
                        );

                    sessions.insert(session_id.to_string(), new_session);

                    tool_ok(id, json!({
                        "imported": true,
                        "sessionId": session_id,
                        "validated": true,
                        "importSummary": {
                            "instances": imported_count,
                            "fileBackedInstances": file_backed,
                            "appliedCursor": applied_cursor.to_string(),
                            "chunks": chunks,
                            "chunkSize": chunk_size
                        }
                    }))
                }
                "roblox.importProgress" => {
                    // polling endpoint to fetch progress summary for a session
                    let session_id = args
                        .get("sessionId")
                        .and_then(Value::as_str)
                        .unwrap_or("");

                    if session_id.is_empty() {
                        return (
                            StatusCode::BAD_REQUEST,
                            Json(json!(invalid_request(id, "sessionId is required"))),
                        );
                    }

                    let sessions = state.sessions.lock().expect("session lock poisoned");
                    let session = match sessions.get(session_id) {
                        Some(s) => s,
                        None => return session_not_found_rpc(id),
                    };

                    let total_changes = session.changes.len();
                    let last_cursor = session.cursor;

                    tool_ok(id, json!({
                        "sessionId": session_id,
                        "cursor": last_cursor.to_string(),
                        "changeBatches": total_changes
                    }))
                }
                "roblox.closeSession" => {
                    let session_id = args
                        .get("sessionId")
                        .and_then(Value::as_str)
                        .unwrap_or("sess:default.project.json");

                    let removed = {
                        let mut sessions = state.sessions.lock().expect("session lock poisoned");
                        sessions.remove(session_id).is_some()
                    };

                    tool_ok(id, json!({"closed": removed}))
                }
                _ => (
                    StatusCode::BAD_REQUEST,
                    Json(json!(invalid_request(id, "unsupported tool name"))),
                ),
            }
        }
        "notifications/initialized" => (
            StatusCode::OK,
            Json(json!({
                "jsonrpc": "2.0",
                "id": id,
                "result": {"ack": true}
            })),
        ),
        "logging/setLevel" => {
            // Some clients use a logging API (e.g., logging/setLevel). Accept and
            // acknowledge it to avoid a 400 error from the client.
            tool_ok(id, json!({}))
        }
        m if m.starts_with("mcp.") => {
            // some clients (Copilot MCP, etc.) send utility methods such as
            // "mcp.setLogLevel" on startup.  We don't currently support any
            // of them, but responding with a successful empty result prevents
            // a 400 error from confusing the caller.
            tool_ok(id, json!({}))
        }
        _ => (
            StatusCode::BAD_REQUEST,
            Json(json!(invalid_request(id, "unsupported method"))),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::{
        has_write_conflict, make_default_session, publish_event_with_replay, remove_subtree,
        replay_events_since, AppState, Config, ReplayState,
    };
    use rojo_adapter::ProjectSnapshot;
    use serde_json::{json, Map};
    use std::{collections::HashMap, sync::{Arc, Mutex}};
    use tokio::sync::broadcast;

    fn test_app_state() -> AppState {
        let (tx, _rx) = broadcast::channel(16);
        AppState {
            adapter: rojo_adapter::RojoAdapter::new(),
            server_version: "test".to_string(),
            sessions: Arc::new(Mutex::new(HashMap::new())),
            broadcaster: tx,
            replay: Arc::new(Mutex::new(ReplayState::new())),
            config: Config::from_env(),
        }
    }

    #[test]
    fn make_session_from_snapshot_roundtrip() {
        let mut instances = std::collections::HashMap::new();
        let mut props = Map::new();
        props.insert("PropA".to_string(), json!(123));

        instances.insert(
            "ref_root".to_string(),
            rojo_adapter::AdapterNode {
                id: "ref_root".to_string(),
                parent: None,
                name: "Game".to_string(),
                class_name: "DataModel".to_string(),
                properties: props.clone(),
                children: vec![],
            },
        );

        let snapshot = ProjectSnapshot {
            root_id: "ref_root".to_string(),
            instances,
            file_paths: std::collections::HashMap::new(),
        };

        let session = super::make_session_from_snapshot("proj", snapshot);
        assert_eq!(session.root_id, "ref_root");
        assert!(session.instances.contains_key("ref_root"));
        let node = session.instances.get("ref_root").unwrap();
        assert_eq!(node.properties.get("PropA").unwrap(), &json!(123));
    }

    #[test]
    fn validate_snapshot_detects_issues() {
        let mut instances = std::collections::HashMap::new();
        instances.insert(
            "ref_child".to_string(),
            rojo_adapter::AdapterNode {
                id: "ref_child".to_string(),
                parent: Some("ref_root".to_string()),
                name: "Child".to_string(),
                class_name: "Folder".to_string(),
                properties: Map::new(),
                children: vec![],
            },
        );

        let mut file_paths = std::collections::HashMap::new();
        file_paths.insert("unknown_id".to_string(), "path/to/file".to_string());

        let snapshot = ProjectSnapshot {
            root_id: "ref_root".to_string(), // root missing from instances
            instances,
            file_paths,
        };

        let issues = super::validate_snapshot(&snapshot);
        assert!(issues.iter().any(|s| s.contains("rootId")));
        assert!(issues.iter().any(|s| s.contains("filePaths references unknown instance")));
    }

    #[test]
    fn apply_snapshot_to_session_chunks() {
        // create a snapshot with 250 instances
        let mut instances = std::collections::HashMap::new();
        for i in 0..250 {
            let id = format!("ref_{}", i);
            instances.insert(
                id.clone(),
                rojo_adapter::AdapterNode {
                    id: id.clone(),
                    parent: None,
                    name: format!("Node{}", i),
                    class_name: "Folder".to_string(),
                    properties: Map::new(),
                    children: vec![],
                },
            );
        }

        let snapshot = ProjectSnapshot {
            root_id: "ref_0".to_string(),
            instances,
            file_paths: std::collections::HashMap::new(),
        };

        let mut session = make_default_session();
        let (applied_cursor, total, _file_backed, chunks) =
            super::apply_snapshot_to_session(&mut session, snapshot, 100, None, None, 10_000);
        assert_eq!(total, 250);
        assert_eq!(chunks, 3);
        assert!(applied_cursor >= 3);
        // session should now contain the instances
        assert!(session.instances.contains_key("ref_0"));
        assert_eq!(session.cursor, applied_cursor);
        // changes should have 3 new batches appended
        assert!(session.changes.len() >= 3);
    }

    #[test]
    fn broadcast_messages_emitted_on_chunk_apply() {
        use tokio::sync::broadcast;
        use serde_json::Value;
        // small snapshot with 5 instances, chunk_size 2 -> 3 chunks
        let mut instances = std::collections::HashMap::new();
        for i in 0..5 {
            let id = format!("ref_{}", i);
            instances.insert(
                id.clone(),
                rojo_adapter::AdapterNode {
                    id: id.clone(),
                    parent: None,
                    name: format!("Node{}", i),
                    class_name: "Folder".to_string(),
                    properties: Map::new(),
                    children: vec![],
                },
            );
        }

        let snapshot = ProjectSnapshot {
            root_id: "ref_0".to_string(),
            instances,
            file_paths: std::collections::HashMap::new(),
        };

        let mut session = make_default_session();
        let (tx, mut rx) = broadcast::channel(16);

        let (applied_cursor, total, _file_backed, chunks) =
            super::apply_snapshot_to_session(&mut session, snapshot, 2, Some(&tx), None, 10_000);

        assert_eq!(total, 5);
        assert_eq!(chunks, 3);

        // receive 3 messages
        let mut received = 0;
        while let Ok(msg) = rx.try_recv() {
            let v: Value = serde_json::from_str(&msg.to_string()).unwrap_or(json!({}));
            if v.get("type").and_then(Value::as_str) == Some("importProgress") {
                received += 1;
            }
        }

        assert_eq!(received, 3);
        assert!(applied_cursor >= 3);
    }

    #[test]
    fn apply_patch_is_idempotent_for_same_patch_id() {
        let mut session = make_default_session();
        session.cursor = 10;

        session.cursor += 1;
        let first_cursor = session.cursor;
        session
            .applied_patches
            .insert("patch-1".to_string(), first_cursor);

        let second = session.applied_patches.get("patch-1").copied().unwrap();
        assert_eq!(first_cursor, second);
        assert_eq!(session.cursor, first_cursor);
    }

    #[test]
    fn cursor_advances_monotonically() {
        let mut cursor = 0_u64;
        let requested = 4_u64;
        cursor = std::cmp::max(cursor, requested) + 1;
        assert_eq!(cursor, 5);

        let requested_old = 2_u64;
        cursor = std::cmp::max(cursor, requested_old) + 1;
        assert_eq!(cursor, 6);
    }

    #[test]
    fn default_session_has_root() {
        let session = make_default_session();
        assert!(session.instances.contains_key(&session.root_id));
    }

    #[test]
    fn remove_subtree_removes_child_from_parent() {
        let mut session = make_default_session();
        let mut removed = vec![];
        remove_subtree(
            "ref_replicated_storage",
            &mut session.instances,
            &mut removed,
        );

        assert!(removed.contains(&"ref_replicated_storage".to_string()));
        assert!(!session.instances.contains_key("ref_replicated_storage"));
        let root = session.instances.get("ref_root").unwrap();
        assert!(!root.children.contains(&"ref_replicated_storage".to_string()));
    }

    #[test]
    fn detects_base_cursor_conflict() {
        assert!(has_write_conflict(Some(5), 4));
        assert!(!has_write_conflict(Some(5), 5));
        assert!(!has_write_conflict(None, 1));
    }

    #[test]
    fn replay_sequence_and_retrieval() {
        let state = test_app_state();

        publish_event_with_replay(
            &state.broadcaster,
            Some(&state.replay),
            state.config.seq_retention,
            json!({"type": "importProgress", "sessionId": "sess-1", "chunk": 1}),
        );
        publish_event_with_replay(
            &state.broadcaster,
            Some(&state.replay),
            state.config.seq_retention,
            json!({"type": "importProgress", "sessionId": "sess-1", "chunk": 2}),
        );

        let (latest, events) = replay_events_since(&state, 0, 10);
        assert_eq!(latest, 2);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].get("seq").and_then(|v| v.as_u64()), Some(1));
        assert_eq!(events[1].get("seq").and_then(|v| v.as_u64()), Some(2));
        assert_eq!(events[0].get("type").and_then(|v| v.as_str()), Some("importProgress"));
    }
}
