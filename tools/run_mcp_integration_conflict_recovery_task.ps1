param(
    [int]$Iterations = 2
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
$serverUrl = 'http://127.0.0.1:44877/health'

if (-not (Test-Path $cargoExe)) {
    throw "cargo not found at $cargoExe"
}

Push-Location $workspace
try {
    Write-Host "Starting MCP server..."
    $server = Start-Process -FilePath $cargoExe -ArgumentList @('run','-p','mcp-server') -WorkingDirectory $workspace -PassThru

    $ready = $false
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep -Milliseconds 500
        try {
            $health = Invoke-RestMethod -Uri $serverUrl -Method Get -TimeoutSec 2
            if ($health.ok -eq $true) {
                $ready = $true
                break
            }
        }
        catch {
        }
    }

    if (-not $ready) {
        throw "MCP server did not become healthy in time."
    }

    Write-Host "Server is healthy. Running integration conflict-recovery contract test..."
    & (Join-Path $workspace 'tools\mcp_integration_conflict_recovery_contract_test.ps1') -Iterations $Iterations

    Write-Host "Integration conflict-recovery task completed successfully."
}
finally {
    if ($server -and -not $server.HasExited) {
        Write-Host "Stopping MCP server..."
        Stop-Process -Id $server.Id -Force
    }
    Pop-Location
}
