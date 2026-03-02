use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub bind_addr: String,
    pub enable_ws_rpc: bool,
    pub require_ws_token: bool,
    pub ws_auth_token: Option<String>,
    pub ws_backpressure_policy: String,
    pub ws_ping_interval_ms: u64,
    pub ws_ping_timeout_ms: u64,
    pub max_ws_message_size: usize,
    pub client_send_queue_capacity: usize,
    pub seq_retention: usize,
}

impl Config {
    pub fn from_env() -> Self {
        let bind_addr = env::var("MCP_BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:44877".to_string());
        let enable_ws_rpc = env::var("MCP_ENABLE_WS_RPC").map(|v| v == "true").unwrap_or(true);
        let require_ws_token = env::var("MCP_REQUIRE_WS_TOKEN").map(|v| v == "true").unwrap_or(false);
        let ws_auth_token = env::var("MCP_WS_AUTH_TOKEN").ok().and_then(|v| {
            let trimmed = v.trim().to_string();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed)
            }
        });
        let ws_backpressure_policy = env::var("MCP_WS_BACKPRESSURE_POLICY")
            .unwrap_or_else(|_| "drop_oldest".to_string());
        let ws_ping_interval_ms = env::var("MCP_WS_PING_INTERVAL_MS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(30_000);
        let ws_ping_timeout_ms = env::var("MCP_WS_PING_TIMEOUT_MS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(60_000);
        let max_ws_message_size = env::var("MCP_MAX_WS_MESSAGE_SIZE")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(1_048_576);
        let client_send_queue_capacity = env::var("MCP_CLIENT_SEND_QUEUE_CAPACITY")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(256);
        let seq_retention = env::var("MCP_SEQ_RETENTION")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(10_000);

        Config {
            bind_addr,
            enable_ws_rpc,
            require_ws_token,
            ws_auth_token,
            ws_backpressure_policy,
            ws_ping_interval_ms,
            ws_ping_timeout_ms,
            max_ws_message_size,
            client_send_queue_capacity,
            seq_retention,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Config;
    use std::env;

    #[test]
    fn default_config_values() {
        // Ensure env vars absent
        env::remove_var("MCP_BIND_ADDR");
        env::remove_var("MCP_ENABLE_WS_RPC");
        env::remove_var("MCP_REQUIRE_WS_TOKEN");
        env::remove_var("MCP_WS_AUTH_TOKEN");
        env::remove_var("MCP_WS_BACKPRESSURE_POLICY");
        env::remove_var("MCP_WS_PING_INTERVAL_MS");
        env::remove_var("MCP_WS_PING_TIMEOUT_MS");
        env::remove_var("MCP_MAX_WS_MESSAGE_SIZE");
        env::remove_var("MCP_CLIENT_SEND_QUEUE_CAPACITY");
        env::remove_var("MCP_SEQ_RETENTION");

        let cfg = Config::from_env();
        assert_eq!(cfg.bind_addr, "127.0.0.1:44877");
        assert!(cfg.enable_ws_rpc);
        assert!(!cfg.require_ws_token);
        assert!(cfg.ws_auth_token.is_none());
        assert_eq!(cfg.ws_backpressure_policy, "drop_oldest");
        assert_eq!(cfg.ws_ping_interval_ms, 30_000);
        assert_eq!(cfg.ws_ping_timeout_ms, 60_000);
        assert_eq!(cfg.max_ws_message_size, 1_048_576);
        assert_eq!(cfg.client_send_queue_capacity, 256);
        assert_eq!(cfg.seq_retention, 10_000);
    }
}
