pub mod protocol;

pub use protocol::{
    initialize_result, invalid_request, InitializeParams, JsonRpcError, JsonRpcRequest,
    JsonRpcResponse, ServerCapabilities,
};

#[cfg(test)]
mod tests {
    use crate::protocol::{initialize_result, InitializeParams};

    #[test]
    fn initialize_uses_requested_protocol_if_supported() {
        let params = InitializeParams {
            protocol_version: "2025-11-25".to_string(),
            capabilities: serde_json::json!({}),
            client_info: None,
        };

        let result = initialize_result(params, "0.1.0");
        assert_eq!(result.protocol_version, "2025-11-25");
    }

    #[test]
    fn initialize_falls_back_when_unknown_protocol() {
        let params = InitializeParams {
            protocol_version: "2023-01-01".to_string(),
            capabilities: serde_json::json!({}),
            client_info: None,
        };

        let result = initialize_result(params, "0.1.0");
        assert_eq!(result.protocol_version, "2025-11-25");
    }
}
