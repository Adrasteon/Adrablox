param(
    [string]$Endpoint = "http://127.0.0.1:44877/mcp",
    [string]$ProjectPath = "adrablox.project.json",
    [int]$Iterations = 3
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

    $response = Invoke-RestMethod -Uri $Endpoint -Method Post -ContentType "application/json" -Body ($bodyObject | ConvertTo-Json -Depth 40)

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

function Get-NodeById {
    param(
        [Parameter(Mandatory = $true)]$Tree,
        [Parameter(Mandatory = $true)][string]$InstanceId
    )

    if ($Tree.instances -and $Tree.instances.PSObject.Properties[$InstanceId]) {
        return $Tree.instances.PSObject.Properties[$InstanceId].Value
    }

    return $null
}

Assert-True -Condition ($Iterations -ge 1) -Message "Iterations must be >= 1"

$sessionId = ""
$targetId = ""
$rootId = ""
$originalSource = ""

Write-Host "[1/7] initialize"
Invoke-Mcp -Method "initialize" -Params @{
    protocolVersion = "2025-11-25"
    capabilities = @{
        resources = @{ subscribe = $true }
        tools = @{}
    }
    clientInfo = @{
        name = "mcp-integration-reconnect-loop-contract-test"
        version = "0.1.0"
    }
} | Out-Null

Write-Host "[2/7] notifications/initialized"
Invoke-Mcp -Method "notifications/initialized" -Params @{} | Out-Null

Write-Host "[3/7] open initial session and capture target"
$open = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath }
$sessionId = [string]$open.sessionId
$rootId = [string]$open.rootInstanceId
$tree = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionId; instanceId = $rootId }
$fileBacked = @($tree.fileBackedInstanceIds)
Assert-True -Condition ($fileBacked.Count -gt 0) -Message "Expected file-backed instances"
$targetId = [string]$fileBacked[0]
$node = Get-NodeById -Tree $tree -InstanceId $targetId
Assert-True -Condition ($null -ne $node) -Message "Target node missing"
$originalSource = [string]$node.Properties.Source
$currentCursor = [string]$tree.cursor

Write-Host "[4/7] reconnect loop iterations=$Iterations"
for ($i = 1; $i -le $Iterations; $i++) {
    $marker = "-- reconnect-loop-" + $i + "-" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")
    $nextSource = $originalSource + "`n" + $marker

    $patch = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
        sessionId = $sessionId
        patchId = "reconnect_loop_patch_" + $i
        baseCursor = $currentCursor
        origin = "integration-reconnect-loop-contract-test"
        operations = @(
            @{
                op = "setProperty"
                instanceId = $targetId
                property = "Source"
                value = $nextSource
            }
        )
    }
    Assert-True -Condition ($patch.accepted -eq $true) -Message "Iteration $i patch should be accepted"

    $appliedCursor = [string]$patch.appliedCursor
    $sub = Invoke-McpTool -Name "roblox.subscribeChanges" -Arguments @{ sessionId = $sessionId; cursor = $currentCursor }
    Assert-True -Condition ([string]$sub.cursor -eq $appliedCursor) -Message "Iteration $i subscribe cursor mismatch"
    Assert-True -Condition (@($sub.updated).Count -ge 1) -Message "Iteration $i should report updates"

    $close = Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionId }
    Assert-True -Condition ($close.closed -eq $true) -Message "Iteration $i close should succeed"

    $reopen = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath }
    $sessionId = [string]$reopen.sessionId
    $rootId = [string]$reopen.rootInstanceId

    $readAfterReopen = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionId; instanceId = $rootId }
    $nodeAfterReopen = Get-NodeById -Tree $readAfterReopen -InstanceId $targetId
    if ($null -eq $nodeAfterReopen) {
        $fallbackTarget = [string](@($readAfterReopen.fileBackedInstanceIds)[0])
        $targetId = $fallbackTarget
        $nodeAfterReopen = Get-NodeById -Tree $readAfterReopen -InstanceId $targetId
    }

    Assert-True -Condition ($null -ne $nodeAfterReopen) -Message "Iteration $i node missing after reopen"
    $sourceAfterReopen = [string]$nodeAfterReopen.Properties.Source
    Assert-True -Condition ($sourceAfterReopen.Contains($marker)) -Message "Iteration $i marker missing after reopen"

    $currentCursor = [string]$readAfterReopen.cursor
}

Write-Host "[5/7] restore original source"
$restorePatch = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "reconnect_loop_restore"
    baseCursor = $currentCursor
    origin = "integration-reconnect-loop-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $targetId
            property = "Source"
            value = $originalSource
        }
    )
}
Assert-True -Condition ($restorePatch.accepted -eq $true) -Message "Restore patch should be accepted"

Write-Host "[6/7] verify restore"
$verifyTree = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionId; instanceId = $rootId }
$verifyNode = Get-NodeById -Tree $verifyTree -InstanceId $targetId
Assert-True -Condition ($null -ne $verifyNode) -Message "Verify node missing"
Assert-True -Condition ([string]$verifyNode.Properties.Source -eq $originalSource) -Message "Source should match original after restore"

Write-Host "[7/7] close final session"
$closedFinal = Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionId }
Assert-True -Condition ($closedFinal.closed -eq $true) -Message "Final close should succeed"

Write-Host "Integration reconnect-loop contract test completed successfully."
