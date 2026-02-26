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
    collections::HashMap,
    fs,
    net::SocketAddr,
    sync::{Arc, Mutex},
};
use tracing::info;

#[derive(Clone)]
struct AppState {
    adapter: RojoAdapter,
    server_version: String,
    sessions: Arc<Mutex<HashMap<String, SessionState>>>,
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

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            std::env::var("RUST_LOG")
                .unwrap_or_else(|_| "mcp_server=info,axum=info,tower_http=info".to_string()),
        )
        .init();

    let state = Arc::new(AppState {
        adapter: RojoAdapter::new(),
        server_version: env!("CARGO_PKG_VERSION").to_string(),
        sessions: Arc::new(Mutex::new(HashMap::new())),
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
        .with_state(state);

    let addr: SocketAddr = "127.0.0.1:44877".parse()?;
    info!(%addr, "mcp-server listening");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
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
    let sessions = state.sessions.lock().expect("session lock poisoned");
    let session_id = match resolve_session_id(query.session_id.as_deref(), &sessions) {
        Some(value) => value,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "sessionId is required"})),
            );
        }
    };

    let session = match sessions.get(&session_id) {
        Some(value) => value,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "session does not exist"})),
            );
        }
    };

    match read_tree_result(session, Some(&instance_id), &session_id) {
        Ok(result) => (StatusCode::OK, Json(result)),
        Err(message) => (StatusCode::BAD_REQUEST, Json(json!({"error": message}))),
    }
}

async fn handle_rojo_read_by_session_and_instance(
    State(state): State<Arc<AppState>>,
    Path((session_id, instance_id)): Path<(String, String)>,
) -> impl IntoResponse {
    let sessions = state.sessions.lock().expect("session lock poisoned");
    let session = match sessions.get(&session_id) {
        Some(value) => value,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "session does not exist"})),
            );
        }
    };

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
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "session does not exist"})),
            );
        }
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
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "session does not exist"})),
            );
        }
    };

    refresh_session_from_source(&state, session);
    (
        StatusCode::OK,
        Json(subscribe_result(session, requested_cursor, &session_id)),
    )
}

async fn handle_mcp(
    State(state): State<Arc<AppState>>,
    Json(request): Json<JsonRpcRequest>,
) -> impl IntoResponse {
    let id = request.id.clone().unwrap_or(json!(null));

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
        "tools/list" => (
            StatusCode::OK,
            Json(json!({
                "jsonrpc": "2.0",
                "id": id,
                "result": {
                    "tools": [
                        {"name": "roblox.openSession", "description": "Open a Rojo-backed session"},
                        {"name": "roblox.readTree", "description": "Read a tree/subtree snapshot"},
                        {"name": "roblox.subscribeChanges", "description": "Subscribe to incremental changes"},
                        {"name": "roblox.applyPatch", "description": "Apply a mutation patch"},
                        {"name": "roblox.closeSession", "description": "Close session"}
                    ]
                }
            })),
        ),
        "tools/call" => {
            let name = request
                .params
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or("");
            let args = request
                .params
                .get("arguments")
                .cloned()
                .unwrap_or_else(|| json!({}));

            match name {
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
                        let sessions = state.sessions.lock().expect("session lock poisoned");
                        let session = match sessions.get(session_id) {
                            Some(session) => session,
                            None => {
                                return (
                                    StatusCode::BAD_REQUEST,
                                    Json(json!(invalid_request(id, "session does not exist"))),
                                );
                            }
                        };

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
                            None => {
                                return (
                                    StatusCode::BAD_REQUEST,
                                    Json(json!(invalid_request(id, "session does not exist"))),
                                );
                            }
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
                            None => {
                                return (
                                    StatusCode::BAD_REQUEST,
                                    Json(json!(invalid_request(id, "session does not exist"))),
                                );
                            }
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
                                                "reason": "write_conflict",
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
                                                    "reason": "unsupported_for_file_backed_session"
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
                                                            "reason": "source_write_failed",
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
                                                        "reason": "source_path_missing"
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
                                                "reason": "write_conflict",
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
                                                    "reason": "unsupported_for_file_backed_session"
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
                                            "reason": "unsupported_for_file_backed_session"
                                        }));
                                        continue;
                                    }
                                    "removeInstance" => {
                                        conflicts.push(
                                            "removeInstance is not supported for file-backed sessions".to_string(),
                                        );
                                        conflict_details.push(json!({
                                            "operation": "removeInstance",
                                            "reason": "unsupported_for_file_backed_session"
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
        _ => (
            StatusCode::BAD_REQUEST,
            Json(json!(invalid_request(id, "unsupported method"))),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::{has_write_conflict, make_default_session, remove_subtree};

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
}
