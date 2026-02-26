$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot

Push-Location $workspace
try {
    Write-Host "Running Rojo parity fixture suite..."
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_parity_suite_task.ps1

    Write-Host "Running strict parity summary checks..."
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/summarize_parity_reports.ps1 -FailIfNoReports -FailIfDiffs

    Write-Host "Rojo parity release gate completed successfully."
}
finally {
    Pop-Location
}
