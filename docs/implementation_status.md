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

## Last-Mile Plan (Spec-Complete Gates)

### Milestone 1 — Serve-Semantic Parity Lock

Current: IN PROGRESS

Goal: Close remaining behavioral differences with Rojo serve internals for snapshot/read/subscribe/apply flows.

Deliverables:
- Expand parity contract suite to cover remaining edge semantics across IDs, metadata, and changefeed behavior.
- Run side-by-side parity checks against live Rojo serve for agreed fixture projects.

Pass/Fail gate:
- **PASS** if parity suite shows no unresolved behavioral deltas for agreed fixtures and all existing contract tests remain green.
- **FAIL** if any blocking semantic mismatch remains (especially cursor, mutation, or changefeed equivalence).

### Milestone 2 — Integration and Reliability Hardening

Current: IN PROGRESS

Goal: Prove stable plugin+server behavior under realistic reconnect/conflict/long-running usage.

Deliverables:
- Add plugin+server integration/e2e scenarios in CI.
- Add soak/reliability checks for reconnect windows, stale cursor replay, invalid-session recovery, and conflict rollback loops.

Pass/Fail gate:
- **PASS** if integration suite is green in CI and reliability runs complete without unrecovered sync divergence.
- **FAIL** if any test leaves plugin/server out of sync without deterministic recovery.

### Milestone 3 — Distribution and Day-0 Usability

Current: FAIL

Goal: Ship a repeatable install/run path for new users without dev-only manual steps.

Deliverables:
- Plugin packaging + versioned distribution workflow.
- Server artifact packaging and release workflow.
- Finalized Day-0 onboarding validation against fresh-machine setup.

Pass/Fail gate:
- **PASS** if a fresh user can install, run, connect, and complete a live-authoring round trip using published artifacts and docs only.
- **FAIL** if setup still requires source-level/manual developer-only steps.

### Spec-Complete Declaration Criteria

Declare “spec-complete” only when **all** milestone gates above are in PASS state simultaneously.

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
  - Rojo parity diff script: `tools/rojo_parity_diff_check.ps1` (normalized MCP vs live Rojo comparison report).
  - One-click Rojo parity diff flow: `tools/run_rojo_parity_diff_task.ps1` (parameterized by `-ProjectFile`, `-ReportPath`, and optional `-MutationFilePath` for reversible changefeed exercise).
  - One-click Rojo parity suite flow: `tools/run_rojo_parity_suite_task.ps1` (runs all fixtures with fail-on-diff, including mutation parity checks; supports optional `-Categories`, `-Fixtures`, and `-DryRun` filtering/preview options).
  - Parity fixture manifest: `tools/parity_fixtures.json` (suite fixture definitions are now data-driven with fixture metadata: `name`, `category`, `enabled`).
  - One-click local parity release gate flow: `tools/run_rojo_parity_release_gate_task.ps1` (runs fixture suite and strict summary checks; supports optional `-Categories`, `-Fixtures`, and `-DryRun` filtering/preview options).
  - Fixture coverage now includes: `default.project.json`, `fixtures/complex.project.json`, `fixtures/service_heavy.project.json`, `fixtures/nested_modules.project.json`, `fixtures/mixed_services.project.json`, `fixtures/lifecycle_ops.project.json`, `fixtures/ui_container.project.json`, `fixtures/serverstorage_flow.project.json`, and `fixtures/presentation_services.project.json`.
  - Latest baseline fixture parity run (`default.project.json`) reports `diffCount=0` in `tools/parity_diff_report.json`.
  - Latest complex fixture parity run (`fixtures/complex.project.json`) reports `diffCount=0` in `tools/parity_diff_report_complex.json`.
  - Latest service-heavy fixture parity run (`fixtures/service_heavy.project.json`) reports `diffCount=0` in `tools/parity_diff_report_service_heavy.json`.
  - Latest nested-modules fixture parity run (`fixtures/nested_modules.project.json`) reports `diffCount=0` in `tools/parity_diff_report_nested_modules.json`.
  - Latest mixed-services fixture parity run (`fixtures/mixed_services.project.json`) reports `diffCount=0` in `tools/parity_diff_report_mixed_services.json`.
  - Latest lifecycle-ops fixture parity run (`fixtures/lifecycle_ops.project.json`) reports `diffCount=0` in `tools/parity_diff_report_lifecycle_ops.json`.
  - Latest ui-container fixture parity run (`fixtures/ui_container.project.json`) reports `diffCount=0` in `tools/parity_diff_report_ui_container.json`.
  - Latest serverstorage fixture parity run (`fixtures/serverstorage_flow.project.json`) reports `diffCount=0` in `tools/parity_diff_report_serverstorage_flow.json`.
  - Latest presentation-services fixture parity run (`fixtures/presentation_services.project.json`) reports `diffCount=0` in `tools/parity_diff_report_presentation_services.json`.
  - Cross-platform protocol contract script: `tools/mcp_protocol_contract_test.py`.
  - Windows protocol task runner: `tools/run_mcp_protocol_task.ps1`.
  - Linux/macOS protocol task runner: `tools/run_mcp_protocol_task.sh`.
  - Server-only run script: `tools/run_mcp_server.ps1`.
  - Rojo compatibility check script: `tools/rojo_compat_check.ps1`.
  - VS Code tasks for server run, smoke, policy contract, Rojo compatibility, Rojo changefeed edge-case, conflict race contract, reconnect/replay contract, invalid-session contract, Rojo parity diff, Rojo parity suite, Rojo parity release gate, and protocol contract flows.
  - GitHub Actions CI (`.github/workflows/ci.yml`) runs:
    - Windows: tests + smoke + policy contract + Rojo compatibility + Rojo changefeed edge-case + conflict race + reconnect/replay + invalid-session + protocol contract checks,
    - Linux/macOS: tests + protocol contract checks.
  - Optional CI parity gate: manual `workflow_dispatch` with `run_rojo_parity_diff=true` runs Rojo parity fixture suite on Windows (skips if `rojo` CLI is not present).
  - Optional strict manual parity mode: set `workflow_dispatch` input `strict_rojo_parity=true` to fail when parity reports are missing or when total diffs are non-zero.
  - Optional targeted strict manual parity mode: set `workflow_dispatch` input `strict_rojo_parity_categories` to comma-separated category names to execute only selected fixture categories and fail when those categories have non-zero diffs.
  - Manual parity runs generate `tools/parity_diff_summary.json` from `tools/parity_diff_report*.json` (including fixture metadata and category breakdown), print `Parity summary: fixtures=<n> totalDiffs=<n> categoryDiffs=<category:diffs|...>` in CI logs, and upload both as workflow artifact `rojo-parity-reports` for inspection/download.

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
