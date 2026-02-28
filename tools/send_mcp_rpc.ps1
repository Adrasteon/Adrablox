<#
Sends a single JSON-RPC request to the MCP server and prints the response.

Usage examples:
  powershell -NoProfile -File tools\send_mcp_rpc.ps1 -Method tools/list -Pretty
  powershell -NoProfile -File tools\send_mcp_rpc.ps1 -Method roblox.openSession -Params '{"protocolVersion":"2025-11-25","capabilities":{}}' -Pretty
#>
param(
    [string]$Method = "tools/list",
    [string]$Params = "{}",
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'

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
