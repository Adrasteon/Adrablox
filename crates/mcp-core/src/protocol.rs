use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const SUPPORTED_PROTOCOL: &str = "2025-11-25";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JsonRpcRequest {
    pub jsonrpc: String,
    #[serde(default)]
    pub id: Option<Value>,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JsonRpcResponse<T: Serialize> {
    pub jsonrpc: String,
    pub id: Value,
    pub result: T,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JsonRpcError {
    pub code: i64,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JsonRpcErrorResponse {
    pub jsonrpc: String,
    pub id: Value,
    pub error: JsonRpcError,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeParams {
    pub protocol_version: String,
    pub capabilities: Value,
    #[serde(default)]
    pub client_info: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerCapabilities {
    pub resources: Value,
    pub tools: Value,
    pub logging: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeResult {
    pub protocol_version: String,
    pub capabilities: ServerCapabilities,
    pub server_info: Value,
    pub instructions: String,
}

pub fn initialize_result(params: InitializeParams, server_version: &str) -> InitializeResult {
    let protocol = if params.protocol_version == SUPPORTED_PROTOCOL {
        params.protocol_version
    } else {
        SUPPORTED_PROTOCOL.to_string()
    };

    InitializeResult {
        protocol_version: protocol,
        capabilities: ServerCapabilities {
            resources: serde_json::json!({
                "subscribe": true,
                "listChanged": false
            }),
            tools: serde_json::json!({
                "listChanged": false
            }),
            logging: serde_json::json!({}),
        },
        server_info: serde_json::json!({
            "name": "roblox-mcp-server",
            "version": server_version
        }),
        instructions: "Call roblox.openSession before read/subscribe/apply operations.".to_string(),
    }
}

pub fn invalid_request(id: Value, message: &str) -> JsonRpcErrorResponse {
    JsonRpcErrorResponse {
        jsonrpc: "2.0".to_string(),
        id,
        error: JsonRpcError {
            code: -32600,
            message: message.to_string(),
            data: None,
        },
    }
}
