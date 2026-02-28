param(
    [int]$ReconnectIterations = 5,
    [int]$ConflictIterations = 3,
    [int]$MixedIterations = 3,
    [string]$ReportPath = "tools/integration_reliability_report.json"
)

$ErrorActionPreference = "Stop"

if ($ReconnectIterations -lt 1) { throw "ReconnectIterations must be >= 1" }
if ($ConflictIterations -lt 1) { throw "ConflictIterations must be >= 1" }
if ($MixedIterations -lt 1) { throw "MixedIterations must be >= 1" }

$workspace = Split-Path -Parent $PSScriptRoot
$absoluteReportPath = Join-Path $workspace $ReportPath
$reportDir = Split-Path -Parent $absoluteReportPath
if (-not [string]::IsNullOrWhiteSpace($reportDir) -and -not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $start = Get-Date
    try {
        $actionOutput = & $Action 2>&1
        foreach ($line in @($actionOutput)) {
            if ($null -ne $line -and -not [string]::IsNullOrWhiteSpace("$line")) {
                Write-Host $line
            }
        }
        $end = Get-Date
        return [pscustomobject]@{
            name = $Name
            status = "passed"
            startedUtc = $start.ToUniversalTime().ToString("o")
            endedUtc = $end.ToUniversalTime().ToString("o")
            durationSeconds = [Math]::Round(($end - $start).TotalSeconds, 3)
            error = $null
        }
    }
    catch {
        $end = Get-Date
        return [pscustomobject]@{
            name = $Name
            status = "failed"
            startedUtc = $start.ToUniversalTime().ToString("o")
            endedUtc = $end.ToUniversalTime().ToString("o")
            durationSeconds = [Math]::Round(($end - $start).TotalSeconds, 3)
            error = $_.Exception.Message
        }
    }
}

Push-Location $workspace
try {
    Write-Host "Running integration reliability evidence suite..."
    Write-Host "- reconnectIterations=$ReconnectIterations"
    Write-Host "- conflictIterations=$ConflictIterations"
    Write-Host "- mixedIterations=$MixedIterations"

    $steps = @()
    $steps += Invoke-Step -Name "integration-reconnect-loop" -Action {
        powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace 'tools/run_mcp_integration_reconnect_loop_task.ps1') -Iterations $ReconnectIterations
    }
    $steps += Invoke-Step -Name "integration-conflict-recovery" -Action {
        powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace 'tools/run_mcp_integration_conflict_recovery_task.ps1') -Iterations $ConflictIterations
    }
    $steps += Invoke-Step -Name "integration-mixed-resilience" -Action {
        powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace 'tools/run_mcp_integration_mixed_resilience_task.ps1') -Iterations $MixedIterations
    }

    $failed = @($steps | Where-Object { $_.status -ne "passed" })
    $report = [ordered]@{
        generatedUtc = (Get-Date).ToUniversalTime().ToString("o")
        reconnectIterations = $ReconnectIterations
        conflictIterations = $ConflictIterations
        mixedIterations = $MixedIterations
        allPassed = ($failed.Count -eq 0)
        passedCount = @($steps | Where-Object { $_.status -eq "passed" }).Count
        failedCount = $failed.Count
        steps = $steps
    }

    $report | ConvertTo-Json -Depth 10 | Set-Content -Path $absoluteReportPath -Encoding UTF8
    Write-Host "Reliability report written: $absoluteReportPath"

    if ($failed.Count -gt 0) {
        $failedNames = ($failed | ForEach-Object { $_.name }) -join ", "
        throw "Integration reliability suite failed: $failedNames"
    }

    Write-Host "Integration reliability suite completed successfully."
}
finally {
    Pop-Location
}
