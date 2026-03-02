# MCP Transport Plan — Hybrid HTTP + WebSocket

Last updated: 2026-03-02

Overview
--------
This document expands the existing `mcp_transport_plan.md` into a guarded, staged, and actionable implementation plan. It is intended to be both an engineering checklist and a set of ready-to-run AI prompts that can be used to implement the work incrementally and safely.

Related docs
------------
- `docs/studio_transport_matrix.md` — operational channel matrix, fallback policy, and validation scenarios.
- `docs/ws_protocol.md` — protocol details for envelope, replay, auth, and limits.

Goals
-----
- Keep `HTTP JSON‑RPC` as the authoritative control/mutation plane (unchanged semantics and idempotency).
- Implement an authenticated, hardened `WebSocket` channel for low‑latency events and optional JSON‑RPC-over-WS with replay and backpressure.

Scope clarification ("all possible communications")
----------------------------------------------------
For this project, "all possible communications between Roblox Studio and VS Code" means all practical channels that are supported in Studio/plugin workflows and relevant to this repository:

1. Network request/response (`HttpService:RequestAsync`, `GetAsync`, `PostAsync`).
2. Streaming channels in Studio via `HttpService:CreateWebStreamClient`:
	- `RawStream`/SSE-style streaming
	- `WebSocket` streaming with bidirectional `Send()` support.
3. File-backed sync (Rojo/file watcher) between disk and Studio.
4. Editor-integration event channels inside Studio (`ScriptEditorService` callbacks/events) as trigger points for sync/analysis actions.

Non-goals: undocumented/private transport hooks, unsupported LocalScript-only networking assumptions, or replacing Roblox-supported APIs with custom native socket behavior.

Guardrails & Constraints
------------------------
- Default network binding is `127.0.0.1` until `MCP_BIND_ADDR` is explicitly set.
- Non-local WS RPC is opt-in via `MCP_ENABLE_WS_RPC=true` and `MCP_REQUIRE_WS_TOKEN=true`.
- Limits (configurable via env):
	- `MCP_MAX_WS_MESSAGE_SIZE` default `1048576` (1MiB)
	- `MCP_CLIENT_SEND_QUEUE_CAPACITY` default `256`
	- `MCP_SEQ_RETENTION` default `10000`
- Backpressure policy: `drop_oldest` (default) or `disconnect`.
- Reject upgrades lacking valid tokens when `MCP_REQUIRE_WS_TOKEN=true`.
- Roblox Studio/API constraints (from current docs):
	- `HttpService.HttpEnabled` must be enabled for external HTTP requests.
	- `HttpService:CreateWebStreamClient` is Studio-only and supports streaming protocols including WebSocket.
	- `WebStreamClient:Send()` works only for clients created with `Enum.WebStreamClientType.WebSocket`.
	- Maximum of 6 active `WebStreamClient` clients at one time.
	- Plugin secret handling is limited; do not assume plugin access to all secret sources in local workflows.

Communication matrix (required)
-------------------------------

| Channel | Direction | Reliability | Latency | Best Use | Required in plan |
|---|---|---|---|---|---|
| HTTP JSON-RPC (`POST /mcp`) | Studio↔Server | High (request/response + retry) | Medium | Authoritative control and mutations | Yes (primary) |
| WS (`/mcp-stream` + WS-RPC) | Studio↔Server | Medium→High (after replay/heartbeat) | Low | Live updates, push, optional RPC | Yes |
| WebStream Raw/SSE | Server→Studio | Medium | Low | Token streams/progress streams | Yes (fallback option) |
| Rojo file sync | VS Code↔Studio | High (file-based) | Medium | Source of truth for scripts/files | Yes |
| ScriptEditorService events | Studio internal | N/A transport | N/A | Triggering sync/lint/update workflows | Yes (integration points) |

Execution rule: No single channel is sufficient for all use cases. The executable architecture is hybrid by design:
- HTTP JSON‑RPC for correctness-critical operations.
- WS/WebStream for real-time push and lower-latency UX.
- Rojo/file-backed flow for durable source synchronization.

Protocol Summary
----------------
- Server→client envelope:

```json
{ "seq": number, "type": string, "sessionId"?: string, "payload": object }
```

- Client→server RPC (preferred): JSON‑RPC 2.0. Server must map WS requests into the same internal dispatch used by HTTP handlers.
- Replay API: `GET /mcp/replay?since=<seq>&limit=<n>` and WS `{ "cmd":"replay", "since": <seq>, "limit": <n> }`.
- Error and code model follow `crates/mcp-core` standard error codes.

Staged plan (with explicit substeps, files, acceptance criteria)
----------------------------------------------------------------

Stage A — Spec & config (low-risk)
	- A.1: Add `docs/ws_protocol.md` describing envelope, replay, auth, limits, examples. (File: `docs/ws_protocol.md`)
	- A.2: Add `cmd/mcp-server/src/config.rs` to parse envs (`MCP_*`) and export `Config`. Use defaults favoring localhost. (File: `cmd/mcp-server/src/config.rs`)
	- A.3: Add `docs/studio_transport_matrix.md` documenting the communication matrix above and when to use HTTP vs WS vs RawStream.
	- Acceptance: docs present; `Config::from_env()` returns expected defaults and is used in `main.rs`.

Stage B — Modularize WS (non-breaking)
	- B.1: Create `cmd/mcp-server/src/ws.rs` with `register_ws_routes(router, state, config)` and port existing `/mcp-stream` logic into it. Keep old exports until tests pass.
	- B.2: Add env gating: when `MCP_ENABLE_WS_RPC=false` and non-local, refuse WS-RPC upgrades. Passive push (existing `/mcp-stream`) may remain.
	- Acceptance: server compiles; no change in existing HTTP behavior.

Stage C — Auth & receive (core feature)
	- C.1: Implement `validate_upgrade(headers, state) -> Result<UserCtx, Reject>` supporting `Authorization: Bearer <token>` and `Sec-WebSocket-Protocol` token. Token store in `AppState` or simple dev token file for local dev.
	- C.2: Implement concurrent receive loop that dispatches WS requests into the internal handler used by HTTP RPC. Enforce `MCP_MAX_WS_MESSAGE_SIZE` and close on malformed JSON with `INVALID_REQUEST` error.
	- Acceptance: an authorized WS client can call e.g. `openSession` and receive the same response semantics as `POST /mcp`.
	- C.3: Add compatibility mode for Studio WebStream clients (`Enum.WebStreamClientType.WebSocket` and `RawStream`) so plugin-side client choice can be feature-flagged.

Stage D — Sequencing & replay
	- D.1: Add `seq` counter in `AppState`, atomically incrementing for each broadcast and persisting the last `MCP_SEQ_RETENTION` events in a ring buffer.
	- D.2: Implement `GET /mcp/replay` and WS replay command; ensure ordering and idempotency.
	- Acceptance: integration test demonstrates disconnect+reconnect with replay returns all missed events in order.

Stage E — Backpressure, heartbeat, ops
	- E.1: Implement bounded per-client send queue with configured policy; record metrics on drops.
	- E.2: Application-level heartbeat + graceful close and server shutdown flush.
	- Acceptance: under simulated slow consumers, server remains stable and metrics reflect backpressure.

Stage F — Clients & plugin
	- F.1: Update `studio_action_scripts/cli/index.js` to support `--auth-token` and `--since` flags.
	- F.2: Update plugin `ConnectionManager.lua` to choose transport in order:
		1) `WebStreamClientType.WebSocket` when available/configured,
		2) `RawStream` when endpoint exposes streaming-only responses,
		3) HTTP subscribe/poll fallback.
	- F.3: Integrate `ScriptEditorService` hooks (`TextDocumentDidChange`, `UpdateSourceAsync` paths already used by plugin security context) so editor events can trigger transport actions without replacing transport logic.
	- Acceptance: plugin in dev mode uses WS; when WS fails, plugin uses HTTP unchanged.

Stage G — Tests, CI & release
	- G.1: Unit tests for ws module and config.
	- G.2: Integration `tools/run_ws_replay_task.ps1` to validate end-to-end replay and auth.
	- G.2b: Integration `tools/run_stream_client_compat_task.ps1` to validate Studio-compatible WebStream behavior for WS and RawStream modes.
	- G.3: CI workflow `ws_integration` to run integration test; gate Rojo parity tasks.
	- Acceptance: CI green and artifacts updated with docs.

Stage G execution status (2026-03-02)
	- [x] Completed Stage F.3 by wiring guarded `ScriptEditorService.TextDocumentDidChange` hooks in plugin `SyncEngine` to trigger Source patch flow for observed script instances.
	- [x] Added `tools/run_ws_replay_task.ps1` (runs reconnect/replay contract + WS CLI replay/auth smoke and emits `tools/ws_replay_report.json`).
	- [x] Added `tools/run_stream_client_compat_task.ps1` (validates plugin WebSocket/RawStream/HTTP fallback invariants and emits `tools/stream_client_compat_report.json`).
	- [x] Added dedicated CI workflow `.github/workflows/ws_integration.yml` that runs WS transport checks and gates optional parity task execution behind successful WS checks.
	- [x] Updated `.github/workflows/ci.yml` with optional `run_ws_transport_suite` dispatch input and report artifact upload (`ws-transport-reports`) for consolidated CI path.
	- [x] Added migration documentation `docs/ws_transport_migration_guide.md` and linked it in `README.md`.

Roblox-doc accuracy checklist (must pass before merge)
------------------------------------------------------
- `HttpService.HttpEnabled` handling documented and validated in setup guidance.
- `CreateWebStreamClient` Studio-only assumption reflected in plugin/client design.
- `WebStreamClient:Send()` used only when `WebSocket` client type is selected.
- Concurrency limits for stream clients (<=6 active) enforced in plugin connection manager.
- Plan retains HTTP fallback for environments where WS/WebStream is unavailable or restricted.

Failure-mode requirements (executable)
--------------------------------------
- If WS upgrade/auth fails: plugin/CLI automatically degrade to HTTP JSON‑RPC polling/subscription.
- If replay window exceeded: client reboots session with `openSession` + `readTree` rebaseline.
- If stream-client cap reached (6): close least-recently-used stream and log structured warning.
- If `HttpEnabled` is false: surface explicit setup guidance and block network transport startup.

Implementation notes & sample snippets
------------------------------------
- Example axum upgrade handler (use `ws.rs` module):

```rust
use axum::extract::WebSocketUpgrade;
async fn handle_ws_upgrade(
		ws: WebSocketUpgrade,
		headers: HeaderMap,
		State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
		if !allow_upgrade(&headers, &state) {
				return (StatusCode::FORBIDDEN, "ws auth required");
		}
		ws.on_upgrade(|socket| ws::ws_handler(socket, state))
}
```

- Receive loop sketch:

```rust
loop {
		tokio::select! {
				msg = socket.recv() => match msg { /* parse/dispatch */ }
				broadcast = rx.recv() => { socket.send(...).await }
		}
}
```

Testing & commands
------------------
- Unit tests:
```powershell
cargo test -p mcp-server
```
- Integration replay test (dev):
```powershell
powershell -File tools/run_ws_replay_task.ps1
```

Observability & metrics
-----------------------
- Emit structured logs: `ws.upgrade`, `ws.auth.success`, `ws.auth.fail`, `ws.replay.request`, `ws.replay.sent`.
- Counters: `ws_connections`, `ws_auth_failures`, `ws_send_errors`, `ws_backpressure_drops`, `ws_seq_current`.

PR checklist
------------
- Unit tests included and passing.
- Docs updated: `docs/ws_protocol.md` and `README.md`.
- CI workflow updated if required.
- Migration note for plugin authors.

Staged AI prompts (for automation)
----------------------------------
Use these as direct assistant tasks. Each prompt expects the assistant to modify code, add tests, and update docs.

- Prompt A (spec & config):
	"Create `docs/ws_protocol.md` describing the WS envelope, replay and auth. Add `cmd/mcp-server/src/config.rs` to parse `MCP_*` envs with defaults. Wire `Config` into `main.rs`. Add unit tests verifying defaults."

- Prompt B (refactor module):
	"Refactor existing WS code into `cmd/mcp-server/src/ws.rs` exposing `register_ws_routes`. Keep existing HTTP behavior. Add unit tests ensuring no behavioral change."

- Prompt C (auth & receive):
	"Implement upgrade auth and a concurrent receive loop that dispatches WS client requests to internal RPC handlers. Enforce message size and return clear close codes on error. Add tests and a sample `studio_action_scripts/cli` authorized client."

- Prompt D (replay):
	"Add `seq` generation and retention in `AppState`, implement `GET /mcp/replay` and WS replay, and add integration test verifying replay correctness."

- Prompt E (ops):
	"Implement per-client bounded queues, backpressure policy, heartbeat and graceful shutdown behavior. Add stress test and metrics."

- Prompt F (clients):
	"Add `--auth-token` and `--since` to `studio_action_scripts/cli/index.js`, and update plugin `ConnectionManager.lua` to prefer WS then fallback to HTTP. Include small functional tests."

Progress tracking
-----------------
- Track task completion by updating the checklist in this file and using the provided `manage_todo_list` helper. Consider adding `tools/mark_task_complete.ps1` to automate updates.

Next steps (recommended)
------------------------
1. Open PR for Stage A: add `docs/ws_protocol.md` and `cmd/mcp-server/src/config.rs`, wire into `main.rs` and add unit tests.
2. After PR A merges, open PR for Stage B to create `ws.rs` skeleton and confirm compile/test.

---
This plan is intentionally prescriptive and contains the guardrails necessary for safe incremental rollout. Tell me whether to (1) open PR for Stage A now, or (2) start implementing Stage B skeleton next.

