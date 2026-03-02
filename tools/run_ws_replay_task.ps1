param(
    [string]$NodeExe = "node"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
$serverUrl = 'http://127.0.0.1:44877/health'
$reportPath = Join-Path $workspace 'tools/ws_replay_report.json'

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

    Write-Host "Server is healthy. Running reconnect/replay contract test..."
    & (Join-Path $workspace 'tools\mcp_reconnect_replay_contract_test.ps1')

    Write-Host "Running ws-tail CLI flag/auth/replay smoke test..."
    & (Join-Path $workspace 'tools\ws_cli_flag_smoke_test.ps1') -NodeExe $NodeExe

    $report = [ordered]@{
        status = 'PASS'
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        checks = @(
            'mcp_reconnect_replay_contract_test',
            'ws_cli_flag_smoke_test'
        )
        notes = @(
            'Server replay contract passed',
            'CLI ws-tail replay/auth flags validated'
        )
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath -Encoding UTF8
    Write-Host "WS replay task completed successfully. Report: $reportPath"
}
finally {
    if ($server -and -not $server.HasExited) {
        Write-Host "Stopping MCP server..."
        Stop-Process -Id $server.Id -Force
    }
    Pop-Location
}
