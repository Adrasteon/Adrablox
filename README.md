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
  - `tools/mcp_protocol_contract_test.py`: cross-platform protocol contract checks (capabilities + session metadata)
  - `tools/run_mcp_protocol_task.ps1`: start server, run protocol contract test, stop server (Windows)
  - `tools/run_mcp_protocol_task.sh`: start server, run protocol contract test, stop server (Linux/macOS)
  - `tools/run_mcp_server.ps1`: run server for manual Studio testing
  - VS Code tasks: `MCP: Run Server`, `MCP: Smoke Test (start+run+stop)`, `MCP: Policy Contract Test (start+run+stop)`, `MCP: Rojo Compat Test (start+run+stop)`, `MCP: Protocol Contract Test (start+run+stop)`
  - CI workflow: `.github/workflows/ci.yml` (Windows full contract checks + Linux/macOS protocol contract checks)

## Documentation index

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
- `subscribeChanges` emits updates when VS Code/disk files change
- `setProperty(Source)` writes Source updates back to mapped files
- Adapter now attempts Rojo (`librojo`) snapshot loading when a `.project.json` file is provided, with filesystem fallback for `src` workflows
- Parity-layer increment: Rojo-derived IDs are metadata-aware/stable and script path resolution prefers real source files (`.lua`/`.luau`)
- Structural patch ops (`addInstance`, `removeInstance`) are rejected for file-backed sessions to avoid divergence from source-of-truth files
- For file-backed instances, only `setProperty(Source)` is accepted; `setName` and other property writes are rejected as non-durable
- Server now advertises mutation policy metadata (`supportsStructuralOps`, `fileBackedMutationPolicy`) in open/read/subscribe payloads
- Studio plugin consumes policy metadata and blocks unsupported local edits before sending patches
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
3. Harden reconnect/replay windows and conflict merge policy.
4. Add Studio plugin packaging flow and integration testing pipeline.
