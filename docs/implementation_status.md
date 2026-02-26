# Implementation Status

Last updated: 2026-02-26

## Summary

The project has moved from planning/scaffolding into a working MVP implementation for both the MCP server and Studio plugin.

## Completed

- Server/runtime
  - Rust workspace and runnable MCP server are in place.
  - JSON-RPC endpoint (`/mcp`) and health endpoint (`/health`) implemented.
  - Rojo compatibility endpoints implemented: `/api/rojo`, `/api/read`, `/api/subscribe`.
  - Adapter integrates `librojo` snapshot loading for `.project.json`-based sessions.
  - Parity-layer increment: Rojo-derived node IDs are now metadata-aware and stable across refreshes.
  - Lifecycle baseline implemented (`initialize`, `notifications/initialized`).

- Tool surface
  - `roblox.openSession`
  - `roblox.readTree`
  - `roblox.subscribeChanges`
  - `roblox.applyPatch`
  - `roblox.closeSession`

- State and mutation behavior
  - Filesystem-backed session/tree model with monotonic cursors.
  - Hybrid snapshot path: `librojo` for project-file inputs, filesystem mapper fallback for `src` inputs.
  - Source-root snapshots built from `.lua` files under project source directory.
  - Metadata path mapping now prefers real script files (`.lua`/`.luau`) to avoid incorrect syncback targets.
  - Structural patch operations are intentionally rejected for file-backed sessions to prevent tree/file divergence.
  - File-backed mutation semantics are durability-first: only `Source` writes are accepted, while `setName` and other property updates are rejected.
  - Session payloads now include explicit mutation policy metadata for clients.
  - Studio plugin enforces policy client-side to block unsupported edits before patch submission.
  - Filesystem changes surfaced through `subscribeChanges` cursor updates.
  - `setProperty(Source)` persists updates back to mapped source files.
  - Idempotent patch behavior keyed by `patchId`.
  - Field-level conflict detection using `baseCursor`.
  - Structured conflict metadata returned for client handling.

- Studio plugin
  - Connect/bootstrap/polling flow.
  - Local change patching (`Name`, `Source`).
  - Remote apply (`added`, `updated`, `removed`) into Studio.
  - Conflict rollback behavior.
  - Conflict UI list + manual “Re-read selected” action.

- Validation/tooling
  - Rust tests passing (`cargo test`).
  - Direct smoke script: `tools/mcp_smoke_test.ps1`.
  - One-click smoke flow: `tools/run_mcp_smoke_task.ps1`.
  - Policy contract test script: `tools/mcp_policy_contract_test.ps1`.
  - One-click policy contract flow: `tools/run_mcp_policy_task.ps1`.
  - One-click Rojo compatibility flow: `tools/run_rojo_compat_task.ps1`.
  - Cross-platform protocol contract script: `tools/mcp_protocol_contract_test.py`.
  - Windows protocol task runner: `tools/run_mcp_protocol_task.ps1`.
  - Linux/macOS protocol task runner: `tools/run_mcp_protocol_task.sh`.
  - Server-only run script: `tools/run_mcp_server.ps1`.
  - Rojo compatibility check script: `tools/rojo_compat_check.ps1`.
  - VS Code tasks for server run, smoke, policy contract, Rojo compatibility, and protocol contract flows.
  - GitHub Actions CI (`.github/workflows/ci.yml`) runs:
    - Windows: tests + smoke + policy contract + Rojo compatibility checks,
    - Linux/macOS: tests + protocol contract checks.

## In Progress / Remaining

- Expand current `librojo` integration to full Rojo serve parity (IDs, metadata, mutation semantics).
- Add parity and edge-case compatibility tests against live Rojo serve behavior.
- Add reconnect/replay hardening and broader conflict policy options.
- Add automated integration/e2e tests for plugin + server.
- Add packaging/release automation for plugin distribution and server artifacts.

## Quick Verification Commands

```powershell
Set-Location D:\roblox
$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
& $cargoExe test
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_smoke_task.ps1
```
