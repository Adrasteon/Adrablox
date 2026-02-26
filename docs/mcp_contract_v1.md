# MCP Contract v1 (Working Draft)

Last updated: 2026-02-25
Status: Working draft (baseline implementation in workspace)
Related docs: `mcp_studio_unified_project_plan.md`, `proposed_structure.md`

## 1) Purpose

This document defines the initial protocol contract between:

- MCP clients (including the Roblox Studio plugin adapter flow)
- The Rust MCP server backed by Rojo (`librojo` / ServeSession)

Goals:

- Provide an implementation-ready request/response contract.
- Keep behavior compatible with Rojo sync semantics.
- Support migration from current Rojo HTTP flows to MCP lifecycle/capabilities.

## 2) Versioning

- Contract version: `v1` (this document)
- MCP protocol target: `2025-11-25`
- Server must return:
  - `protocolVersion` (MCP version)
  - `serverVersion` (server implementation version)
  - `compatibilityVersion` (server-plugin compatibility track, e.g. `1.x`)

Version policy:

- Breaking changes require `v2` document + compatibility matrix update.
- Additive fields are allowed if clients ignore unknown fields.

## 3) Transport and Session Model

### 3.1 Canonical MCP lifecycle

The server supports:

1. `initialize` request
2. `notifications/initialized`
3. regular operations (`resources/*`, `tools/*`, and notifications)

### 3.2 Studio-compatible transport behavior

- Initial implementation may be HTTP request/response with long-poll subscriptions for Studio compatibility.
- MCP semantics remain authoritative even if transport adapters are used.
- Studio-side usage requires HTTP requests enabled in project settings.

### 3.3 Session

- `sessionId` identifies a loaded Rojo project session.
- Cursors are monotonic per session for change streams.
- Reconnects may resume via last acknowledged cursor.

## 4) Capabilities (v1)

Server declares at minimum:

```json
{
  "capabilities": {
    "resources": {
      "subscribe": true,
      "listChanged": false
    },
    "tools": {
      "listChanged": false
    },
    "logging": {}
  }
}
```

## 5) Resource and Tool Mapping

### 5.1 Resources

- `roblox://session/{sessionId}/tree/{instanceId}`
  - Returns tree/subtree snapshot payload.
- `roblox://session/{sessionId}/status`
  - Returns health, root, and protocol metadata.

### 5.2 Tools

- `roblox.openSession`
- `roblox.readTree`
- `roblox.subscribeChanges`
- `roblox.applyPatch`
- `roblox.closeSession`

Notes:

- Resource reads are side-effect free.
- Tool calls may mutate state and require validation.

## 6) Lifecycle Messages

### 6.1 `initialize`

Request:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-11-25",
    "capabilities": {
      "resources": { "subscribe": true },
      "tools": {}
    },
    "clientInfo": {
      "name": "EdiyorStudioPlugin",
      "version": "0.1.0"
    }
  }
}
```

Response:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2025-11-25",
    "capabilities": {
      "resources": { "subscribe": true, "listChanged": false },
      "tools": { "listChanged": false },
      "logging": {}
    },
    "serverInfo": {
      "name": "roblox-mcp-server",
      "version": "0.1.0"
    },
    "instructions": "Use roblox.openSession before read/subscribe/apply operations."
  }
}
```

### 6.2 `notifications/initialized`

Client sends standard initialized notification before operational calls.

## 7) Tool Contracts

## 7.1 `roblox.openSession`

Purpose: Load/bind project and create active sync session.

Input:

```json
{
  "projectPath": "D:/workspace/default.project.json",
  "workspaceRoot": "D:/workspace",
  "requestedCompatibilityVersion": "1.x"
}
```

Result:

```json
{
  "sessionId": "sess_abc123",
  "serverVersion": "0.1.0",
  "compatibilityVersion": "1.x",
  "rootInstanceId": "ref_root",
  "initialCursor": "42"
}
```

Validation:

- Path must exist and resolve to a valid Rojo project.
- Reject if incompatible compatibility version.

## 7.2 `roblox.readTree`

Purpose: Read full tree or subtree.

Input:

```json
{
  "sessionId": "sess_abc123",
  "instanceId": "ref_root"
}
```

Result:

```json
{
  "cursor": "42",
  "instance": {
    "Id": "ref_root",
    "ClassName": "DataModel",
    "Name": "Game",
    "Properties": {},
    "Children": ["ref_a", "ref_b"]
  },
  "instances": {
    "ref_a": { "Id": "ref_a", "ClassName": "ReplicatedStorage", "Name": "ReplicatedStorage", "Properties": {}, "Children": [] },
    "ref_b": { "Id": "ref_b", "ClassName": "ServerScriptService", "Name": "ServerScriptService", "Properties": {}, "Children": [] }
  }
}
```

## 7.3 `roblox.subscribeChanges`

Purpose: Stream or poll incremental changes from cursor.

Input:

```json
{
  "sessionId": "sess_abc123",
  "cursor": "42",
  "timeoutMs": 30000
}
```

Result:

```json
{
  "cursor": "45",
  "added": {
    "ref_new": {
      "Id": "ref_new",
      "Parent": "ref_a",
      "Name": "MyModule",
      "ClassName": "ModuleScript",
      "Properties": { "Source": "return {}" },
      "Children": []
    }
  },
  "updated": [
    {
      "id": "ref_b",
      "changedName": "ServerScripts",
      "changedProperties": { "Name": "ServerScripts" }
    }
  ],
  "removed": ["ref_old"]
}
```

Behavior:

- No-op change response may be returned on timeout.
- Cursor must always advance monotonically when changes are emitted.

## 7.4 `roblox.applyPatch`

Purpose: Apply mutation patch(es) from plugin/client.

Input:

```json
{
  "sessionId": "sess_abc123",
  "patchId": "patch_20260225_001",
  "baseCursor": "45",
  "origin": "studio-plugin",
  "operations": [
    {
      "op": "setProperty",
      "instanceId": "ref_new",
      "property": "Source",
      "value": "return { value = 1 }"
    }
  ]
}
```

Result:

```json
{
  "accepted": true,
  "idempotent": false,
  "origin": "studio-plugin",
  "baseCursor": "45",
  "appliedCursor": "46",
  "conflicts": [],
  "conflictDetails": []
}
```

Conflict detail shape:

```json
{
  "instanceId": "ref_abc",
  "property": "Source",
  "reason": "write_conflict",
  "baseCursor": "45",
  "lastWriteCursor": "46"
}
```

Idempotency rules:

- `patchId` must be unique per `sessionId`.
- Duplicate `patchId` returns same effective result without reapplying side effects.

## 7.5 `roblox.closeSession`

Purpose: Release resources and stop updates for the session.

Input:

```json
{
  "sessionId": "sess_abc123"
}
```

Result:

```json
{
  "closed": true
}
```

## 8) Error Model

JSON-RPC envelope is used, with domain-specific `data.code` values.

Example:

```json
{
  "jsonrpc": "2.0",
  "id": 9,
  "error": {
    "code": -32000,
    "message": "Patch conflict",
    "data": {
      "code": "PATCH_CONFLICT",
      "sessionId": "sess_abc123",
      "patchId": "patch_20260225_001",
      "details": ["Instance no longer exists"]
    }
  }
}
```

Standard domain error codes:

- `INVALID_ARGUMENT`
- `UNAUTHORIZED`
- `FORBIDDEN`
- `NOT_FOUND`
- `SESSION_EXPIRED`
- `CURSOR_INVALID`
- `PATCH_CONFLICT`
- `INTERNAL_ERROR`
- `NOT_IMPLEMENTED`

## 9) Security Requirements

- Default bind to localhost for development.
- Token auth required for non-local bindings.
- Validate all mutation inputs (types, target existence, allowed operations).
- Reject malformed or oversized payloads with explicit errors.
- Log mutation operations with session/user context.

## 10) Compatibility with Existing Rojo Flows

Compatibility endpoints (adapter mode) should preserve:

- `GET /api/rojo`
- `GET /api/read/{instanceId}`
- `GET /api/subscribe/{sessionId}/{cursor}`

Mapping requirement:

- Responses must remain semantically equivalent to current Rojo output where practical.

## 11) Non-Functional Targets (v1)

- Startup to ready: <= 2s on standard dev machine.
- Snapshot bootstrap: <= 3s for medium project baseline.
- Incremental patch apply acknowledgment: <= 500ms p95 (local).
- Reconnect recovery with cursor resume: <= 2s (local).

## 12) Implementation Checklist

- [x] Implement lifecycle (`initialize`, `notifications/initialized`).
- [x] Implement tool handlers (`openSession`, `readTree`, `subscribeChanges`, `applyPatch`, `closeSession`).
- [x] Add idempotency store for `patchId`.
- [x] Add base cursor conflict checks and conflict detail payloads.
- [x] Add initial Studio plugin integration path for connect/read/subscribe/apply/rollback.
- [ ] Add cursor replay window hardening and reconnect edge-case handling.
- [ ] Add compatibility adapter tests against Rojo-style endpoints.
- [ ] Add Studio plugin integration tests for connect/read/subscribe/apply/undo.

## 13) Open Decisions

- Whether long-poll remains the only Studio transport in v1, or if a secondary streaming channel ships behind a feature flag.
- Final naming conventions for resource URIs and tool names.
- Exact authentication mechanism for team-shared setups (token format + rotation strategy).
