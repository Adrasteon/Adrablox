# WS Transport Migration Guide

Last updated: 2026-03-02

Purpose
-------
Guide existing plugin/CLI users from HTTP-only MCP usage to hybrid HTTP + WS transport with safe fallback behavior.

Who should migrate
------------------
- Plugin users that want lower-latency realtime updates.
- CLI users that want replay-aware WS event tails.
- Operators enabling non-local WS-RPC with token-based auth.

Server-side migration steps
---------------------------
1. Keep HTTP endpoint unchanged (`POST /mcp`) as authoritative control plane.
2. Confirm WS endpoints are reachable:
   - `ws://<host>:<port>/mcp-stream`
   - `ws://<host>:<port>/mcp-stream/ws-rpc`
3. Configure optional WS controls as needed:
   - `MCP_ENABLE_WS_RPC`
   - `MCP_REQUIRE_WS_TOKEN`
   - `MCP_WS_AUTH_TOKEN`
   - `MCP_MAX_WS_MESSAGE_SIZE`
   - `MCP_CLIENT_SEND_QUEUE_CAPACITY`
   - `MCP_SEQ_RETENTION`

CLI migration steps
-------------------
- Use `ws-tail` with replay/auth flags:
  - `node studio_action_scripts/cli/index.js ws-tail --since 100 --limit 200`
  - `node studio_action_scripts/cli/index.js ws-tail --auth-token <token> --since 100`
- Validate local flag behavior with:
  - `powershell -File tools/ws_cli_flag_smoke_test.ps1`

Plugin migration steps
----------------------
- `ConnectionManager` now prefers transport order:
  1. `WebSocket` (`CreateWebStreamClient(WebSocket)`)
  2. `RawStream`
  3. HTTP polling fallback
- Replay request send is WS-only guarded (`WebStreamClient:Send` invoked only in WS mode).

Operational validation
----------------------
- Run WS replay task:
  - `powershell -File tools/run_ws_replay_task.ps1`
- Run stream compatibility task:
  - `powershell -File tools/run_stream_client_compat_task.ps1`

Rollback plan
-------------
- If WS transport is unstable, continue using HTTP-only flow.
- Disable WS-RPC via `MCP_ENABLE_WS_RPC=false` while keeping `/mcp` online.
- Re-enable once auth/limits/heartbeat are verified.
