$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'

if (-not (Test-Path $cargoExe)) {
    throw "cargo not found at $cargoExe"
}

Push-Location $workspace
try {
    Write-Output "Starting MCP server (manual mode)..."
    & $cargoExe run -p mcp-server
}
finally {
    Pop-Location
}

