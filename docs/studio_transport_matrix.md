# Studio ↔ VS Code Transport Matrix

Last updated: 2026-03-02

Purpose
-------
Operational playbook for selecting, implementing, and validating communication channels between Roblox Studio plugins and the MCP server used by VS Code workflows.

This document complements `mcp_transport_plan.md` and is intended to be executable guidance during implementation.

Sources (current Roblox docs)
-----------------------------
- `HttpService` (RequestAsync/GetAsync/PostAsync, HttpEnabled, CreateWebStreamClient)
- `WebStreamClient` (Opened/MessageReceived/Error/Closed, `Send()` behavior)
- `ScriptEditorService` (editor event hooks and source update APIs)

Transport options
-----------------

| Channel | Direction | Reliability | Latency | Recommended use | Notes |
|---|---|---|---|---|---|
| HTTP JSON-RPC (`POST /mcp`) | Bi-directional via request/response | High | Medium | Authoritative control/mutation calls | Keep as source of truth |
| WS stream (`/mcp-stream`) | Server → client push | Medium (High with replay) | Low | Realtime progress/change notifications | Harden with replay/heartbeat |
| WS RPC (optional) | Full duplex | Medium (High with replay+auth) | Low | Latency-sensitive request flow | Must map to same internal RPC handlers |
| WebStream Raw/SSE | Server → client stream | Medium | Low | Streaming-only endpoints/tool output | Studio-only capability |
| File-backed sync (Rojo/files) | VS Code ↔ Studio | High | Medium | Durable source synchronization | Not a network transport |
| ScriptEditorService events | Studio internal trigger plane | N/A | N/A | Trigger sync/analysis actions | Plugin security APIs |

Decision rules (must follow)
----------------------------
1. Use HTTP JSON-RPC for all correctness-critical and mutating operations.
2. Use WS/WebStream for realtime UX updates and event delivery.
3. If WS/WebStream fails, automatically degrade to HTTP subscribe/poll.
4. Keep file-backed sync path available for durable source updates.
5. Never depend on undocumented/private Roblox networking behavior.

Roblox constraints that affect implementation
---------------------------------------------
- `HttpService.HttpEnabled` must be enabled for external HTTP requests.
- `HttpService:CreateWebStreamClient` is Studio-only.
- `WebStreamClient:Send()` only works for `Enum.WebStreamClientType.WebSocket`.
- Maximum six concurrent `WebStreamClient` instances.
- Plugin secret access can be constrained by environment; avoid assuming generic secret availability in local plugin runs.

Required runtime configuration
------------------------------
- `MCP_BIND_ADDR` (default `127.0.0.1:44877`)
- `MCP_ENABLE_WS_RPC` (default `true` for localhost workflows)
- `MCP_REQUIRE_WS_TOKEN` (default `false` for localhost, `true` for non-local)
- `MCP_MAX_WS_MESSAGE_SIZE` (default `1048576`)
- `MCP_CLIENT_SEND_QUEUE_CAPACITY` (default `256`)
- `MCP_SEQ_RETENTION` (default `10000`)

Fallback matrix
---------------

| Failure mode | Immediate action | Next action |
|---|---|---|
| WS upgrade/auth failure | Switch client transport to HTTP subscribe/poll | Surface auth/setup error and retry with backoff |
| WS replay window exceeded | Rebaseline via `openSession` + `readTree` | Resume subscriptions at new cursor/seq |
| Stream client limit reached (6) | Close least-recently-used stream | Reconnect required stream and log warning |
| `HttpEnabled=false` | Block network transport startup | Show setup instruction to enable HTTP Requests |
| Message too large | Reject/close with explicit error | Require client chunking or smaller payload |

Coverage checklist (communications completeness)
------------------------------------------------
- [ ] HTTP control plane implemented and tested (`POST /mcp`).
- [ ] WS push implemented with sequence IDs and replay.
- [ ] Optional WS RPC path dispatches through same internal handlers as HTTP.
- [ ] WebStream client compatibility tested for `WebSocket` and `RawStream` modes.
- [ ] Plugin transport chooser supports WS → RawStream → HTTP fallback order.
- [ ] File-backed sync remains functional and policy-compliant.
- [x] ScriptEditorService hooks integrated as event triggers (not transport replacement).

Validation scenarios
--------------------
1. HTTP-only mode
   - Disable WS or force failure; verify full workflow succeeds via HTTP.
2. WS healthy mode
   - Connect WS, receive low-latency events, verify ordering by `seq`.
3. WS reconnect mode
   - Disconnect/reconnect with `since`; verify replay completeness and order.
4. WebStream compatibility mode
   - Plugin uses `CreateWebStreamClient(WebSocket)` and `RawStream` as configured.
5. Backpressure mode
   - Simulate slow consumer; verify drop/disconnect policy and metrics.

Suggested test tasks
--------------------
- `tools/run_ws_replay_task.ps1`
- `tools/run_stream_client_compat_task.ps1`
- Existing HTTP contract tasks (`tools/mcp_smoke_test.ps1`, reconnect/replay contract tests)

Operational notes
-----------------
- Keep mutation semantics centralized in HTTP/internal RPC path to avoid divergence.
- Keep transport-specific logic thin; business logic should remain transport-agnostic.
- Log transport transitions (WS→HTTP fallback, replay rebaseline) as structured events.
