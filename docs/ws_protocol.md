# WebSocket Protocol (MCP)

This document describes the WebSocket envelope, optional JSON‑RPC over WS, replay API, and related operational constraints for the MCP server.

Envelope
--------

Server→client broadcast messages follow this envelope:

```json
{ "seq": number, "type": string, "sessionId"?: string, "payload": object }
```

- `seq`: monotonic sequence number assigned by the server for ordering and replay.
- `type`: message type string (e.g., `progress`, `change`, `event`).
- `sessionId`: optional session identifier for session-scoped messages.
- `payload`: JSON object with event-specific contents.

Client→Server RPC
------------------

Clients MAY use JSON‑RPC 2.0 framing over WebSocket for request/response style interactions:

```json
{ "jsonrpc": "2.0", "id": <id>, "method": "name", "params": {...} }
```

Servers SHOULD map WS JSON‑RPC requests to the same internal dispatch used for `POST /mcp` so idempotency and authorization rules are preserved.

Replay API
----------

HTTP:

```
GET /mcp/replay?since=<seq>&limit=<n>
```

WS:

```json
{ "cmd": "replay", "since": <seq>, "limit": <n> }
```

The server responds with a sequence of envelope messages starting from `since+1` up to `limit` items.

Auth & Security
---------------

- Localhost-only by default. To enable non-local WS RPC, set `MCP_ENABLE_WS_RPC=true` and `MCP_REQUIRE_WS_TOKEN=true`.
- When `MCP_REQUIRE_WS_TOKEN=true`, the server requires an `Authorization: Bearer <token>` header or the token passed in `Sec-WebSocket-Protocol` during upgrade.

Operational Limits
------------------

- `MCP_MAX_WS_MESSAGE_SIZE` (default 1MiB) — maximum inbound message size.
- `MCP_CLIENT_SEND_QUEUE_CAPACITY` (default 256) — per-client send queue capacity.
- `MCP_SEQ_RETENTION` (default 10000) — number of recent messages retained for replay.

Error model
-----------

Errors follow the standard `crates/mcp-core` JSON-RPC error schema with `error.data.code` and optional `error.data.hint`.

Examples
--------

Client replay request (WS):

```json
{ "cmd": "replay", "since": 12345, "limit": 100 }
```

Server broadcast example:

```json
{ "seq": 12346, "type": "change", "sessionId": "s-abc", "payload": { "added": [], "updated": [], "removed": [] } }
```
