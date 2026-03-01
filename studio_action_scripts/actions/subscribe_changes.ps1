param(
    [Parameter(Mandatory=$true)][string]$SessionId,
    [string]$Cursor = $null,
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"

$arguments = @{
    sessionId = $SessionId
}
if ($null -ne $Cursor) {
    $arguments.cursor = $Cursor
}

$params = @{
    name = 'roblox.subscribeChanges'
    arguments = $arguments
} | ConvertTo-Json -Depth 10 -Compress

$payload = [ordered]@{
    jsonrpc = '2.0'
    id = 1
    method = 'tools/call'
    params = ($params | ConvertFrom-Json)
}

$bodyJson = $payload | ConvertTo-Json -Depth 12
$response = Invoke-RestMethod -Uri $Url -Method Post -Body $bodyJson -ContentType 'application/json'

if ($Pretty) {
    $response | ConvertTo-Json -Depth 12 | Write-Host
} else {
    $response
}
