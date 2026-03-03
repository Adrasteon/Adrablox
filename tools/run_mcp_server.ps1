param(
    [switch]$RojoCompat
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'

if (-not (Test-Path $cargoExe)) {
    throw "cargo not found at $cargoExe"
}

Push-Location $workspace
try {
    Write-Host "Starting MCP server (manual mode)..."
    $env:MCP_ENABLE_NATIVE_PROJECT_MANIFEST = 'true'
    $env:MCP_NATIVE_PROJECT_MANIFEST_PATH = 'adrablox.project.json'
    $cargoArgs = @('run','-p','mcp-server')
    if ($RojoCompat) {
        Write-Host "Rojo compatibility build enabled (--features rojo-compat)."
        $cargoArgs += @('--features','rojo-compat')
    }
    & $cargoExe @cargoArgs
}
finally {
    Pop-Location
}
