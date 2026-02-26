$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
$serverUrl = 'http://127.0.0.1:44877/health'

if (-not (Test-Path $cargoExe)) {
    throw "cargo not found at $cargoExe"
}

function Get-PythonExecutable {
    $candidates = @(
        "$env:LocalAppData\Programs\Python\Python312\python.exe",
        "$env:LocalAppData\Programs\Python\Python313\python.exe",
        "$env:ProgramFiles\Python312\python.exe",
        "$env:ProgramFiles\Python313\python.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "Python executable not found. Install Python 3.12+ or update candidate paths in tools/run_mcp_protocol_task.ps1"
}

$pythonExe = Get-PythonExecutable

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

    Write-Host "Server is healthy. Running protocol contract test..."
    & $pythonExe (Join-Path $workspace 'tools\mcp_protocol_contract_test.py')

    Write-Host "Protocol contract task completed successfully."
}
finally {
    if ($server -and -not $server.HasExited) {
        Write-Host "Stopping MCP server..."
        Stop-Process -Id $server.Id -Force
    }
    Pop-Location
}
