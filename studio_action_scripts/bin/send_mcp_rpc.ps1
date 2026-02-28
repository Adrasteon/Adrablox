param(
    [string]$Method = "tools/list",
    [string]$Params = "{}",
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'

# Prefer calling the repo-local tools helper when present to avoid duplication.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"
$toolsHelper = Join-Path $repoRoot "tools\send_mcp_rpc.ps1"

# Prefer Node CLI if available
if (Test-Path $nodeCli) {
    & node $nodeCli 'call' $Method $Params -Url $Url | Out-Null
    exit $LASTEXITCODE
}

# Fall back to the repo-local PowerShell helper
if (Test-Path $toolsHelper) {
    $flags = @()
    if ($Pretty) { $flags += '-Pretty' }
    & $toolsHelper -Method $Method -Params $Params -Url $Url @flags
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
    $resp | ConvertTo-Json -Depth 10 | Write-Output
} else {
    $resp
}
