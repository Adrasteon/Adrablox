# Adrablox

Roblox Studio plugin + MCP server workspace for click-first VS Code workflows and file-backed live authoring.

## At a glance

- MCP server: Rust (`cmd/mcp-server`)
- Studio plugin: Luau (`plugin/mcp-studio`)
- VS Code control extension: TypeScript (`tools/vscode-adrablox-control`)
- Default local endpoint: `http://127.0.0.1:44877/mcp`
- Transport model: HTTP JSON-RPC authoritative, with hybrid WS support and replay hardening work in progress

## Quick links

- Releases: https://github.com/Adrasteon/Adrablox/releases
- Day-0 setup: [docs/day0_onboarding.md](docs/day0_onboarding.md)
- Implementation snapshot: [docs/implementation_status.md](docs/implementation_status.md)
- Transport plan (HTTP + WS): [mcp_transport_plan.md](mcp_transport_plan.md)
- VS Code UX MVP: [docs/vscode_ux_extension_mvp.md](docs/vscode_ux_extension_mvp.md)
- VS Code UX roadmap (Phase 4+5): [docs/vscode_ux_extension_phase4_5_plan.md](docs/vscode_ux_extension_phase4_5_plan.md)

---

## 1) End-user quick start (from release artifacts)

1. Open **Releases** and download:
   - server zip for your OS (Windows users: `mcp-server-windows.zip`)
   - plugin artifact (`.rbxm`/`.rbxmx` depending on release)
2. Extract the server zip to a normal folder (for example `Documents\Adrablox`).
3. Start server and keep it running:
   - Windows packaged runner: `run-mcp-server.bat` (or `run-mcp-server.ps1`)
4. In Roblox Studio, import/open the plugin and connect to:
   - `http://127.0.0.1:44877/mcp`
5. Confirm server health:
   - `GET http://127.0.0.1:44877/health`

If setup fails, use [docs/day0_onboarding.md](docs/day0_onboarding.md).

---

## 2) Contributor quick start (repo clone)

### Prerequisites

- Rust toolchain (`rustup`, `cargo`)
- Roblox Studio (with **Allow HTTP Requests** enabled)
- PowerShell (Windows) for task scripts
- Node.js (for `studio_action_scripts/cli` utilities)
- Optional: Rojo CLI (needed for installable plugin packaging/parity workflows)

### Fast validation path

From repo root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_smoke_task.ps1
```

This starts the server, runs smoke checks, and stops the server.

### Run server for manual Studio testing

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_server.ps1
```

Wait for health before manual MCP calls:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/wait_for_mcp_health.ps1
```

Native manifest migration:
- Preferred project config is `adrablox.project.json`.
- Local run scripts set `MCP_ENABLE_NATIVE_PROJECT_MANIFEST=true` and `MCP_NATIVE_PROJECT_MANIFEST_PATH=adrablox.project.json`.
- Adapter selection supports `MCP_PROJECT_ADAPTER_MODE=auto|native|rojo`.
- Explicit `rojo` mode is deprecated-gated and requires both `MCP_ENABLE_ROJO_ADAPTER_MODE=true` and a `rojo-compat` build; without `rojo-compat`, the env flag is ignored and selection stays native.
- `auto` mode picks `native` by default; it only selects `rojo` when `MCP_ENABLE_ROJO_ADAPTER_MODE=true` and native manifest mode is disabled.
- Legacy compatibility HTTP routes are opt-in via `MCP_ENABLE_LEGACY_ROJO_ROUTES=true` (default is disabled).
- Rojo compatibility is now compile-time gated behind cargo feature `rojo-compat` (default build is native-only; enable via `cargo run -p mcp-server --features rojo-compat`).
- `openSession` resolves through native manifest mapping defined by `session.defaultProjectPath` / `compatibility.rojoProjectPath`.
- Native manifest fallback order is: `session.defaultProjectPath` → `compatibility.rojoProjectPath` → `default.project.json`.

---

## 3) Core endpoints

- `GET /health`
- `POST /mcp` (JSON-RPC; `tools/list`, `tools/call`)
- `GET /api/read/{instanceId}` (legacy; requires `rojo-compat` build + `MCP_ENABLE_LEGACY_ROJO_ROUTES=true`)
- `GET /api/subscribe/{sessionId}/{cursor}` (legacy; requires `rojo-compat` build + `MCP_ENABLE_LEGACY_ROJO_ROUTES=true`)
- `POST /api/rojo` (legacy; requires `rojo-compat` build + `MCP_ENABLE_LEGACY_ROJO_ROUTES=true`)
- `ws://127.0.0.1:44877/mcp-stream` (push stream)

Notes:
- Tool responses may include `structuredContent` wrappers.
- Import progress can be consumed via stream and/or polled by tool (`roblox.importProgress`) depending on client capability.

Current tool surface:
- `roblox.openSession`
- `roblox.readTree`
- `roblox.subscribeChanges`
- `roblox.applyPatch`
- `roblox.importProgress`
- `roblox.closeSession`
- `roblox.exportSnapshot`
- `roblox.importSnapshot`

---

## 4) Common commands

### Server + protocol sanity

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_smoke_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_policy_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_protocol_task.ps1
```

Linux/macOS protocol task:

```bash
bash tools/run_mcp_protocol_task.sh
```

### Reliability and integration suites

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_integration_roundtrip_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_integration_reconnect_loop_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_integration_conflict_recovery_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_integration_mixed_resilience_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mcp_integration_reliability_suite_task.ps1
```

### Rojo compatibility/parity

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_compat_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_changefeed_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_parity_diff_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_parity_suite_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_parity_release_gate_task.ps1
```

### Packaging and release evidence

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/package_release_artifacts.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/package_release_artifacts.ps1 -IncludeRojoCompatServer
powershell -NoProfile -ExecutionPolicy Bypass -File tools/validate_release_manifest.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/generate_release_checksums.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_day0_packaged_validation_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_day0_published_artifact_validation_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_release_candidate_evidence_pack_task.ps1
```

Mission-critical local strict gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_mission_critical_local_gate_task.ps1
```

---

## 5) VS Code extension status

Extension path: `tools/vscode-adrablox-control/`

Implemented:
- Phase 1–3 complete (status/actions/tree/task output/full health/remediation/rerun)
- Phase 4 foundation actioned: direct MCP RPC client (`rpc-first`) with script fallback
- Transport settings exposed in extension config:
  - `adrablox.transport.mode`
  - `adrablox.transport.enableFallback`
  - `adrablox.transport.endpoint`
  - `adrablox.session.projectPath`

Roadmap details: [docs/vscode_ux_extension_phase4_5_plan.md](docs/vscode_ux_extension_phase4_5_plan.md)

---

## 6) Repository layout

```text
cmd/mcp-server/                 Rust MCP server
crates/mcp-core/                Protocol/core types
crates/rojo-adapter/            Rojo/file-backed adapter boundary
plugin/mcp-studio/              Roblox Studio plugin source
studio_action_scripts/          Action scripts + Node CLI helper
tools/                          Validation, parity, packaging, release gates
docs/                           Plans, contracts, onboarding, status
```

---

## 7) CI overview

Main workflow: `.github/workflows/ci.yml`
- Windows: expanded contract/integration checks
- Linux/macOS: protocol-focused checks
- Optional manual gates (`workflow_dispatch`) for parity, reliability, WS transport, and release-candidate evidence packs

WS-specific workflow: `.github/workflows/ws_integration.yml`
- replay + stream compatibility checks

Release packaging workflow: `.github/workflows/release-packaging.yml`
- manual dispatch packaging/validation flow

---

## 8) Troubleshooting

- Verify endpoint is exactly `http://127.0.0.1:44877/mcp`.
- Confirm Roblox Studio **Allow HTTP Requests** is enabled.
- Run smoke task first before deeper debugging:
  - `tools/run_mcp_smoke_task.ps1`
- If Python command fails on Windows aliasing, use:
  - `tools/run_mcp_protocol_task.ps1` (it probes common Python installs)
- For release/readiness diagnostics, run:
  - `tools/run_spec_readiness_report.ps1`

---

## 9) Additional documentation

- [docs/day0_onboarding.md](docs/day0_onboarding.md)
- [docs/mcp_contract_v1.md](docs/mcp_contract_v1.md)
- [docs/studio_transport_matrix.md](docs/studio_transport_matrix.md)
- [docs/ws_protocol.md](docs/ws_protocol.md)
- [docs/ws_transport_migration_guide.md](docs/ws_transport_migration_guide.md)
- [docs/mcp_studio_unified_project_plan.md](docs/mcp_studio_unified_project_plan.md)
- [docs/implementation_status.md](docs/implementation_status.md)

If you want to contribute, start with smoke + protocol tasks, then open a focused PR with one subsystem change at a time.
