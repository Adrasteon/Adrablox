param(
    [string]$ReportPath = "tools/spec_readiness_report.json",
    [switch]$FailIfNotPass
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$reportFullPath = if ([System.IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $workspace $ReportPath }

if (-not (Test-Path $reportFullPath)) {
    throw "Spec readiness report not found: $reportFullPath"
}

$report = Get-Content -Raw -Path $reportFullPath | ConvertFrom-Json

$m1 = [string]$report.milestones.milestone1_parity.status
$m2 = [string]$report.milestones.milestone2_reliability.status
$m3 = [string]$report.milestones.milestone3_distribution.status
$overall = [string]$report.specComplete

Write-Output ("Spec readiness summary: milestone1={0} milestone2={1} milestone3={2} specComplete={3}" -f $m1, $m2, $m3, $overall)

if ($env:GITHUB_STEP_SUMMARY) {
    $lines = @(
        "## Spec Readiness Summary",
        "",
        "| Gate | Status |",
        "| --- | --- |",
        "| Milestone 1 (Parity) | $m1 |",
        "| Milestone 2 (Reliability) | $m2 |",
        "| Milestone 3 (Distribution) | $m3 |",
        "| Overall Spec Complete | $overall |"
    )
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value ($lines -join [Environment]::NewLine)
}

if ($FailIfNotPass -and $overall -ne "PASS") {
    throw "Spec readiness is not PASS (specComplete=$overall)."
}

