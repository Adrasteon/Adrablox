param(
    [string]$Categories = ""
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot

Push-Location $workspace
try {
    $suiteArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($Categories)) {
        $suiteArgs += '-Categories'
        $suiteArgs += $Categories
    }

    Write-Host "Running Rojo parity fixture suite..."
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_parity_suite_task.ps1 @suiteArgs

    $summaryArgs = @('-FailIfNoReports', '-FailIfDiffs')
    if (-not [string]::IsNullOrWhiteSpace($Categories)) {
        $summaryArgs += '-FailCategories'
        $summaryArgs += $Categories
    }

    Write-Host "Running strict parity summary checks..."
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/summarize_parity_reports.ps1 @summaryArgs

    Write-Host "Rojo parity release gate completed successfully."
}
finally {
    Pop-Location
}
