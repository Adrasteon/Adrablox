$ErrorActionPreference = 'Stop'
$endpoint = 'http://127.0.0.1:44877/mcp'
$script:ReqId = 0

function Invoke-Mcp([string]$Method, $Params) {
    $script:ReqId += 1
    $body = @{
        jsonrpc = '2.0'
        id = $script:ReqId
        method = $Method
        params = $Params
    }

    $response = Invoke-RestMethod -Uri $endpoint -Method Post -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 20)
    if ($response.error) {
        throw "MCP error: $($response.error.message)"
    }

    return $response.result
}

function Invoke-Tool([string]$Name, $Arguments) {
    $result = Invoke-Mcp -Method 'tools/call' -Params @{ name = $Name; arguments = $Arguments }
    return $result.structuredContent
}

Invoke-Mcp -Method 'initialize' -Params @{
    protocolVersion = '2025-11-25'
    capabilities = @{ resources = @{ subscribe = $true }; tools = @{} }
    clientInfo = @{ name = 'live-file-check'; version = '0.1.0' }
} | Out-Null
Invoke-Mcp -Method 'notifications/initialized' -Params @{} | Out-Null

$open = Invoke-Tool -Name 'roblox.openSession' -Arguments @{ projectPath = 'src' }
$sessionId = [string]$open.sessionId
$cursor = [string]$open.initialCursor

$filePath = Join-Path (Get-Location) 'src/App.module.lua'
$before = Get-Content -Raw -Path $filePath
Set-Content -Path $filePath -Value ($before + "`n-- live-change-check") -NoNewline
Start-Sleep -Milliseconds 500

$sub = Invoke-Tool -Name 'roblox.subscribeChanges' -Arguments @{ sessionId = $sessionId; cursor = $cursor }

$updatedCount = @($sub.updated).Count
Write-Output ("updatedCount={0}" -f $updatedCount)
if ($updatedCount -gt 0) {
    Write-Output ("firstChangedProperties={0}" -f (($sub.updated[0].changedProperties | ConvertTo-Json -Compress)))
}

Set-Content -Path $filePath -Value $before -NoNewline
Invoke-Tool -Name 'roblox.closeSession' -Arguments @{ sessionId = $sessionId } | Out-Null
Write-Output 'live-file-check completed'
