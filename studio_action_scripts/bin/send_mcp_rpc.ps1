param(
    [string]$Method = "tools/list",
    [string]$Params = "{}",
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'

# Prefer calling the repo-local tools helper when present to avoid duplication.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$toolsHelper = Join-Path $repoRoot "tools\send_mcp_rpc.ps1"

if (Test-Path $toolsHelper) {
    & $toolsHelper -Method $Method -Params $Params -Url $Url @($Pretty ? '-Pretty' : @())
    exit $LASTEXITCODE
}

try {
    $paramsObj = $Params | ConvertFrom-Json
} catch {
    Write-Error "Failed to parse -Params as JSON: $_"
    exit 2
}

$payload = [ordered]@{
    jsonrpc = '2.0'
    id = 1
    method = $Method
    params = $paramsObj
}

$bodyJson = $payload | ConvertTo-Json -Depth 10

try {
    $resp = Invoke-RestMethod -Uri $Url -Method Post -Body $bodyJson -ContentType 'application/json'
} catch {
    Write-Error "HTTP request failed: $($_.Exception.Message)"
    exit 3
}

if ($Pretty) {
    $resp | ConvertTo-Json -Depth 10 | Write-Host
} else {
    $resp
}
