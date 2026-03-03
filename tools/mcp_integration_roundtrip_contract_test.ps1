param(
    [string]$Endpoint = "http://127.0.0.1:44877/mcp",
    [string]$ProjectPath = "adrablox.project.json"
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

$originalSource = ""
$marker = ""
$targetId = ""
$restoreNeeded = $false

Write-Host "[1/10] initialize"
Invoke-Mcp -Method "initialize" -Params @{
    protocolVersion = "2025-11-25"
    capabilities = @{
        resources = @{ subscribe = $true }
        tools = @{}
    }
    clientInfo = @{
        name = "mcp-integration-roundtrip-contract-test"
        version = "0.1.0"
    }
} | Out-Null

Write-Host "[2/10] notifications/initialized"
Invoke-Mcp -Method "notifications/initialized" -Params @{} | Out-Null

Write-Host "[3/10] open/read session A"
$openA = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath }
$sessionA = [string]$openA.sessionId
$rootA = [string]$openA.rootInstanceId
$treeA = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionA; instanceId = $rootA }
$fileBackedA = @($treeA.fileBackedInstanceIds)
Assert-True -Condition ($fileBackedA.Count -gt 0) -Message "Expected file-backed instances in session A"
$targetId = [string]$fileBackedA[0]
$nodeA = Get-NodeById -Tree $treeA -InstanceId $targetId
Assert-True -Condition ($null -ne $nodeA) -Message "Target node missing in session A"
$originalSource = [string]$nodeA.Properties.Source
$baseCursorA = [string]$treeA.cursor

$marker = "-- integration-roundtrip-marker-" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")
$modifiedSource = $originalSource + "`n" + $marker

Write-Host "[4/10] apply Source update in session A"
$patchA = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionA
    patchId = "integration_roundtrip_apply"
    baseCursor = $baseCursorA
    origin = "integration-roundtrip-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $targetId
            property = "Source"
            value = $modifiedSource
        }
    )
}
Assert-True -Condition ($patchA.accepted -eq $true) -Message "Source update patch should be accepted"
$restoreNeeded = $true

Write-Host "[5/10] verify update via read in session A"
$treeA2 = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionA; instanceId = $rootA }
$nodeA2 = Get-NodeById -Tree $treeA2 -InstanceId $targetId
Assert-True -Condition ($null -ne $nodeA2) -Message "Target node missing after update"
$updatedSourceA = [string]$nodeA2.Properties.Source
Assert-True -Condition ($updatedSourceA.Contains($marker)) -Message "Updated source should include marker in session A"

Write-Host "[6/10] close session A"
$closedA = Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionA }
Assert-True -Condition ($closedA.closed -eq $true) -Message "Session A should close"

Write-Host "[7/10] open/read session B"
$openB = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath }
$sessionB = [string]$openB.sessionId
$rootB = [string]$openB.rootInstanceId
$treeB = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionB; instanceId = $rootB }
$fileBackedB = @($treeB.fileBackedInstanceIds)
Assert-True -Condition ($fileBackedB.Count -gt 0) -Message "Expected file-backed instances in session B"

$targetIdB = $targetId
$nodeB = Get-NodeById -Tree $treeB -InstanceId $targetIdB
if ($null -eq $nodeB) {
    $targetIdB = [string]$fileBackedB[0]
    $nodeB = Get-NodeById -Tree $treeB -InstanceId $targetIdB
}
Assert-True -Condition ($null -ne $nodeB) -Message "Target node missing in session B"
$sourceB = [string]$nodeB.Properties.Source
Assert-True -Condition ($sourceB.Contains($marker)) -Message "Updated source should persist into session B"

Write-Host "[8/10] restore original Source in session B"
$patchRestore = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionB
    patchId = "integration_roundtrip_restore"
    baseCursor = [string]$treeB.cursor
    origin = "integration-roundtrip-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $targetIdB
            property = "Source"
            value = $originalSource
        }
    )
}
Assert-True -Condition ($patchRestore.accepted -eq $true) -Message "Restore patch should be accepted"

Write-Host "[9/10] verify restore via read in session B"
$treeB2 = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionB; instanceId = $rootB }
$nodeB2 = Get-NodeById -Tree $treeB2 -InstanceId $targetIdB
Assert-True -Condition ($null -ne $nodeB2) -Message "Target node missing after restore"
$restoredSourceB = [string]$nodeB2.Properties.Source
Assert-True -Condition ($restoredSourceB -eq $originalSource) -Message "Source should match original after restore"
$restoreNeeded = $false

Write-Host "[10/10] close session B"
$closedB = Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionB }
Assert-True -Condition ($closedB.closed -eq $true) -Message "Session B should close"

Write-Host "Integration roundtrip contract test completed successfully."
