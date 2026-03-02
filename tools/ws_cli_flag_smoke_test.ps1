param(
    [string]$NodeExe = "node"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cliPath = Join-Path $repoRoot "studio_action_scripts/cli/index.js"

if (-not (Test-Path $cliPath)) {
    throw "CLI entrypoint not found: $cliPath"
}

$output = & $NodeExe $cliPath ws-tail --dry-run --since 42 --limit 10 --auth-token test-token
if ($LASTEXITCODE -ne 0) {
    throw "ws-tail dry-run exited with code $LASTEXITCODE"
}

$parsed = $output | ConvertFrom-Json

if ($parsed.command -ne "ws-tail") {
    throw "Unexpected command in dry-run output"
}

if ($parsed.since -ne 42) {
    throw "Expected since=42 in dry-run output"
}

if ($parsed.limit -ne 10) {
    throw "Expected limit=10 in dry-run output"
}

if (-not $parsed.hasAuthToken) {
    throw "Expected hasAuthToken=true in dry-run output"
}

Write-Host "ws_cli_flag_smoke_test: PASS"
