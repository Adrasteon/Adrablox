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
    Write-Output "Running mission-critical local gate..."
    Write-Output "- reconnectIterations=$ReconnectIterations"
    Write-Output "- conflictIterations=$ConflictIterations"
    Write-Output "- mixedIterations=$MixedIterations"
    Write-Output "- mutationSettleMs=$MutationSettleMs"
    Write-Output "- categories='$Categories'"
    Write-Output "- fixtures='$Fixtures'"
    Write-Output "- dryRun=$DryRun"

    $cliArgs = @(
        '-ReconnectIterations', "$ReconnectIterations",
        '-ConflictIterations', "$ConflictIterations",
        '-MixedIterations', "$MixedIterations",
        '-MutationSettleMs', "$MutationSettleMs",
        '-IncludeDistributionEvidence',
        '-FailIfNotPass'
    )

    if (-not [string]::IsNullOrWhiteSpace($Categories)) {
        $cliArgs += @('-Categories', $Categories)
    }

    if (-not [string]::IsNullOrWhiteSpace($Fixtures)) {
        $cliArgs += @('-Fixtures', $Fixtures)
    }

    if ($DryRun) {
        $cliArgs += '-DryRun'
    }

    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace 'tools/run_release_candidate_evidence_pack_task.ps1') @cliArgs

    if ($DryRun) {
        Write-Output "Mission-critical local gate dry-run completed successfully."
        return
    }

    Write-Output "Mission-critical local gate completed successfully."
}
finally {
    Pop-Location
}

