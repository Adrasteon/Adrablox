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
$init = Invoke-Mcp -Method "initialize" -Params @{
    protocolVersion = "2025-11-25"
    capabilities = @{
        resources = @{ subscribe = $true }
        tools = @{}
    }
    clientInfo = @{
        name = "mcp-policy-contract-test"
        version = "0.1.0"
    }
}
Write-Host "  protocolVersion=$($init.protocolVersion)"

Write-Host "[2/8] notifications/initialized"
Invoke-Mcp -Method "notifications/initialized" -Params @{} | Out-Null

Write-Host "[3/8] roblox.openSession"
$open = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath }
$sessionId = [string]$open.sessionId
$rootInstanceId = [string]$open.rootInstanceId
Write-Host "  sessionId=$sessionId root=$rootInstanceId"

$cap = $open.sessionCapabilities
Assert-True -Condition ($null -ne $cap) -Message "openSession must include sessionCapabilities"
Assert-True -Condition ($cap.supportsStructuralOps -eq $false) -Message "supportsStructuralOps must be false"
Assert-True -Condition ($cap.fileBackedMutationPolicy.allowSetName -eq $false) -Message "allowSetName must be false"
Assert-True -Condition (@($cap.fileBackedMutationPolicy.allowedSetProperty) -contains "Source") -Message "allowedSetProperty must include Source"

Write-Host "[4/8] roblox.readTree"
$tree = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionId; instanceId = $rootInstanceId }
$fileBackedIds = @($tree.fileBackedInstanceIds)
Assert-True -Condition ($fileBackedIds.Count -gt 0) -Message "readTree should expose fileBackedInstanceIds"
$targetId = [string]$fileBackedIds[0]

$instanceNode = $tree.instances.PSObject.Properties[$targetId].Value
Assert-True -Condition ($null -ne $instanceNode) -Message "target file-backed instance must exist in tree"
$originalName = [string]$instanceNode.Name
$originalSource = [string]$instanceNode.Properties.Source

Write-Host "  fileBackedTarget=$targetId"

Write-Host "[5/8] applyPatch setName should be rejected"
$renamePatch = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "policy_rename_reject"
    baseCursor = [string]$tree.cursor
    origin = "policy-contract-test"
    operations = @(
        @{
            op = "setName"
            instanceId = $targetId
            name = "$originalName`_Renamed"
        }
    )
}
Assert-True -Condition ($renamePatch.accepted -eq $false) -Message "setName on file-backed instance must be rejected"
Assert-True -Condition (@($renamePatch.conflictDetails).Count -gt 0) -Message "setName rejection should include conflict details"
Assert-True -Condition (@($renamePatch.conflictDetails | Where-Object { $_.reason -eq 'UNSUPPORTED_FILE_BACKED_MUTATION' }).Count -gt 0) -Message "setName rejection should use UNSUPPORTED_FILE_BACKED_MUTATION"

Write-Host "[6/8] applyPatch non-Source property should be rejected"
$nonSourcePatch = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "policy_nonsource_reject"
    baseCursor = [string]$tree.cursor
    origin = "policy-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $targetId
            property = "Disabled"
            value = $false
        }
    )
}
Assert-True -Condition ($nonSourcePatch.accepted -eq $false) -Message "non-Source setProperty on file-backed instance must be rejected"
Assert-True -Condition (@($nonSourcePatch.conflictDetails | Where-Object { $_.reason -eq 'UNSUPPORTED_FILE_BACKED_MUTATION' }).Count -gt 0) -Message "non-Source rejection should use UNSUPPORTED_FILE_BACKED_MUTATION"

Write-Host "[7/8] applyPatch Source should be accepted + restore"
$updatedSource = $originalSource + "`n-- policy-contract-test"
$sourcePatch = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "policy_source_accept"
    baseCursor = [string]$tree.cursor
    origin = "policy-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $targetId
            property = "Source"
            value = $updatedSource
        }
    )
}
Assert-True -Condition ($sourcePatch.accepted -eq $true) -Message "Source setProperty on file-backed instance must be accepted"

$restorePatch = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "policy_source_restore"
    baseCursor = [string]$sourcePatch.appliedCursor
    origin = "policy-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $targetId
            property = "Source"
            value = $originalSource
        }
    )
}
Assert-True -Condition ($restorePatch.accepted -eq $true) -Message "Source restore must be accepted"

Write-Host "[8/8] roblox.closeSession"
$closed = Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionId }
Assert-True -Condition ($closed.closed -eq $true) -Message "session should close"

Write-Host "Policy contract test completed successfully."
