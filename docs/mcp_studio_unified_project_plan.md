# MCP Server + Roblox Studio Plugin: Unified Project Plan

Last updated: 2026-02-25 (reviewed against Context7 MCP, Rojo, and Roblox Creator docs; implementation progress synced)

## Executive Decision

### Active Delivery Target

**Target: production-like live authoring from VS Code files.**

This means file edits under the project source tree are treated as the primary authoring input, surfaced through MCP change cursors, and reflected into Studio with deterministic conflict handling.

Use a **hybrid approach**:

- Reuse and extend Rojo internals (`librojo`, ServeSession, existing sync semantics) for the MCP server core.
- Build a new Roblox Studio plugin (Luau) for UX, workflow, and protocol-aware synchronization.

This gives the best balance of functionality, reliability, and maintainability versus a full rewrite.

## Scope and Outcomes

### In scope

- MCP-compatible server that exposes Roblox project/state operations through MCP lifecycle and capability conventions.
- Roblox Studio plugin that connects to the server, synchronizes state, and provides connection/status/conflict UX.
- Backward-compatibility bridge for existing Rojo-style HTTP integrations during migration.

### Out of scope (initial release)

- Re-implementing Rojo core project parsing/snapshot logic from scratch.
- Multi-tenant remote SaaS hosting architecture.
- Full cloud auth platform beyond local/team token support.

## Goals

- Provide fast, reliable two-way sync between local dev tools (including VS Code flows) and Roblox Studio.
- Align with current MCP lifecycle and capability negotiation patterns.
- Keep migration risk low by preserving Rojo behavior and adding protocol adapters.
- Establish a clear CI/release model for server + plugin with compatibility gates.

## Architecture (Updated)

- **MCP Server (Rust)**
  - Built as a new crate/binary that wraps `librojo` and `ServeSession`.
  - Implements MCP lifecycle: `initialize` handshake, capability declaration, and `notifications/initialized` flow.
  - Publishes resource/tool surfaces mapped to Rojo operations.

- **Roblox Studio Plugin (Luau)**
  - Uses Studio plugin APIs for UI and DataModel operations.
  - Uses `HttpService:RequestAsync` transport path for robust Studio compatibility.
  - Handles reconnect, cursor resume, patch apply, and conflict prompts.

- **Compatibility Layer**
  - Keep or provide adapter behavior for legacy Rojo serve endpoints (`/api/rojo`, `/api/read/{instanceId}`, `/api/subscribe/{sessionId}/{cursor}`) during transition.

## Transport Strategy (MCP + Studio Reality)

### Canonical MCP behavior

- Support MCP initialization and capability negotiation per current spec.
- Prefer MCP-compliant server endpoint behavior for modern clients.
- Plan compatibility behavior for older HTTP+SSE patterns where needed (migration support).

### Studio transport choice

- Primary: HTTP request/response + long-poll style subscription compatible with Studio plugin networking patterns.
- Requirement: project must enable **Allow HTTP Requests** for plugin networking flows that call external/local endpoints.
- Optional future: add alternate streaming transport only after Studio-side reliability is proven.

## MCP Surface Design

### MCP lifecycle alignment

- `initialize`: negotiate `protocolVersion`, advertise capabilities.
- `notifications/initialized`: begin active notifications/subscriptions.
- Capability declaration includes resource/tool availability and subscription support.

### Domain mapping

- Rojo tree/snapshot data mapped to MCP resources.
- Patch and mutation operations mapped to MCP tools.
- Cursor-based change feeds mapped to resource subscription notifications.

## MCP Server Design Details

### Core responsibilities

- Load and monitor Rojo projects via `librojo` APIs.
- Manage sessions, cursors, and replay windows for disconnect recovery.
- Expose health, diagnostics, and protocol/version metadata.

### Reliability requirements

- Idempotent mutation calls (`patchId`/operation IDs).
- Ordered update delivery per session cursor.
- Reconnect with cursor resume and bounded replay.
- Backpressure handling and timeout controls.

### Security requirements

- Localhost default bind for development.
- Token-based auth for non-local usage.
- Input validation and authorization checks on all mutation operations.
- Structured audit logging for apply operations.

## Studio Plugin Design Details

### Core modules

- `ConnectionManager`: initialize/auth/retry/heartbeat.
- `SyncEngine`: snapshot bootstrap, cursor subscriptions, inbound patch application.
- `PatchSerializer`: Studio changes ↔ patch payloads.
- `UI`: dock widget, connection status, sync health, conflict resolution actions.

### Studio-specific behaviors

- Integrate with `ChangeHistoryService` so plugin-applied edits are undoable.
- Keep UI responsive during sync operations.
- Provide safe fallback states when connectivity degrades.

## Repository and Deliverables

### Proposed structure

- `cmd/mcp-server/` (Rust entrypoint)
- `crates/mcp-core/` (protocol mapping + session orchestration)
- `crates/rojo-adapter/` (thin wrapper around `librojo` integration points)
- `plugin/mcp-studio/` (Luau plugin source)
- `docs/` (protocol, operations, compatibility matrix)
- `ci/` (build/test/package workflows)

### Release deliverables

- Versioned MCP server binaries (Windows/macOS/Linux).
- Versioned Studio plugin package and install guide.
- Compatibility matrix (server version ↔ plugin version ↔ protocol version).

## Implementation Plan (Phased)

### Phase 0: Baseline and contracts

- Clone and baseline Rojo build/tests.
- Freeze initial MCP contract and capability set.
- Define compatibility target versions.

### Phase 1: Thin MCP adapter over Rojo

- Implement lifecycle (`initialize`, `initialized`) and health/info endpoints.
- Implement read/snapshot + cursor subscribe.
- Add compatibility endpoints for current Rojo flows.

### Phase 2: Studio plugin MVP

- Connect + authenticate + bootstrap snapshot.
- Subscribe and render sync status.
- Apply simple edit round-trip with undo support.

### Phase 3: Mutation hardening

- Idempotent apply operations with conflict handling.
- Retry/recovery semantics and replay windows.
- Security hardening and audit logging.

### Phase 4: Production readiness

- Full CI matrix, packaging, upgrade path, and documentation.
- Performance tuning and scalability validation.

## Testing Strategy

### Server tests

- Unit: lifecycle handlers, capability negotiation, patch validation.
- Integration: in-process Rojo sessions with multi-client subscription tests.
- Compatibility: verify legacy endpoint adapter behavior.

### Plugin tests

- Unit-style module tests for serializer/sync engine logic.
- Studio integration runs validating connect/sync/disconnect/reconnect.
- Undo/redo behavior and conflict UI flow checks.

### End-to-end tests

- Snapshot bootstrap latency target checks.
- Cursor resume correctness after forced disconnect.
- Patch idempotency and ordering guarantees.

## Success Criteria (Revised)

- MCP lifecycle compliance: initialize negotiation + capability declaration + initialized flow pass.
- Studio plugin can connect, bootstrap snapshot, subscribe, and perform one edit round-trip with undo.
- Recovery: reconnect with cursor resume without state divergence.
- CI publishes reproducible binaries/plugin artifacts and passes compatibility tests.

## Risks and Mitigations (Revised)

- **Protocol drift**: lock explicit protocol versions and enforce compatibility tests in CI.
- **Transport mismatch**: keep HTTP-compatible path for Studio while MCP-native path evolves.
- **Security regressions**: token auth, mutation validation, audit logs, and local-only defaults.
- **Behavior divergence from Rojo**: keep Rojo adapter thin and validate outputs against current serve behavior.

## Immediate Next Actions

1. Clone Rojo and run baseline build/tests.
2. Draft MCP contract doc (lifecycle, capabilities, resources/tools mapping, error model).
3. Scaffold `mcp-server` + `mcp-core` crates with `initialize` and `GetServerInfo` equivalents.
4. Scaffold `plugin/mcp-studio` with connection/status widget and snapshot bootstrap.
5. Add compatibility adapter tests against Rojo-style read/subscribe semantics.

## Implementation Progress (Current)

### Completed in workspace

- Rust workspace scaffold (`cmd/mcp-server`, `crates/mcp-core`, `crates/rojo-adapter`) is implemented and builds.
- MCP lifecycle baseline implemented: `initialize` and `notifications/initialized`.
- Tool endpoints implemented: `roblox.openSession`, `roblox.readTree`, `roblox.subscribeChanges`, `roblox.applyPatch`, `roblox.closeSession`.
- Session state implemented with:
  - monotonic cursors,
  - idempotent patch handling (`patchId`),
  - filesystem-backed snapshots and incremental changes.
- Conflict baseline implemented:
  - `baseCursor` checks,
  - field-level write tracking,
  - structured `conflictDetails` responses.
- Studio plugin MVP implemented:
  - connect/bootstrap/polling loop,
  - local change patching (`Name`, `Source`),
  - remote apply (`added`, `updated`, `removed`),
  - rollback for conflicts,
  - conflict UI panel + manual “Re-read selected” action.
- Validation tooling implemented:
  - `tools/mcp_smoke_test.ps1`,
  - `tools/run_mcp_smoke_task.ps1`,
  - VS Code tasks for server-only and smoke-test flows.
- Filesystem-backed live authoring baseline implemented:
  - session source roots resolve to real directories,
  - tree snapshots are built from `.lua` files,
  - `subscribeChanges` emits diffs from filesystem edits,
  - `setProperty(Source)` writes back to source files for file-backed instances.
- Rojo compatibility HTTP endpoints implemented:
  - `POST /api/rojo`,
  - `GET /api/read/{instanceId}`,
  - `GET /api/subscribe/{sessionId}/{cursor}`.
- `librojo` integration started in adapter:
  - adapter now loads Rojo snapshots via `librojo` when a project file is provided,
  - fallback mapper remains active for `src`-only file-first workflows.
- Parity-layer increment delivered:
  - Rojo snapshot IDs in adapter are now metadata-aware and stable,
  - metadata path resolution prioritizes script files for safe `Source` syncback,
  - `.luau` files are now included in script-path handling.
  - structural mutation ops (`addInstance`/`removeInstance`) are blocked in file-backed sessions to keep state aligned with filesystem source of truth.
  - file-backed mutation rules now enforce durability (`setProperty(Source)` only), rejecting non-persistable writes (`setName` and non-`Source` properties).
  - server now advertises policy metadata (`supportsStructuralOps`, `fileBackedMutationPolicy`) and plugin consumes it to proactively block unsupported local edits.
  - automated policy contract test added to verify capability fields and mutation rejection/acceptance behavior end-to-end.
  - CI workflow added to run Rust tests and all contract checks (smoke, policy, Rojo compatibility) on push/PR.
  - CI expanded with Linux/macOS matrix for protocol-level contract checks.
  - Windows one-click protocol contract runner added for local parity validation without shell-specific setup.

### Remaining before production-ready

- Complete `librojo` parity: align IDs/metadata/update semantics with Rojo serve session behavior.
- Add payload parity verification and edge-case coverage for compatibility endpoints.
- Add robust integration/e2e test automation and packaging pipeline.
- Finalize conflict policy UX and telemetry/audit coverage.

## Objective Likelihood and Risk Gates

### Likelihood Assessment

Current assessment: **High likelihood** of meeting project objectives, provided transport/recovery/conflict handling are implemented in the MVP rather than deferred.

Rationale:

- MCP lifecycle/capability model supports the server contract and subscription patterns required for tool-driven sync.
- Rojo already provides production-proven read and cursor-based change feed primitives (`/api/read`, `/api/subscribe`).
- Roblox Studio plugin APIs support the required UX and state integration (`DockWidgetPluginGui`, `ChangeHistoryService`, `HttpService:RequestAsync`).

### Critical Risk Gates (must pass)

1. **Bootstrap gate**
  - Studio plugin connects and boots a full snapshot consistently within target latency.
2. **Round-trip gate**
  - A local edit from Studio and a file-side edit from workspace both converge without divergence in at least one full round trip.
3. **Recovery gate**
  - Forced disconnect/reconnect resumes from cursor without requiring full reload and without state drift.
4. **Conflict gate**
  - Concurrent edits produce deterministic conflict outcomes and clear user-facing resolution UX.
5. **Undo gate**
  - Plugin-applied edits are correctly integrated into `ChangeHistoryService` undo/redo flow.

### Go/No-Go Criteria for MVP

- **Go** if all five risk gates pass in automated or repeatable manual test runs for representative projects.
- **No-Go** if recovery or conflict gates fail; these are release blockers for the “easier and more productive” objective.

---

## References (Context7)

- MCP specification (lifecycle, capabilities, transports, security): modelcontextprotocol.io spec (2025-11-25).
- Rojo serve and programmatic usage: Rojo docs (`/api/rojo`, `/api/read/{instanceId}`, `/api/subscribe/{sessionId}/{cursor}`, `ServeSession`).
- Roblox Creator docs: Studio plugin APIs, `DockWidgetPluginGui`, `ChangeHistoryService`, and `HttpService:RequestAsync` + HTTP request enablement notes.
