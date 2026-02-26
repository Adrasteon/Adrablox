# Day-0 Onboarding (Minimum Setup)

This is the absolute minimum path for a new user with:

- VS Code installed and signed in
- Roblox Studio installed and signed in
- no extensions/plugins/MCP servers configured yet

## Goal

Get from zero to a working local MCP session with the fewest actions possible.

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

Release packaging automation now exists for server + plugin source artifacts, but plugin install packaging is not finalized yet; one temporary manual step is still required.

1. Start server from VS Code task:
   - `Day-0: 2) Run Server (manual Studio session)`
2. Install/load the Studio plugin from the local plugin source (dev workflow).
3. In plugin UI, connect to:
   - `http://127.0.0.1:44877/mcp`
4. Edit a mapped script in `src` from VS Code.
5. Confirm the change appears in Studio and no conflict is reported.

## Simplest Future UX (Target)

After installable plugin packaging and Day-0 validation are finalized, the target flow is:

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
- Current packaged outputs: `dist/release/mcp-server-<platform>.zip`, `dist/release/mcp-studio-plugin-source.zip`, `dist/release/release_manifest.json`
- Manual packaged-validation command: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_day0_packaged_validation_task.ps1`
- VS Code packaged-validation task: `Day-0: 3) Validate Packaged Artifacts (start+run+stop)`
