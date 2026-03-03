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

Write-Host "[1/7] initialize"
Invoke-Mcp -Method "initialize" -Params @{
    protocolVersion = "2025-11-25"
    capabilities = @{
        resources = @{ subscribe = $true }
        tools = @{}
    }
    clientInfo = @{
        name = "mcp-conflict-race-contract-test"
        version = "0.1.0"
    }
} | Out-Null

Write-Host "[2/7] notifications/initialized"
Invoke-Mcp -Method "notifications/initialized" -Params @{} | Out-Null

Write-Host "[3/7] open + read"
$open = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath }
$sessionId = [string]$open.sessionId
$rootInstanceId = [string]$open.rootInstanceId

$tree = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionId; instanceId = $rootInstanceId }
$baseCursor = [string]$tree.cursor
$fileBackedIds = @($tree.fileBackedInstanceIds)
Assert-True -Condition ($fileBackedIds.Count -gt 0) -Message "Expected at least one file-backed instance"
$targetId = [string]$fileBackedIds[0]

$instanceNode = $tree.instances.PSObject.Properties[$targetId].Value
Assert-True -Condition ($null -ne $instanceNode) -Message "Target file-backed instance not found in readTree"
$originalSource = [string]$instanceNode.Properties.Source

Write-Host "  sessionId=$sessionId targetId=$targetId baseCursor=$baseCursor"

Write-Host "[4/7] apply first Source patch at base cursor"
$firstSource = $originalSource + "`n-- conflict-race-first"
$patch1 = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "race_first"
    baseCursor = $baseCursor
    origin = "conflict-race-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $targetId
            property = "Source"
            value = $firstSource
        }
    )
}
Assert-True -Condition ($patch1.accepted -eq $true) -Message "First patch should be accepted"
$patch1Cursor = [string]$patch1.appliedCursor

Write-Host "[5/7] apply second Source patch with stale base cursor"
$secondSource = $originalSource + "`n-- conflict-race-second"
$patch2 = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "race_second_stale"
    baseCursor = $baseCursor
    origin = "conflict-race-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $targetId
            property = "Source"
            value = $secondSource
        }
    )
}

Assert-True -Condition ($patch2.accepted -eq $false) -Message "Stale-base second patch should be rejected"
$details = @($patch2.conflictDetails)
Assert-True -Condition ($details.Count -gt 0) -Message "Stale-base conflict should include conflictDetails"
Assert-True -Condition ($details[0].reason -eq "CONFLICT_WRITE_STALE_CURSOR") -Message "Expected CONFLICT_WRITE_STALE_CURSOR reason for stale base"

Write-Host "[6/7] restore original Source"
$restore = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "race_restore"
    baseCursor = $patch1Cursor
    origin = "conflict-race-contract-test"
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

Write-Host "[7/7] closeSession"
$closed = Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionId }
Assert-True -Condition ($closed.closed -eq $true) -Message "Session should close"

Write-Host "Conflict race contract test completed successfully."
