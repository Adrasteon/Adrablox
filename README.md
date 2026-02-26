# Ediyor Roblox MCP Workspace

Active implementation workspace for the MCP Server + Roblox Studio plugin project.

## What is included

- Rust workspace
  - `cmd/mcp-server`: runnable MCP server with `/health` and `/mcp` JSON-RPC endpoint
  - `crates/mcp-core`: protocol types and initialize/capability helpers
  - `crates/rojo-adapter`: adapter boundary with filesystem-backed Lua project snapshots
- Roblox Studio plugin (MVP implementation)
  - `plugin/mcp-studio/src`: connection manager, sync engine, patch serializer
  - `plugin/mcp-studio/ui`: dock widget with live status, conflict list, and manual re-read action
- Planning and contract docs in `docs/`
- Tooling and tasks
  - `tools/mcp_smoke_test.ps1`: direct MCP smoke test
  - `tools/run_mcp_smoke_task.ps1`: start server, run smoke test, stop server
  - `tools/mcp_policy_contract_test.ps1`: validates advertised policy + mutation rejection semantics
  - `tools/run_mcp_policy_task.ps1`: start server, run policy contract test, stop server
  - `tools/run_rojo_compat_task.ps1`: start server, run Rojo compatibility check, stop server
  - `tools/rojo_changefeed_edge_check.ps1`: validates update/add/rename/remove changefeed edge cases
  - `tools/run_rojo_changefeed_task.ps1`: start server, run Rojo changefeed edge-case check, stop server
  - `tools/mcp_conflict_race_contract_test.ps1`: validates stale-base cursor conflict semantics for patch application
  - `tools/run_mcp_conflict_race_task.ps1`: start server, run conflict race contract test, stop server
  - `tools/mcp_reconnect_replay_contract_test.ps1`: validates missed-cursor replay and future-cursor subscribe semantics
  - `tools/run_mcp_reconnect_replay_task.ps1`: start server, run reconnect/replay contract test, stop server
  - `tools/mcp_invalid_session_contract_test.ps1`: validates closed-session behavior and post-close recovery path
  - `tools/run_mcp_invalid_session_task.ps1`: start server, run invalid-session contract test, stop server
  - `tools/mcp_integration_roundtrip_contract_test.ps1`: validates open/read/apply/close/reopen/restore end-to-end integration behavior
  - `tools/run_mcp_integration_roundtrip_task.ps1`: start server, run integration roundtrip contract test, stop server
  - `tools/mcp_integration_reconnect_loop_contract_test.ps1`: validates repeated reconnect/apply/subscribe/restore integration behavior across iterations
  - `tools/run_mcp_integration_reconnect_loop_task.ps1`: start server, run reconnect-loop integration contract test, stop server
  - `tools/mcp_integration_conflict_recovery_contract_test.ps1`: validates two-session stale-cursor conflict detection and deterministic re-read/reapply recovery loops
  - `tools/run_mcp_integration_conflict_recovery_task.ps1`: start server, run integration conflict-recovery contract test, stop server
  - `tools/mcp_integration_mixed_resilience_contract_test.ps1`: validates mixed resilience path (stale-cursor conflict + closed-session `SESSION_NOT_FOUND` handling + recovery/reapply + restore)
  - `tools/run_mcp_integration_mixed_resilience_task.ps1`: start server, run integration mixed-resilience contract test, stop server
  - `tools/run_mcp_integration_soak_task.ps1`: manual higher-iteration reconnect-loop soak runner (default `-Iterations 10`)
  - `tools/run_mcp_integration_reliability_suite_task.ps1`: runs reconnect/conflict/mixed resilience gates and writes `tools/integration_reliability_report.json` evidence
  - `tools/rojo_parity_diff_check.ps1`: compares normalized MCP vs live Rojo serve snapshots and writes a diff report
  - `tools/run_rojo_parity_diff_task.ps1`: start MCP + Rojo serve, run parity diff, stop both servers
  - `tools/run_rojo_parity_suite_task.ps1`: runs parity diff against all fixture projects with fail-on-diff behavior
  - `tools/run_rojo_parity_edge_semantics_task.ps1`: runs focused parity edge-semantics checks across targeted fixture categories
  - `tools/parity_fixtures.json`: manifest defining parity suite fixture coverage (`name`, `category`, `enabled`, `projectFile`, `reportPath`, `mutationFilePath`)
  - `tools/run_rojo_parity_release_gate_task.ps1`: runs parity suite then strict summary checks (`-FailIfNoReports -FailIfDiffs`) for local release gating
  - `tools/mcp_protocol_contract_test.py`: cross-platform protocol contract checks (capabilities + session metadata)
  - `tools/run_mcp_protocol_task.ps1`: start server, run protocol contract test, stop server (Windows)
  - `tools/run_mcp_protocol_task.sh`: start server, run protocol contract test, stop server (Linux/macOS)
  - `tools/package_release_artifacts.ps1`: builds release server binary, creates versioned plugin source archive, and builds installable versioned plugin `.rbxm` when Rojo is available (or when `-RequireRojo` is used)
  - `tools/validate_release_manifest.ps1`: validates release manifest schema plus artifact naming/presence (with optional installable-artifact requirement)
  - `tools/generate_release_checksums.ps1`: generates and verifies SHA-256 checksums for release artifacts declared by the release manifest
  - `tools/run_day0_packaged_validation_task.ps1`: validates packaged artifacts by launching server from release zip, running smoke flow, and checking plugin archive contents
  - `tools/run_day0_published_artifact_validation_task.ps1`: validates Day-0 bundle readiness directly from `dist/release` artifacts using a temp project and direct MCP calls
  - `tools/run_spec_readiness_report.ps1`: computes Milestone 1/2/3 PASS/FAIL/UNKNOWN evidence from parity/reliability/release artifacts and writes `tools/spec_readiness_report.json`
  - `tools/run_release_candidate_evidence_pack_task.ps1`: runs reliability evidence + parity suite/strict summary + spec readiness in one release-candidate command
  - `tools/run_mcp_server.ps1`: run server for manual Studio testing
  - VS Code tasks: `Day-0: 1) Smoke Test (start+run+stop)`, `Day-0: 2) Run Server (manual Studio session)`, `Day-0: 3) Validate Packaged Artifacts (start+run+stop)`, `Day-0: 4) Validate Published Artifact Bundle`, `MCP: Policy Contract Test (start+run+stop)`, `MCP: Rojo Compat Test (start+run+stop)`, `MCP: Rojo Changefeed Edge Test (start+run+stop)`, `MCP: Conflict Race Contract Test (start+run+stop)`, `MCP: Reconnect Replay Contract Test (start+run+stop)`, `MCP: Invalid Session Contract Test (start+run+stop)`, `MCP: Integration Roundtrip Contract Test (start+run+stop)`, `MCP: Integration Reconnect Loop Contract Test (start+run+stop)`, `MCP: Integration Conflict Recovery Contract Test (start+run+stop)`, `MCP: Integration Mixed Resilience Contract Test (start+run+stop)`, `MCP: Integration Soak Contract Test (manual, start+run+stop)`, `MCP: Integration Reliability Suite (manual evidence)`, `MCP: Spec Readiness Report`, `MCP: Release Candidate Evidence Pack`, `MCP: Rojo Parity Diff (start+run+compare+stop)`, `MCP: Rojo Parity Suite (fixtures, fail-on-diff)`, `MCP: Rojo Parity Edge Semantics (focused)`, `MCP: Rojo Parity Release Gate (suite+strict-summary)`, `MCP: Protocol Contract Test (start+run+stop)`, `Release: Package Server + Plugin Artifacts`, `Release: Package Versioned Plugin Artifacts`
  - CI workflow: `.github/workflows/ci.yml` (Windows expanded contract checks + Linux/macOS protocol contract checks)
    - Optional parity gate: `workflow_dispatch` input `run_rojo_parity_diff=true` runs `tools/run_rojo_parity_suite_task.ps1` on Windows (auto-skips if `rojo` CLI is unavailable on runner)
    - Optional strict mode: set `workflow_dispatch` input `strict_rojo_parity=true` to fail the manual parity run when parity reports are missing or contain diffs.
    - Optional targeted strict mode: set `workflow_dispatch` input `strict_rojo_parity_categories` to a comma-separated category list (for example `baseline,structure`) to run only those fixture categories and fail when selected categories have diffs.
    - When this optional parity gate runs, CI builds `tools/parity_diff_summary.json` from `tools/parity_diff_report*.json`, prints `Parity summary: fixtures=<n> totalDiffs=<n> categoryDiffs=<category:diffs|...>` in job logs, and uploads both in the `rojo-parity-reports` workflow artifact.
    - Optional parity edge-semantics gate: set `workflow_dispatch` input `run_rojo_edge_semantics=true` to run focused edge-semantic parity checks across targeted categories.
    - Optional reliability evidence gate: set `workflow_dispatch` input `run_integration_reliability_suite=true` to run `tools/run_mcp_integration_reliability_suite_task.ps1` and upload `tools/integration_reliability_report.json` as workflow artifact `integration-reliability-report`.
    - Optional readiness gate: set `workflow_dispatch` input `run_spec_readiness_report=true` to generate `tools/spec_readiness_report.json` and upload it as workflow artifact `spec-readiness-report`.
    - Optional release-candidate evidence gate: set `workflow_dispatch` input `run_release_candidate_evidence_pack=true` to install pinned Rojo, run `tools/run_release_candidate_evidence_pack_task.ps1`, and upload `release-candidate-evidence` artifact (reliability + parity + readiness outputs).
    - Optional release-candidate distribution mode: set `workflow_dispatch` input `release_candidate_include_distribution_evidence=true` (with the evidence gate) to include packaging + manifest/checksums + published Day-0 validation before readiness.
  - Manual release packaging workflow: `.github/workflows/release-packaging.yml` (`workflow_dispatch` only; packages server and plugin artifacts for Windows/Linux/macOS, installs pinned Rojo `7.7.0-rc.1`, enforces installable plugin build, validates manifest/artifact naming, runs packaged + published Day-0 validations, and generates/verifies release checksums)

## Documentation index

- [docs/day0_onboarding.md](docs/day0_onboarding.md) — minimum setup/run actions for brand-new users
- [docs/mcp_studio_unified_project_plan.md](docs/mcp_studio_unified_project_plan.md) — project plan, phases, risks, and success gates
- [docs/mcp_contract_v1.md](docs/mcp_contract_v1.md) — working MCP contract and tool payloads
- [docs/proposed_structure.md](docs/proposed_structure.md) — repository/language structure decisions
- [docs/implementation_status.md](docs/implementation_status.md) — current implementation snapshot and remaining work

## Quick start

Run from workspace root:

```powershell
$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
& $cargoExe test
& $cargoExe run -p mcp-server
```

Server endpoints:

- `GET http://127.0.0.1:44877/health`
- `POST http://127.0.0.1:44877/mcp`
- `POST http://127.0.0.1:44877/api/rojo`
- `GET http://127.0.0.1:44877/api/read/{instanceId}`
- `GET http://127.0.0.1:44877/api/subscribe/{sessionId}/{cursor}`

## Smoke test script

Run the end-to-end MCP smoke test after starting the server:

```powershell
$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
& $cargoExe run -p mcp-server
```

In another terminal:

```powershell
Set-Location D:\roblox
.\tools\mcp_smoke_test.ps1
```

Optional custom endpoint:

```powershell
.\tools\mcp_smoke_test.ps1 -Endpoint "http://127.0.0.1:44877/mcp" -ProjectPath "src"
```

One-click task runner (starts server, executes smoke test, stops server):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_smoke_task.ps1
```

Live file-authoring verification script (expects server running):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/live_file_check.ps1
```

Rojo compatibility endpoint check (expects server running):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/rojo_compat_check.ps1
```

Rojo compatibility test (start+run+stop in one command):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_compat_task.ps1
```

Rojo changefeed edge-case test (start+run+stop in one command):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_changefeed_task.ps1
```

Conflict race contract test (start+run+stop in one command):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_conflict_race_task.ps1
```

Reconnect/replay contract test (start+run+stop in one command):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_reconnect_replay_task.ps1
```

Invalid-session contract test (start+run+stop in one command):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_invalid_session_task.ps1
```

Rojo parity diff (start MCP + live Rojo serve, compare, write report):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_parity_diff_task.ps1
```

The parity report is written to `tools/parity_diff_report.json`.
Optional: pass `-MutationFilePath <workspace-relative-file>` to exercise a reversible file edit and compare post-mutation subscribe deltas when both servers expose subscribe.

Rojo parity suite (run all fixtures, fail on any diff):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_parity_suite_task.ps1
```

The suite now runs static parity plus a reversible mutation check per fixture (currently default, complex, service-heavy, nested-modules, mixed-services, lifecycle-ops, ui-container, serverstorage, presentation-services, starterpack, teams-spawns, startercharacter, and metadata-churn fixtures).
Optional: pass `-Categories <comma-separated-categories>` (for example `-Categories baseline,structure`) to run a targeted subset of enabled fixture categories.
Optional: pass `-Fixtures <comma-separated-fixture-names>` (for example `-Fixtures baseline-default,complex-services-shared`) to run specific enabled fixtures by manifest `name`.
Optional: pass `-DryRun` to print selected fixtures and categories without starting MCP or Rojo servers.

Rojo parity release gate (suite + strict summary checks):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_parity_release_gate_task.ps1
```

Optional: pass `-Categories <comma-separated-categories>` to apply category filtering to both suite execution and strict summary checks.
Optional: pass `-Fixtures <comma-separated-fixture-names>` to target specific manifest fixture names in release-gate execution.
Optional: pass `-DryRun` to preview selected fixtures without executing parity checks or strict summary validation.

Release packaging (manual, distribution prep):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/package_release_artifacts.ps1
```

This writes distribution artifacts into `dist/release` (`mcp-server-<platform>.zip`, versioned `mcp-studio-plugin-source-<version>.zip`, and `release_manifest.json`). If Rojo is installed, it also writes installable `mcp-studio-plugin-<version>.rbxm`.
End-user/local validation paths do not require Rojo; Rojo is enforced in the manual release workflow.

Release manifest/artifact validation (manual):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/validate_release_manifest.ps1
```

Optional: pass `-RequireInstallable` to fail unless installable plugin `.rbxm` is present.

Release checksum generation/verification (manual):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/generate_release_checksums.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/generate_release_checksums.ps1 -Verify
```

Day-0 packaged-artifact validation (manual, distribution evidence):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_day0_packaged_validation_task.ps1
```

This validates packaged artifacts by launching the server from `dist/release/mcp-server-<platform>.zip`, running the MCP smoke flow against that packaged binary, and verifying expected plugin archive files.

Day-0 published-artifact bundle validation (manual, strict release-readiness check):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_day0_published_artifact_validation_task.ps1
```

Optional: pass `-RequireInstallable` to fail unless installable plugin `.rbxm` is present.

Integration reliability evidence suite (manual):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_integration_reliability_suite_task.ps1 -ReconnectIterations 5 -ConflictIterations 3 -MixedIterations 3
```

This writes reliability evidence to `tools/integration_reliability_report.json`.

Release-candidate evidence pack (manual, one command):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_release_candidate_evidence_pack_task.ps1
```

This runs integration reliability evidence, Rojo parity fixture suite + strict summary checks, and then writes `tools/spec_readiness_report.json`.
Optional: pass `-IncludeDistributionEvidence` to generate full Milestone 3 evidence (release packaging with required installable plugin, manifest/checksum validation, and published Day-0 validation) before readiness evaluation.
Optional: pass `-SkipParitySuite` to reuse existing parity reports (no Rojo execution), `-Categories`/`-Fixtures` to target parity scope, and `-FailIfNotPass` to fail unless all milestone gates are PASS.
If `rojo` is not on PATH, the runner also attempts to auto-discover a winget-installed Rojo binary under `%LOCALAPPDATA%\Microsoft\WinGet\Packages`.

Policy contract test (start+run+stop in one command):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_policy_task.ps1
```

Protocol contract test (start+run+stop in one command, Windows):

```powershell
Set-Location D:\roblox
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_protocol_task.ps1
```

### Windows Python note

On some Windows setups, `python` resolves to the Microsoft Store alias (`...WindowsApps\python.exe`) and fails even after Python is installed.

- `tools/run_mcp_protocol_task.ps1` avoids this by probing common Python install locations directly.
- If you prefer command-line `python` to work globally, disable the App Execution Alias for Python in:
  - Settings → Apps → Advanced app settings → App execution aliases.

## Current implementation status

Current active target: **production-like live authoring from VS Code files**.

Implemented now:

- MCP lifecycle baseline (`initialize`, `notifications/initialized`)
- Tool surface: `roblox.openSession`, `roblox.readTree`, `roblox.subscribeChanges`, `roblox.applyPatch`, `roblox.closeSession`
- Filesystem-backed snapshot + diff flow for `.lua` source files under session source root
- Read operations refresh from source before returning snapshot data (keeps read responses current)
- `subscribeChanges` emits updates when VS Code/disk files change
- `setProperty(Source)` writes Source updates back to mapped files
- Adapter now attempts Rojo (`librojo`) snapshot loading when a `.project.json` file is provided, with filesystem fallback for `src` workflows
- Parity-layer increment: Rojo-derived IDs are metadata-aware/stable and script path resolution prefers real source files (`.lua`/`.luau`)
- Structural patch ops (`addInstance`, `removeInstance`) are rejected for file-backed sessions to avoid divergence from source-of-truth files
- For file-backed instances, only `setProperty(Source)` is accepted; `setName` and other property writes are rejected as non-durable
- Server now advertises mutation policy metadata (`supportsStructuralOps`, `fileBackedMutationPolicy`) in open/read/subscribe payloads
- Studio plugin consumes policy metadata and blocks unsupported local edits before sending patches
- Server now emits explicit lifecycle error codes (e.g., `SESSION_NOT_FOUND`) in JSON-RPC error data for stable client handling
- Conflict details now emit explicit reason codes (`CONFLICT_WRITE_STALE_CURSOR`, `UNSUPPORTED_FILE_BACKED_MUTATION`, `SOURCE_WRITE_FAILED`, `SOURCE_PATH_MISSING`) for stable client branching
- Studio plugin now auto-recovers by opening a fresh session when server reports a missing/expired session (code-first, message fallback)
- Rojo compatibility endpoints implemented (`/api/rojo`, `/api/read`, `/api/subscribe`)
- Idempotent patch handling (`patchId`)
- Base cursor conflict checks and structured conflict details
- Plugin bootstrap + polling + local edit patching (`Name`, `Source`)
- Remote change apply into Studio instances (added/updated/removed)
- Conflict rollback and conflict UI indicators
- Manual "Re-read selected" conflict recovery action

Example initialize request:

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
    "clientInfo": { "name": "manual-test", "version": "0.1.0" }
  }
}
```

## Next implementation steps

1. Expand current `librojo` integration from snapshot parity to full mutation/changefeed parity with Rojo serve session internals.
2. Add Rojo payload parity checks against live Rojo serve behavior.
3. Continue hardening reconnect/replay windows and conflict merge policy beyond baseline reliability gates.
4. Finalize installable Studio plugin packaging/versioning and complete Day-0 validation from packaged artifacts.
