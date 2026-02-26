param(
    [string]$ReportsGlob = "tools/parity_diff_report*.json",
    [string]$SummaryPath = "tools/parity_diff_summary.json",
    [switch]$FailIfDiffs,
    [switch]$FailIfNoReports
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$reportSearchPath = Join-Path $workspace $ReportsGlob
$summaryFullPath = Join-Path $workspace $SummaryPath
$summaryDir = Split-Path -Parent $summaryFullPath

if (-not (Test-Path $summaryDir)) {
    New-Item -ItemType Directory -Path $summaryDir -Force | Out-Null
}

$reports = @(Get-ChildItem -Path $reportSearchPath -File -ErrorAction SilentlyContinue | Sort-Object Name)

$reportEntries = @()
$totalDiffCount = 0

foreach ($reportFile in $reports) {
    $raw = Get-Content -Raw -Path $reportFile.FullName
    $json = $raw | ConvertFrom-Json

    $diffCount = 0
    if ($json.PSObject.Properties["diffCount"]) {
        $diffCount = [int]$json.diffCount
    }

    $entry = [pscustomobject]@{
        reportFile = ("tools/{0}" -f $reportFile.Name)
        projectPath = [string]$json.projectPath
        timestampUtc = [string]$json.timestampUtc
        diffCount = $diffCount
        hasDiffs = ($diffCount -gt 0)
    }

    $reportEntries += $entry
    $totalDiffCount += $diffCount
}

$summary = [pscustomobject]@{
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    reportGlob = $ReportsGlob
    reportCount = $reportEntries.Count
    totalDiffCount = $totalDiffCount
    allPass = (($reportEntries.Count -gt 0) -and ($totalDiffCount -eq 0))
    reports = $reportEntries
}

$summary | ConvertTo-Json -Depth 20 | Set-Content -Path $summaryFullPath

Write-Output ("summaryPath={0}" -f $summaryFullPath)
Write-Output ("reportCount={0}" -f $summary.reportCount)
Write-Output ("totalDiffCount={0}" -f $summary.totalDiffCount)

if ($summary.reportCount -eq 0) {
    Write-Output "No parity reports found for summary generation."
}
elseif ($summary.totalDiffCount -eq 0) {
    Write-Output "Parity summary: all reports are diff-free."
}
else {
    Write-Output "Parity summary: one or more reports contain diffs."
}

if ($FailIfNoReports -and $summary.reportCount -eq 0) {
    throw "Parity summary strict mode failed: no parity reports were found."
}

if ($FailIfDiffs -and $summary.totalDiffCount -gt 0) {
    throw "Parity summary strict mode failed: totalDiffCount=$($summary.totalDiffCount)."
}
