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

    $response = Invoke-RestMethod -Uri $Endpoint -Method Post -ContentType "application/json" -Body ($bodyObject | ConvertTo-Json -Depth 30)
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

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

Write-Host "[1/8] initialize"
Invoke-Mcp -Method "initialize" -Params @{
    protocolVersion = "2025-11-25"
    capabilities = @{
        resources = @{ subscribe = $true }
        tools = @{}
    }
    clientInfo = @{
        name = "mcp-reconnect-replay-contract-test"
        version = "0.1.0"
    }
} | Out-Null

Write-Host "[2/8] notifications/initialized"
Invoke-Mcp -Method "notifications/initialized" -Params @{} | Out-Null

Write-Host "[3/8] open + read"
$open = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath }
$sessionId = [string]$open.sessionId
$rootInstanceId = [string]$open.rootInstanceId

$tree = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionId; instanceId = $rootInstanceId }
$initialCursor = [string]$tree.cursor
$fileBackedIds = @($tree.fileBackedInstanceIds)
Assert-True -Condition ($fileBackedIds.Count -gt 0) -Message "Expected at least one file-backed instance"
$targetId = [string]$fileBackedIds[0]
$instanceNode = $tree.instances.PSObject.Properties[$targetId].Value
Assert-True -Condition ($null -ne $instanceNode) -Message "Target file-backed instance missing"
$originalSource = [string]$instanceNode.Properties.Source

Write-Host "  sessionId=$sessionId targetId=$targetId initialCursor=$initialCursor"

Write-Host "[4/8] apply two accepted Source patches"
$source1 = $originalSource + "`n-- reconnect-replay-1"
$patch1 = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "replay_patch_1"
    baseCursor = $initialCursor
    origin = "reconnect-replay-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $targetId
            property = "Source"
            value = $source1
        }
    )
}
Assert-True -Condition ($patch1.accepted -eq $true) -Message "First patch should be accepted"
$cursor1 = [string]$patch1.appliedCursor

$source2 = $originalSource + "`n-- reconnect-replay-2"
$patch2 = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "replay_patch_2"
    baseCursor = $cursor1
    origin = "reconnect-replay-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $targetId
            property = "Source"
            value = $source2
        }
    )
}
Assert-True -Condition ($patch2.accepted -eq $true) -Message "Second patch should be accepted"
$cursor2 = [string]$patch2.appliedCursor

Write-Host "[5/8] subscribe from old cursor should replay missed updates"
$replay = Invoke-McpTool -Name "roblox.subscribeChanges" -Arguments @{ sessionId = $sessionId; cursor = $initialCursor }
$replayUpdated = @($replay.updated).Count
Assert-True -Condition ($replayUpdated -ge 2) -Message "Expected replay to include both missed updates"
Assert-True -Condition ([string]$replay.cursor -eq $cursor2) -Message "Replay cursor should advance to latest cursor"

Write-Host "[6/8] subscribe from future cursor should not advance"
$future = Invoke-McpTool -Name "roblox.subscribeChanges" -Arguments @{ sessionId = $sessionId; cursor = "999999" }
Assert-True -Condition (@($future.updated).Count -eq 0) -Message "Future cursor subscribe should have no updates"
Assert-True -Condition ([string]$future.cursor -eq $cursor2) -Message "Future cursor subscribe should return current cursor"

Write-Host "[7/8] restore original Source"
$restore = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "replay_restore"
    baseCursor = $cursor2
    origin = "reconnect-replay-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $targetId
            property = "Source"
            value = $originalSource
        }
    )
}
Assert-True -Condition ($restore.accepted -eq $true) -Message "Restore patch should be accepted"

Write-Host "[8/8] closeSession"
$closed = Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionId }
Assert-True -Condition ($closed.closed -eq $true) -Message "Session should close"

Write-Host "Reconnect/replay contract test completed successfully."
