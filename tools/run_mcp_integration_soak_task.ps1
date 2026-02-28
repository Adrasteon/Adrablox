param(
    [int]$Iterations = 10
)

$ErrorActionPreference = "Stop"

if ($Iterations -lt 1) {
    throw "Iterations must be >= 1"
}

Write-Output "Running integration soak with iterations=$Iterations..."
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run_mcp_integration_reconnect_loop_task.ps1') -Iterations $Iterations
Write-Output "Integration soak task completed successfully."

