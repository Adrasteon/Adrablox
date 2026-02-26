# Implementation Status

Last updated: 2026-02-26

## External Stakeholder Summary

- Delivery status: Core platform is built and functioning (server, Studio plugin, and file-backed live authoring).
- Validation status: Automated checks and CI are in place with recent green test/smoke/contract runs.
- Current readiness: Suitable for continued pilot/internal use, not yet final production parity.
- Remaining risk: Full Rojo serve behavioral parity and edge-case hardening are still in progress.
- Next milestone: Complete parity + integration hardening, then finalize packaging/release workflow.

## Current State

- Status: MVP+ baseline is implemented and operational.
- Scope delivered: MCP server + Studio plugin + file-backed live authoring + Rojo-compatible endpoints + policy contracts + CI.
- Repository state: committed on `main` (root commit `ceca931`) with local identity configured and global default branch set to `main`.

## Ready

- Core lifecycle and tool surface are implemented and working (`openSession`, `readTree`, `subscribeChanges`, `applyPatch`, `closeSession`).
- File-backed edit durability is enforced: mapped script `Source` writes persist to disk, with cursored updates and structured conflict handling.
- Rojo compatibility API routes are available (`/api/rojo`, `/api/read`, `/api/subscribe`).
- Validation baseline exists and has recent green runs across Rust tests, smoke flow, policy contract flow, and protocol contract flow.
- CI is configured to run contract checks across Windows and protocol checks across Linux/macOS.

## Not Ready

- Full behavioral parity with Rojo serve internals is not complete (especially mutation and changefeed edge semantics).
- Reconnect/replay hardening and deeper conflict-policy coverage still need expansion.
- End-to-end integration coverage between plugin and server is not yet comprehensive.
- Packaging/release automation for production distribution is not finished.

## Next Milestones

1. Complete serve-semantic parity for `librojo`-backed sessions (IDs/metadata/mutation/changefeed behavior).
2. Add parity stress tests that compare behavior against live Rojo across edge cases.
3. Harden reconnect/replay behavior and expand conflict-policy scenarios.
4. Add plugin+server end-to-end integration tests in CI.
5. Add release packaging for server artifacts and plugin distribution.

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
  - Read freshness parity improvement: read endpoints now refresh from source before serving snapshots.
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
  - Lifecycle error responses now include explicit machine-readable codes (for example `SESSION_NOT_FOUND`).
  - Conflict detail reasons now include explicit machine-readable codes (`CONFLICT_WRITE_STALE_CURSOR`, `UNSUPPORTED_FILE_BACKED_MUTATION`, `SOURCE_WRITE_FAILED`, `SOURCE_PATH_MISSING`).

- Studio plugin
  - Connect/bootstrap/polling flow.
  - Local change patching (`Name`, `Source`).
  - Remote apply (`added`, `updated`, `removed`) into Studio.
  - Conflict rollback behavior.
  - Session-lifecycle hardening: auto-recovery by opening a fresh session when server reports missing/expired session (code-first detection with message fallback).
  - Conflict UI list + manual “Re-read selected” action.

- Validation/tooling
  - Rust tests passing (`cargo test`).
  - Direct smoke script: `tools/mcp_smoke_test.ps1`.
  - One-click smoke flow: `tools/run_mcp_smoke_task.ps1`.
  - Policy contract test script: `tools/mcp_policy_contract_test.ps1`.
  - One-click policy contract flow: `tools/run_mcp_policy_task.ps1`.
  - One-click Rojo compatibility flow: `tools/run_rojo_compat_task.ps1`.
  - Rojo changefeed edge-case contract script: `tools/rojo_changefeed_edge_check.ps1`.
  - One-click Rojo changefeed edge-case flow: `tools/run_rojo_changefeed_task.ps1`.
  - Conflict race contract script: `tools/mcp_conflict_race_contract_test.ps1`.
  - One-click conflict race flow: `tools/run_mcp_conflict_race_task.ps1`.
  - Reconnect/replay contract script: `tools/mcp_reconnect_replay_contract_test.ps1`.
  - One-click reconnect/replay flow: `tools/run_mcp_reconnect_replay_task.ps1`.
  - Invalid-session contract script: `tools/mcp_invalid_session_contract_test.ps1`.
  - One-click invalid-session flow: `tools/run_mcp_invalid_session_task.ps1`.
  - Cross-platform protocol contract script: `tools/mcp_protocol_contract_test.py`.
  - Windows protocol task runner: `tools/run_mcp_protocol_task.ps1`.
  - Linux/macOS protocol task runner: `tools/run_mcp_protocol_task.sh`.
  - Server-only run script: `tools/run_mcp_server.ps1`.
  - Rojo compatibility check script: `tools/rojo_compat_check.ps1`.
  - VS Code tasks for server run, smoke, policy contract, Rojo compatibility, Rojo changefeed edge-case, conflict race contract, reconnect/replay contract, invalid-session contract, and protocol contract flows.
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
