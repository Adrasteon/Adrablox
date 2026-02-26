# Proposed Language and Repository Structure

Last updated: 2026-02-25 (aligned with `mcp_studio_unified_project_plan.md`)

## Executive Summary

- **Architecture choice**: Hybrid.
  - Reuse Rojo internals (`librojo` + ServeSession semantics) for core sync/state behavior.
  - Build a new Roblox Studio plugin (Luau) for UX and protocol-aware synchronization.
- **Primary languages**:
  - MCP server: Rust.
  - Studio plugin: Luau.

## Why this structure

- Maximizes reliability by reusing proven Rojo behavior.
- Improves maintainability by keeping custom code focused on protocol adapters and plugin UX.
- Reduces delivery risk compared with a full from-scratch sync engine rewrite.

## MCP Server Stack (Aligned)

- Language/runtime:
  - Rust + `tokio`.
- Core dependencies:
  - `librojo` for project/session/tree/snapshot integration.
  - JSON-RPC + HTTP tooling via `axum`/`hyper` + `serde`/`serde_json` (exact crate selection can vary).
- Protocol behavior:
  - Implement MCP lifecycle (`initialize`, capability negotiation, `notifications/initialized`).
  - Declare resources/tools capabilities and subscription support explicitly.
  - Keep protocol versioning explicit and tested.
- Compatibility:
  - Maintain compatibility behavior for Rojo-style endpoints during migration (`/api/rojo`, `/api/read/{instanceId}`, `/api/subscribe/{sessionId}/{cursor}`).

## Transport Model (Important Update)

- **Canonical MCP layer**: MCP lifecycle and capability semantics.
- **Studio plugin transport (initial)**: HTTP request/response + long-poll style subscriptions for robust Studio compatibility.
- **Operational requirement**: enable **Allow HTTP Requests** in Roblox Studio project settings.
- **Future extension**: evaluate alternate streaming transport only after HTTP path is proven stable in Studio.

## Studio Plugin Structure (Aligned)

- Language: Luau.
- Modules:
  - `ConnectionManager` — initialize/auth/retry/heartbeat.
  - `SyncEngine` — bootstrap snapshot, cursor subscriptions, inbound sync.
  - `PatchSerializer` — Studio changes ↔ patch payload mapping.
  - `UI` — dock widget, status/health indicators, conflict resolution actions.
- Studio integration requirements:
  - Use `ChangeHistoryService` for undoable plugin-applied edits.
  - Keep DataModel updates safe and ordered.
  - Provide reconnect-safe behavior with cursor resume.

## Recommended Repository Layout

- `cmd/mcp-server/` — server entrypoint binary.
- `crates/mcp-core/` — MCP lifecycle/capabilities/session orchestration.
- `crates/rojo-adapter/` — thin integration boundary over `librojo`.
- `plugin/mcp-studio/` — Luau plugin source.
- `docs/` — protocol contracts, compatibility matrix, operational guides.
- `ci/` — build, test, packaging, and compatibility workflows.

## Reliability and Security Requirements

- Idempotent mutation operations (`patchId`/operation IDs).
- Ordered cursor-based delivery and reconnect replay windows.
- Localhost-default bind mode for dev.
- Token auth for non-local use.
- Input validation, authorization checks, and apply-operation audit logs.

## Testing and CI Expectations

- Server:
  - Unit tests for lifecycle/capability handlers and validation.
  - Integration tests with in-process Rojo sessions and multi-client subscriptions.
  - Compatibility tests for legacy endpoint behavior.
- Plugin:
  - Module-level tests for serializer/sync logic.
  - Studio integration checks for connect/sync/reconnect and undo flow.
- E2E:
  - Snapshot bootstrap and patch round-trip validation.
  - Cursor resume correctness after forced disconnect.

## Build Order (Scaffold Sequence)

1. Scaffold `cmd/mcp-server` + `crates/mcp-core` + `crates/rojo-adapter`.
2. Implement MCP lifecycle + server info/read/subscribe baseline.
3. Scaffold `plugin/mcp-studio` with connection widget and snapshot bootstrap.
4. Add mutation flow (`ApplyPatch` equivalent), idempotency, and conflict handling.
5. Add compatibility tests + packaging + version matrix docs.

## Notes

- This document is intentionally concise and structural.
- Full scope, milestones, risk treatment, and acceptance criteria are defined in `mcp_studio_unified_project_plan.md`.
