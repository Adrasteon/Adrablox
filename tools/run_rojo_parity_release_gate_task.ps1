param(
    [string]$Categories = "",
    [string]$Fixtures = "",
    [switch]$DryRun
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
    if (-not [string]::IsNullOrWhiteSpace($Fixtures)) {
        $suiteArgs += '-Fixtures'
        $suiteArgs += $Fixtures
    }
    if ($DryRun) {
        $suiteArgs += '-DryRun'
    }

    Write-Output "Running Rojo parity fixture suite..."
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_rojo_parity_suite_task.ps1 @suiteArgs

    if ($DryRun) {
        Write-Output "Dry-run mode enabled; skipping strict parity summary checks."
        Write-Output "Rojo parity release gate dry-run completed successfully."
        return
    }

    $summaryArgs = @('-FailIfNoReports', '-FailIfDiffs')
    if (-not [string]::IsNullOrWhiteSpace($Categories)) {
        $summaryArgs += '-FailCategories'
        $summaryArgs += $Categories
    }

    Write-Output "Running strict parity summary checks..."
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/summarize_parity_reports.ps1 @summaryArgs

    Write-Output "Rojo parity release gate completed successfully."
}
finally {
    Pop-Location
}

