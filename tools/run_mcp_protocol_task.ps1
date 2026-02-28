$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
$serverUrl = 'http://127.0.0.1:44877/health'

if (-not (Test-Path $cargoExe)) {
    throw "cargo not found at $cargoExe"
}

function Get-PythonCommand {
    $pythonLocation = $env:pythonLocation
    if (-not [string]::IsNullOrWhiteSpace($pythonLocation)) {
        $pythonFromEnv = Join-Path $pythonLocation 'python.exe'
        if (Test-Path $pythonFromEnv) {
            return [pscustomobject]@{
                FilePath = $pythonFromEnv
                PrefixArgs = @()
            }
        }
    }

    $candidates = @(
        "$env:LocalAppData\Programs\Python\Python312\python.exe",
        "$env:LocalAppData\Programs\Python\Python313\python.exe",
        "$env:ProgramFiles\Python312\python.exe",
        "$env:ProgramFiles\Python313\python.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return [pscustomobject]@{
                FilePath = $candidate
                PrefixArgs = @()
            }
        }
    }

    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCommand) {
        return [pscustomobject]@{
            FilePath = $pythonCommand.Source
            PrefixArgs = @()
        }
    }

    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        return [pscustomobject]@{
            FilePath = $pyLauncher.Source
            PrefixArgs = @('-3')
        }
    }

    throw "Python executable not found. Install Python 3.12+ (or py launcher) or update candidate paths in tools/run_mcp_protocol_task.ps1"
}

$pythonCommand = Get-PythonCommand

Push-Location $workspace
try {
    Write-Output "Starting MCP server..."
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
    Write-Output 'Ignored error (empty catch) in run_mcp_protocol_task.ps1'
}
    }

    if (-not $ready) {
        throw "MCP server did not become healthy in time."
    }

    Write-Output "Server is healthy. Running protocol contract test..."
    $scriptPath = Join-Path $workspace 'tools\mcp_protocol_contract_test.py'
    & $pythonCommand.FilePath @($pythonCommand.PrefixArgs + @($scriptPath))

    Write-Output "Protocol contract task completed successfully."
}
finally {
    if ($server -and -not $server.HasExited) {
        Write-Output "Stopping MCP server..."
        Stop-Process -Id $server.Id -Force
    }
    Pop-Location
}


