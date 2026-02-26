param(
    [string]$Endpoint = "http://127.0.0.1:44877/mcp",
    [string]$ProjectPath = "src"
)

$ErrorActionPreference = "Stop"

$script:RequestId = 0

function Invoke-Mcp {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $false)]$Params
    )

    $script:RequestId += 1

    $bodyObject = @{
        jsonrpc = "2.0"
        id = $script:RequestId
        method = $Method
        params = $(if ($null -eq $Params) { @{} } else { $Params })
    }

    $response = Invoke-RestMethod -Uri $Endpoint -Method Post -ContentType "application/json" -Body ($bodyObject | ConvertTo-Json -Depth 20)

    if ($null -ne $response.error) {
        throw "MCP error: $($response.error.message)"
    }

    return $response.result
}

function Invoke-McpTool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)]$Arguments = @{}
    )

    $result = Invoke-Mcp -Method "tools/call" -Params @{
        name = $Name
        arguments = $Arguments
    }

    if ($null -eq $result.structuredContent) {
        throw "Tool '$Name' missing structuredContent"
    }

    return $result.structuredContent
}

Write-Host "[1/7] initialize"
$init = Invoke-Mcp -Method "initialize" -Params @{
    protocolVersion = "2025-11-25"
    capabilities = @{
        resources = @{ subscribe = $true }
        tools = @{}
    }
    clientInfo = @{
        name = "mcp-smoke-test"
        version = "0.1.0"
    }
}
Write-Host "  protocolVersion=$($init.protocolVersion)"

Write-Host "[2/7] notifications/initialized"
Invoke-Mcp -Method "notifications/initialized" -Params @{} | Out-Null

Write-Host "[3/7] roblox.openSession"
$open = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath }
$sessionId = [string]$open.sessionId
$rootInstanceId = [string]$open.rootInstanceId
$cursor = [int]$open.initialCursor
if ($null -ne $open.sessionCapabilities) {
    Write-Host "  capabilities=$($open.sessionCapabilities | ConvertTo-Json -Compress)"
}
Write-Host "  sessionId=$sessionId root=$rootInstanceId cursor=$cursor"

Write-Host "[4/7] roblox.readTree"
$tree = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionId; instanceId = $rootInstanceId }
Write-Host "  read cursor=$($tree.cursor) instanceCount=$($tree.instances.PSObject.Properties.Count)"

Write-Host "[5/7] roblox.applyPatch (setName)"
$patch = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "smoke_patch_001"
    baseCursor = [string]$tree.cursor
    origin = "smoke-test"
    operations = @(
        @{
            op = "setName"
            instanceId = "ref_server_script_service"
            name = "ServerScriptService"
        }
    )
}
Write-Host "  patch accepted=$($patch.accepted) cursor=$($patch.appliedCursor) conflicts=$($patch.conflicts.Count)"

Write-Host "[6/7] roblox.subscribeChanges"
$sub = Invoke-McpTool -Name "roblox.subscribeChanges" -Arguments @{ sessionId = $sessionId; cursor = [string]$cursor }
Write-Host "  sub cursor=$($sub.cursor) added=$($sub.added.PSObject.Properties.Count) updated=$($sub.updated.Count) removed=$($sub.removed.Count)"

Write-Host "[7/7] roblox.closeSession"
$closed = Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionId }
Write-Host "  closed=$($closed.closed)"

Write-Host "Smoke test completed successfully."
