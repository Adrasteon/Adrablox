param(
    [int]$ReconnectIterations = 1,
    [int]$ConflictIterations = 1,
    [int]$MixedIterations = 1,
    [int]$MutationSettleMs = 500,
    [string]$Categories = "",
    [string]$Fixtures = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ($ReconnectIterations -lt 1) { throw "ReconnectIterations must be >= 1" }
if ($ConflictIterations -lt 1) { throw "ConflictIterations must be >= 1" }
if ($MixedIterations -lt 1) { throw "MixedIterations must be >= 1" }
if ($MutationSettleMs -lt 0) { throw "MutationSettleMs must be >= 0" }

$workspace = Split-Path -Parent $PSScriptRoot

Push-Location $workspace
try {
    Write-Host "Running mission-critical local gate..."
    Write-Host "- reconnectIterations=$ReconnectIterations"
    Write-Host "- conflictIterations=$ConflictIterations"
    Write-Host "- mixedIterations=$MixedIterations"
    Write-Host "- mutationSettleMs=$MutationSettleMs"
    Write-Host "- categories='$Categories'"
    Write-Host "- fixtures='$Fixtures'"
    Write-Host "- dryRun=$DryRun"

    $args = @(
        '-ReconnectIterations', "$ReconnectIterations",
        '-ConflictIterations', "$ConflictIterations",
        '-MixedIterations', "$MixedIterations",
        '-MutationSettleMs', "$MutationSettleMs",
        '-IncludeDistributionEvidence',
        '-FailIfNotPass'
    )

    if (-not [string]::IsNullOrWhiteSpace($Categories)) {
        $args += @('-Categories', $Categories)
    }

    if (-not [string]::IsNullOrWhiteSpace($Fixtures)) {
        $args += @('-Fixtures', $Fixtures)
    }

    if ($DryRun) {
        $args += '-DryRun'
    }

    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace 'tools/run_release_candidate_evidence_pack_task.ps1') @args

    if ($DryRun) {
        Write-Host "Mission-critical local gate dry-run completed successfully."
        return
    }

    Write-Host "Mission-critical local gate completed successfully."
}
finally {
    Pop-Location
}
