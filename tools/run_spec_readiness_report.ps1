param(
    [string]$ParitySummaryPath = "tools/parity_diff_summary.json",
    [string]$ReliabilityReportPath = "tools/integration_reliability_report.json",
    [string]$ReleaseManifestPath = "dist/release/release_manifest.json",
    [string]$ReleaseChecksumsPath = "dist/release/release_checksums.txt",
    [string]$OutputPath = "tools/spec_readiness_report.json",
    [switch]$FailIfNotPass
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot

function Resolve-WorkspacePath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $workspace $Path
}

function New-GateResult {
    param(
        [string]$status,
        [string]$reason,
        $details
    )

    return [pscustomobject]@{
        status = $status
        reason = $reason
        details = $details
    }
}

function Read-JsonOrNull {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $null
    }

    $raw = Get-Content -Raw -Path $Path
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

$paritySummaryFull = Resolve-WorkspacePath -Path $ParitySummaryPath
$reliabilityReportFull = Resolve-WorkspacePath -Path $ReliabilityReportPath
$releaseManifestFull = Resolve-WorkspacePath -Path $ReleaseManifestPath
$releaseChecksumsFull = Resolve-WorkspacePath -Path $ReleaseChecksumsPath
$outputFull = Resolve-WorkspacePath -Path $OutputPath

$paritySummary = Read-JsonOrNull -Path $paritySummaryFull
$reliabilityReport = Read-JsonOrNull -Path $reliabilityReportFull
$releaseManifest = Read-JsonOrNull -Path $releaseManifestFull

$milestone1 = $null
if ($null -eq $paritySummary) {
    $milestone1 = New-GateResult -status "UNKNOWN" -reason "Parity summary missing" -details @{
        expectedPath = $ParitySummaryPath
    }
}
else {
    $reportCount = [int]$paritySummary.reportCount
    $totalDiffCount = [int]$paritySummary.totalDiffCount
    if ($reportCount -gt 0 -and $totalDiffCount -eq 0) {
        $milestone1 = New-GateResult -status "PASS" -reason "Parity summary diff-free" -details @{
            reportCount = $reportCount
            totalDiffCount = $totalDiffCount
        }
    }
    else {
        $milestone1 = New-GateResult -status "FAIL" -reason "Parity summary has diffs or no reports" -details @{
            reportCount = $reportCount
            totalDiffCount = $totalDiffCount
        }
    }
}

$milestone2 = $null
if ($null -eq $reliabilityReport) {
    $milestone2 = New-GateResult -status "UNKNOWN" -reason "Integration reliability report missing" -details @{
        expectedPath = $ReliabilityReportPath
    }
}
else {
    $allPassed = [bool]$reliabilityReport.allPassed
    if ($allPassed) {
        $milestone2 = New-GateResult -status "PASS" -reason "Reliability suite passed" -details @{
            passedCount = [int]$reliabilityReport.passedCount
            failedCount = [int]$reliabilityReport.failedCount
        }
    }
    else {
        $milestone2 = New-GateResult -status "FAIL" -reason "Reliability suite contains failures" -details @{
            passedCount = [int]$reliabilityReport.passedCount
            failedCount = [int]$reliabilityReport.failedCount
        }
    }
}

$milestone3 = $null
if ($null -eq $releaseManifest) {
    $milestone3 = New-GateResult -status "UNKNOWN" -reason "Release manifest missing" -details @{
        expectedManifestPath = $ReleaseManifestPath
        expectedChecksumsPath = $ReleaseChecksumsPath
    }
}
else {
    $hasServerArchive = -not [string]::IsNullOrWhiteSpace([string]$releaseManifest.serverArchive)
    $hasSourceArchive = -not [string]::IsNullOrWhiteSpace([string]$releaseManifest.pluginSourceArchive)
    $installableAvailable = [bool]$releaseManifest.pluginInstallableAvailable
    $checksumsPresent = Test-Path $releaseChecksumsFull

    $manifestPass = $hasServerArchive -and $hasSourceArchive -and $installableAvailable -and $checksumsPresent
    if ($manifestPass) {
        $milestone3 = New-GateResult -status "PASS" -reason "Release bundle evidence present" -details @{
            serverArchive = [string]$releaseManifest.serverArchive
            pluginSourceArchive = [string]$releaseManifest.pluginSourceArchive
            pluginInstallableArtifact = [string]$releaseManifest.pluginInstallableArtifact
            checksumsPath = $ReleaseChecksumsPath
        }
    }
    else {
        $milestone3 = New-GateResult -status "FAIL" -reason "Release bundle evidence incomplete" -details @{
            hasServerArchive = $hasServerArchive
            hasPluginSourceArchive = $hasSourceArchive
            pluginInstallableAvailable = $installableAvailable
            checksumsPresent = $checksumsPresent
            checksumsPath = $ReleaseChecksumsPath
        }
    }
}

$allStatuses = @($milestone1.status, $milestone2.status, $milestone3.status)
$specComplete = "UNKNOWN"
if ($allStatuses -contains "FAIL") {
    $specComplete = "FAIL"
}
elseif (($allStatuses | Where-Object { $_ -eq "PASS" }).Count -eq 3) {
    $specComplete = "PASS"
}

$report = [pscustomobject]@{
    generatedUtc = (Get-Date).ToUniversalTime().ToString("o")
    milestones = [pscustomobject]@{
        milestone1_parity = $milestone1
        milestone2_reliability = $milestone2
        milestone3_distribution = $milestone3
    }
    specComplete = $specComplete
}

$outputDir = Split-Path -Parent $outputFull
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$report | ConvertTo-Json -Depth 20 | Set-Content -Path $outputFull -Encoding UTF8

Write-Output "Spec readiness report written: $outputFull"
Write-Output "- milestone1=$($milestone1.status)"
Write-Output "- milestone2=$($milestone2.status)"
Write-Output "- milestone3=$($milestone3.status)"
Write-Output "- specComplete=$specComplete"

if ($FailIfNotPass -and $specComplete -ne "PASS") {
    throw "Spec readiness check failed: specComplete=$specComplete"
}

