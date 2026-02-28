param(
    [int]$ReconnectIterations = 5,
    [int]$ConflictIterations = 3,
    [int]$MixedIterations = 3,
    [int]$MutationSettleMs = 500,
    [string]$Categories = "",
    [string]$Fixtures = "",
    [switch]$IncludeDistributionEvidence,
    [switch]$SkipReliability,
    [switch]$SkipParitySuite,
    [switch]$SkipParitySummary,
    [switch]$SkipReadiness,
    [switch]$FailIfNotPass,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ($ReconnectIterations -lt 1) { throw "ReconnectIterations must be >= 1" }
if ($ConflictIterations -lt 1) { throw "ConflictIterations must be >= 1" }
if ($MixedIterations -lt 1) { throw "MixedIterations must be >= 1" }
if ($MutationSettleMs -lt 0) { throw "MutationSettleMs must be >= 0" }

$workspace = Split-Path -Parent $PSScriptRoot

function Ensure-RojoAvailable {
    $existing = Get-Command rojo -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        return
    }

    $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $wingetRoot) {
        $rojoExe = Get-ChildItem -Path $wingetRoot -Recurse -Filter 'rojo.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $rojoExe) {
            $rojoDir = Split-Path -Parent $rojoExe.FullName
            $env:Path = "$rojoDir;$env:Path"
        }
    }

    $resolved = Get-Command rojo -ErrorAction SilentlyContinue
    if ($null -eq $resolved) {
        throw "Rojo CLI is required for this step. Install Rojo or run with -SkipParitySuite (and omit -IncludeDistributionEvidence if packaging validation is not needed)."
    }
}

function Invoke-ToolScript {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $fullScriptPath = Join-Path $workspace $ScriptPath
    if (-not (Test-Path $fullScriptPath)) {
        throw "Missing required script for step '$Name': $ScriptPath"
    }

    Write-Output "[$Name] Running $ScriptPath"
    if ($Arguments.Count -gt 0) {
        Write-Output "[$Name] Args: $($Arguments -join ' ')"
    }

    if ($DryRun) {
        return
    }

    powershell -NoProfile -ExecutionPolicy Bypass -File $fullScriptPath @Arguments
}

Push-Location $workspace
try {
    Write-Output "Running release-candidate evidence pack..."
    Write-Output "- reconnectIterations=$ReconnectIterations"
    Write-Output "- conflictIterations=$ConflictIterations"
    Write-Output "- mixedIterations=$MixedIterations"
    Write-Output "- mutationSettleMs=$MutationSettleMs"
    Write-Output "- categories='$Categories'"
    Write-Output "- fixtures='$Fixtures'"
    Write-Output "- includeDistributionEvidence=$IncludeDistributionEvidence"
    Write-Output "- skipReliability=$SkipReliability"
    Write-Output "- skipParitySuite=$SkipParitySuite"
    Write-Output "- skipParitySummary=$SkipParitySummary"
    Write-Output "- skipReadiness=$SkipReadiness"
    Write-Output "- failIfNotPass=$FailIfNotPass"
    Write-Output "- dryRun=$DryRun"

    if (-not $SkipReliability) {
        $reliabilityArgs = @(
            '-ReconnectIterations', "$ReconnectIterations",
            '-ConflictIterations', "$ConflictIterations",
            '-MixedIterations', "$MixedIterations"
        )
        Invoke-ToolScript -Name 'reliability' -ScriptPath 'tools/run_mcp_integration_reliability_suite_task.ps1' -Arguments $reliabilityArgs
    }
    else {
        Write-Output "[reliability] Skipped"
    }

    if (-not $SkipParitySuite) {
        Ensure-RojoAvailable

        $paritySuiteArgs = @('-MutationSettleMs', "$MutationSettleMs")
        if (-not [string]::IsNullOrWhiteSpace($Categories)) {
            $paritySuiteArgs += @('-Categories', $Categories)
        }
        if (-not [string]::IsNullOrWhiteSpace($Fixtures)) {
            $paritySuiteArgs += @('-Fixtures', $Fixtures)
        }

        Invoke-ToolScript -Name 'parity-suite' -ScriptPath 'tools/run_rojo_parity_suite_task.ps1' -Arguments $paritySuiteArgs
    }
    else {
        Write-Output "[parity-suite] Skipped"
    }

    if (-not $SkipParitySummary) {
        $summaryArgs = @('-FailIfNoReports', '-FailIfDiffs')
        if (-not [string]::IsNullOrWhiteSpace($Categories)) {
            $summaryArgs += @('-FailCategories', $Categories)
        }

        Invoke-ToolScript -Name 'parity-summary' -ScriptPath 'tools/summarize_parity_reports.ps1' -Arguments $summaryArgs
    }
    else {
        Write-Output "[parity-summary] Skipped"
    }

    if ($IncludeDistributionEvidence) {
        Ensure-RojoAvailable
        Invoke-ToolScript -Name 'distribution-package' -ScriptPath 'tools/package_release_artifacts.ps1' -Arguments @('-RequireRojo')
        Invoke-ToolScript -Name 'distribution-manifest' -ScriptPath 'tools/validate_release_manifest.ps1' -Arguments @('-RequireInstallable')
        Invoke-ToolScript -Name 'distribution-checksums-generate' -ScriptPath 'tools/generate_release_checksums.ps1'
        Invoke-ToolScript -Name 'distribution-checksums-verify' -ScriptPath 'tools/generate_release_checksums.ps1' -Arguments @('-Verify')
        Invoke-ToolScript -Name 'distribution-day0-published' -ScriptPath 'tools/run_day0_published_artifact_validation_task.ps1' -Arguments @('-RequireInstallable')
    }
    else {
        Write-Output "[distribution] Skipped"
    }

    if (-not $SkipReadiness) {
        $readinessArgs = @()
        if ($FailIfNotPass) {
            $readinessArgs += '-FailIfNotPass'
        }
        Invoke-ToolScript -Name 'spec-readiness' -ScriptPath 'tools/run_spec_readiness_report.ps1' -Arguments $readinessArgs
    }
    else {
        Write-Output "[spec-readiness] Skipped"
    }

    if ($DryRun) {
        Write-Output "Release-candidate evidence pack dry-run completed successfully."
        return
    }

    Write-Output "Release-candidate evidence pack completed successfully."
}
finally {
    Pop-Location
}
