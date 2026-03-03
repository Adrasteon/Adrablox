$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
$serverUrl = 'http://127.0.0.1:44877/health'
$waitScript = Join-Path $workspace 'tools\wait_for_mcp_health.ps1'

if (-not (Test-Path $cargoExe)) {
    throw "cargo not found at $cargoExe"
}

Push-Location $workspace
try {
    Write-Host "Starting MCP server..."
    $env:MCP_ENABLE_NATIVE_PROJECT_MANIFEST = 'true'
    $env:MCP_NATIVE_PROJECT_MANIFEST_PATH = 'adrablox.project.json'
    $server = Start-Process -FilePath $cargoExe -ArgumentList @('run','-p','mcp-server') -WorkingDirectory $workspace -PassThru

    & $waitScript -Url $serverUrl -TimeoutSeconds 60 -PollIntervalMilliseconds 500 -Quiet
    if ($LASTEXITCODE -ne 0) {
        throw "MCP server did not become healthy in time."
    }

    Write-Host "Server is healthy. Running smoke test..."
    & (Join-Path $workspace 'tools\mcp_smoke_test.ps1')

    Write-Host "Smoke task completed successfully."
}
finally {
    if ($server -and -not $server.HasExited) {
        Write-Host "Stopping MCP server..."
        Stop-Process -Id $server.Id -Force
    }
    Pop-Location
}
