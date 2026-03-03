# Day-0 Onboarding (Minimum Setup)

This is the absolute minimum path for a new user with:

- VS Code installed and signed in
- Roblox Studio installed and signed in
- no extensions/plugins/MCP servers configured yet

## Goal

Get from zero to a working local MCP session with the fewest actions possible.

## First-Use Download and Deploy (Plain English)

If you are starting from a release download, open the latest dev release page and click **Assets**. Download the server zip for your computer (most people on Windows should pick `mcp-server-windows.zip`) and the plugin file (`mcp-studio-plugin-<version>.rbxm`). Unzip the server zip to a normal folder like `Documents\Adrablox`, then run the `mcp-server` program inside and leave that window open. In Roblox Studio, import the `.rbxm` plugin file, open the plugin, and connect to `http://127.0.0.1:44877/mcp`.

## Required One-Time Setup

1. Install Rust (`rustup`), which provides `cargo`.
2. Keep Visual Studio Build Tools C++ workload installed on Windows.
3. Clone this repository and open it in VS Code.
4. In Roblox Studio, enable **Allow HTTP Requests**.

## Fastest Validation (No Plugin Yet)

From VS Code, run task:

- `Day-0: 1) Smoke Test (start+run+stop)`

If this passes, the server and protocol flow are functional on your machine.

## Minimum Live Authoring Path (Current State)

Release packaging automation is in place for server + plugin source + installable plugin artifacts, with strict validation flows available.

Project config default (current):

- Preferred session entry is `adrablox.project.json`.
- Native-manifest mode resolves to compatibility project path (`default.project.json`) when present.

1. Start server from VS Code task:
   - `Day-0: 2) Run Server (manual Studio session)`
2. Install/load the Studio plugin from the local plugin source (dev workflow).
3. In plugin UI, connect to:
   - `http://127.0.0.1:44877/mcp`
4. Edit a mapped script under the project mapping (for baseline repo: `src`, `src/workspace`, `src/shared`, `src/client`) from VS Code.
5. Confirm the change appears in Studio and no conflict is reported.

## Simplest Future UX (Target)

Current target flow:

1. Install extension/plugin bundle.
2. Click **Start MCP Server**.
3. Click **Connect** in Studio plugin.
4. Edit in VS Code and observe live Studio sync.

## If Something Fails

- Re-run `Day-0: 1) Smoke Test (start+run+stop)` first.
- Confirm Studio **Allow HTTP Requests** is enabled.
- Confirm plugin endpoint is exactly `http://127.0.0.1:44877/mcp`.

## Distribution Baseline (Current)

- Manual packaging command: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/package_release_artifacts.ps1`
- Current packaged outputs: `dist/release/mcp-server-<platform>.zip`, `dist/release/mcp-studio-plugin-source-<version>.zip`, `dist/release/release_manifest.json`
- Optional compatibility server output: `dist/release/mcp-server-<platform>-rojo-compat.zip` (when `-IncludeRojoCompatServer` is supplied)
- Optional installable output (when `rojo` CLI is present): `dist/release/mcp-studio-plugin-<version>.rbxm`
- Manual packaged-validation command: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_day0_packaged_validation_task.ps1`
- VS Code packaged-validation task: `Day-0: 3) Validate Packaged Artifacts (start+run+stop)`
- Optional compatibility archive validation: append `-UseRojoCompatServer` to Day-0 packaged/published validation commands when intentionally testing `serverArchiveRojoCompat`.

## CI Artifact Naming (Manual Dispatch)

| Gate/input path | Artifact name pattern |
| --- | --- |
| `run_integration_reliability_suite=true` | `integration-reliability-report-it<iterations>` |
| `run_spec_readiness_report=true` only | `spec-readiness-report-standalone` |
| `run_spec_readiness_report=true` with `run_release_candidate_evidence_pack=true` | `spec-readiness-report-with-pack` |
| `run_release_candidate_evidence_pack=true` + `release_candidate_include_distribution_evidence=false` | `release-candidate-evidence-it<iterations>-dist-off` |
| `run_release_candidate_evidence_pack=true` + `release_candidate_include_distribution_evidence=true` | `release-candidate-evidence-it<iterations>-dist-on` |
| `run_rojo_parity_diff=true` | `rojo-parity-reports` |
