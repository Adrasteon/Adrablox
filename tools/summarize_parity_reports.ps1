param(
    [string]$ReportsGlob = "tools/parity_diff_report*.json",
    [string]$SummaryPath = "tools/parity_diff_summary.json",
    [switch]$FailIfDiffs,
    [switch]$FailIfNoReports,
    [string]$FailCategories = ""
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
$categoryStats = @{}

foreach ($reportFile in $reports) {
    $raw = Get-Content -Raw -Path $reportFile.FullName
    $json = $raw | ConvertFrom-Json

    $diffCount = 0
    if ($json.PSObject.Properties["diffCount"]) {
        $diffCount = [int]$json.diffCount
    }

    $fixtureName = ""
    $fixtureCategory = ""
    if ($json.PSObject.Properties["fixture"] -and $json.fixture) {
        if ($json.fixture.PSObject.Properties["name"]) {
            $fixtureName = [string]$json.fixture.name
        }
        if ($json.fixture.PSObject.Properties["category"]) {
            $fixtureCategory = [string]$json.fixture.category
        }
    }

    if ([string]::IsNullOrWhiteSpace($fixtureName)) {
        $fixtureName = [string]$json.projectPath
    }
    if ([string]::IsNullOrWhiteSpace($fixtureCategory)) {
        $fixtureCategory = "uncategorized"
    }

    $entry = [pscustomobject]@{
        reportFile = ("tools/{0}" -f $reportFile.Name)
        fixtureName = $fixtureName
        fixtureCategory = $fixtureCategory
        projectPath = [string]$json.projectPath
        timestampUtc = [string]$json.timestampUtc
        diffCount = $diffCount
        hasDiffs = ($diffCount -gt 0)
    }

    if (-not $categoryStats.ContainsKey($fixtureCategory)) {
        $categoryStats[$fixtureCategory] = [pscustomobject]@{
            fixtureCount = 0
            totalDiffCount = 0
            failingFixtureCount = 0
        }
    }

    $categoryStats[$fixtureCategory].fixtureCount += 1
    $categoryStats[$fixtureCategory].totalDiffCount += $diffCount
    if ($diffCount -gt 0) {
        $categoryStats[$fixtureCategory].failingFixtureCount += 1
    }

    $reportEntries += $entry
    $totalDiffCount += $diffCount
}

$categoryBreakdown = @()
foreach ($category in ($categoryStats.Keys | Sort-Object)) {
    $categoryBreakdown += [pscustomobject]@{
        category = $category
        fixtureCount = [int]$categoryStats[$category].fixtureCount
        totalDiffCount = [int]$categoryStats[$category].totalDiffCount
        failingFixtureCount = [int]$categoryStats[$category].failingFixtureCount
    }
}

$summary = [pscustomobject]@{
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    reportGlob = $ReportsGlob
    reportCount = $reportEntries.Count
    totalDiffCount = $totalDiffCount
    allPass = (($reportEntries.Count -gt 0) -and ($totalDiffCount -eq 0))
    categoryBreakdown = $categoryBreakdown
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

if (-not [string]::IsNullOrWhiteSpace($FailCategories)) {
    $requestedCategories = @($FailCategories.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $availableCategories = @($summary.categoryBreakdown | ForEach-Object { [string]$_.category })

    foreach ($category in $requestedCategories) {
        if ($availableCategories -notcontains $category) {
            throw "Parity summary category strict mode failed: category '$category' not found in summary."
        }
    }

    $failingSelected = @($summary.categoryBreakdown | Where-Object { $requestedCategories -contains [string]$_.category -and [int]$_.totalDiffCount -gt 0 })
    if ($failingSelected.Count -gt 0) {
        $parts = @($failingSelected | ForEach-Object { "{0}:{1}" -f ([string]$_.category), ([int]$_.totalDiffCount) })
        throw "Parity summary category strict mode failed: selected categories have diffs ($($parts -join ','))."
    }
}
