param(
    [string]$Endpoint = "http://127.0.0.1:44877/mcp",
    [string]$ProjectPath = "src",
    [int]$Iterations = 2
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

function Resolve-TargetFromTree {
    param(
        [Parameter(Mandatory = $true)]$Tree,
        [string]$PreferredId = ""
    )

    $targetId = ""
    $node = $null

    if (-not [string]::IsNullOrWhiteSpace($PreferredId)) {
        $node = Get-NodeById -Tree $Tree -InstanceId $PreferredId
        if ($null -ne $node) {
            return $PreferredId, $node
        }
    }

    $fileBackedIds = @($Tree.fileBackedInstanceIds)
    if ($fileBackedIds.Count -eq 0) {
        throw "Expected at least one file-backed instance"
    }

    $targetId = [string]$fileBackedIds[0]
    $node = Get-NodeById -Tree $Tree -InstanceId $targetId
    if ($null -eq $node) {
        throw "Unable to resolve target file-backed node"
    }

    return $targetId, $node
}

Assert-True -Condition ($Iterations -ge 1) -Message "Iterations must be >= 1"

$sessionA = ""
$sessionB = ""
$rootA = ""
$rootB = ""
$targetId = ""
$originalSource = ""
$restored = $false

Write-Host "[1/9] initialize"
Invoke-Mcp -Method "initialize" -Params @{
    protocolVersion = "2025-11-25"
    capabilities = @{
        resources = @{ subscribe = $true }
        tools = @{}
    }
    clientInfo = @{
        name = "mcp-integration-conflict-recovery-contract-test"
        version = "0.1.0"
    }
} | Out-Null

Write-Host "[2/9] notifications/initialized"
Invoke-Mcp -Method "notifications/initialized" -Params @{} | Out-Null

Write-Host "[3/9] open/read session A"
$openA = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath }
$sessionA = [string]$openA.sessionId
$rootA = [string]$openA.rootInstanceId
$treeA = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionA; instanceId = $rootA }
$targetId, $nodeA = Resolve-TargetFromTree -Tree $treeA
$originalSource = [string]$nodeA.Properties.Source

Write-Host "[4/9] open/read session B"
$openB = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath }
$sessionB = [string]$openB.sessionId
$rootB = [string]$openB.rootInstanceId
$treeB = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionB; instanceId = $rootB }
$targetIdB, $nodeB = Resolve-TargetFromTree -Tree $treeB -PreferredId $targetId
Assert-True -Condition ($null -ne $nodeB) -Message "Session B target node missing"

for ($i = 1; $i -le $Iterations; $i++) {
    Write-Host "[5/9][$i/$Iterations] apply in session A"
    $treeAIter = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionA; instanceId = $rootA }
    $targetId, $nodeAIter = Resolve-TargetFromTree -Tree $treeAIter -PreferredId $targetId
    $baseCursorA = [string]$treeAIter.cursor

    $markerA = "-- integration-conflict-a-" + $i + "-" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")
    $sourceA = $originalSource + "`n" + $markerA
    $patchA = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
        sessionId = $sessionA
        patchId = "integration_conflict_a_" + $i
        baseCursor = $baseCursorA
        origin = "integration-conflict-recovery-contract-test"
        operations = @(
            @{
                op = "setProperty"
                instanceId = $targetId
                property = "Source"
                value = $sourceA
            }
        )
    }
    Assert-True -Condition ($patchA.accepted -eq $true) -Message "Iteration $i session A patch should be accepted"

    Write-Host "[6/9][$i/$Iterations] stale apply in session B (expect conflict)"
    $staleCursorB = [string]$treeB.cursor
    $markerB = "-- integration-conflict-b-" + $i + "-" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")
    $sourceBStale = $originalSource + "`n" + $markerB
    $patchBStale = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
        sessionId = $sessionB
        patchId = "integration_conflict_b_stale_" + $i
        baseCursor = $staleCursorB
        origin = "integration-conflict-recovery-contract-test"
        operations = @(
            @{
                op = "setProperty"
                instanceId = $targetIdB
                property = "Source"
                value = $sourceBStale
            }
        )
    }
    Assert-True -Condition ($patchBStale.accepted -eq $false) -Message "Iteration $i stale session B patch should be rejected"
    $details = @($patchBStale.conflictDetails)
    Assert-True -Condition ($details.Count -gt 0) -Message "Iteration $i stale patch should include conflict details"
    Assert-True -Condition ([string]$details[0].reason -eq "CONFLICT_WRITE_STALE_CURSOR") -Message "Iteration $i expected stale cursor reason"

    Write-Host "[7/9][$i/$Iterations] re-read/reapply in session B (recover)"
    $treeBRecovered = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionB; instanceId = $rootB }
    $targetIdB, $nodeBRecovered = Resolve-TargetFromTree -Tree $treeBRecovered -PreferredId $targetIdB
    $latestSource = [string]$nodeBRecovered.Properties.Source
    Assert-True -Condition ($latestSource.Contains($markerA)) -Message "Iteration $i session B should see session A marker after re-read"

    $recoverySource = $latestSource + "`n" + $markerB
    $patchBRecovered = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
        sessionId = $sessionB
        patchId = "integration_conflict_b_recovered_" + $i
        baseCursor = [string]$treeBRecovered.cursor
        origin = "integration-conflict-recovery-contract-test"
        operations = @(
            @{
                op = "setProperty"
                instanceId = $targetIdB
                property = "Source"
                value = $recoverySource
            }
        )
    }
    Assert-True -Condition ($patchBRecovered.accepted -eq $true) -Message "Iteration $i recovery patch should be accepted"

    $treeAConfirm = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionA; instanceId = $rootA }
    $targetId, $nodeAConfirm = Resolve-TargetFromTree -Tree $treeAConfirm -PreferredId $targetId
    $sourceAConfirm = [string]$nodeAConfirm.Properties.Source
    Assert-True -Condition ($sourceAConfirm.Contains($markerB)) -Message "Iteration $i session A should observe recovered marker from session B"

    $treeB = $treeBRecovered
}

Write-Host "[8/9] restore original source"
$treeRestore = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionA; instanceId = $rootA }
$targetId, $null = Resolve-TargetFromTree -Tree $treeRestore -PreferredId $targetId
$patchRestore = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionA
    patchId = "integration_conflict_restore"
    baseCursor = [string]$treeRestore.cursor
    origin = "integration-conflict-recovery-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $targetId
            property = "Source"
            value = $originalSource
        }
    )
}
Assert-True -Condition ($patchRestore.accepted -eq $true) -Message "Restore patch should be accepted"
$restored = $true

Write-Host "[9/9] close sessions"
if (-not [string]::IsNullOrWhiteSpace($sessionA)) {
    Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionA } | Out-Null
}
if (-not [string]::IsNullOrWhiteSpace($sessionB)) {
    Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionB } | Out-Null
}

Write-Host "Integration conflict-recovery contract test completed successfully."
