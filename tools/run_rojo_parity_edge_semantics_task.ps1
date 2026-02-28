param(
    [string]$Categories = "baseline,lifecycle-ops,mixed-services,metadata-churn",
    [int]$MutationSettleMs = 2000,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot

Push-Location $workspace
try {
    Write-Output "Running Rojo parity edge semantics checks..."
    Write-Output "- categories=$Categories"
    Write-Output "- mutationSettleMs=$MutationSettleMs"

    $suiteArgs = @{
        Categories = $Categories
        MutationSettleMs = $MutationSettleMs
    }
    if ($DryRun) {
        $suiteArgs.DryRun = $true
    }

    & (Join-Path $workspace 'tools\run_rojo_parity_suite_task.ps1') @suiteArgs

    if ($DryRun) {
        Write-Output "Rojo parity edge semantics dry-run completed."
    }
    else {
        Write-Output "Rojo parity edge semantics checks completed successfully."
    }
}
finally {
    Pop-Location
}

