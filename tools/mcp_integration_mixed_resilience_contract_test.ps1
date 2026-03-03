param(
    [string]$Endpoint = "http://127.0.0.1:44877/mcp",
    [string]$ProjectPath = "adrablox.project.json",
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

    $response = $null
    try {
        $response = Invoke-RestMethod -Uri $Endpoint -Method Post -ContentType "application/json" -Body ($bodyObject | ConvertTo-Json -Depth 40)
    }
    catch {
        $errorBody = $_.ErrorDetails.Message
        if ([string]::IsNullOrWhiteSpace($errorBody)) {
            throw
        }

        $decoded = $null
        try {
            $decoded = $errorBody | ConvertFrom-Json
        }
        catch {
            throw
        }

        if ($null -ne $decoded.error) {
            $errCode = $null
            if ($null -ne $decoded.error.data -and $null -ne $decoded.error.data.code) {
                $errCode = ("" + $decoded.error.data.code)
            }
            return $false, $null, ($decoded.error.message | Out-String).Trim(), $errCode
        }

        throw
    }

    if ($null -ne $response.error) {
        $errCode = $null
        if ($null -ne $response.error.data -and $null -ne $response.error.data.code) {
            $errCode = ("" + $response.error.data.code)
        }
        return $false, $null, ($response.error.message | Out-String).Trim(), $errCode
    }

    return $true, $response.result, $null, $null
}

function Invoke-McpTool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)]$Arguments = @{}
    )

    $ok, $result, $err, $errCode = Invoke-Mcp -Method "tools/call" -Params @{
        name = $Name
        arguments = $Arguments
    }

    if (-not $ok) {
        return $false, $null, $err, $errCode
    }

    $structured = $null
    if ($null -ne $result) {
        $structured = $result.structuredContent
    }
    if ($null -eq $structured) {
        return $false, $null, "missing structuredContent in tool response", $null
    }

    return $true, $structured, $null, $null
}

function Invoke-McpToolOrThrow {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)]$Arguments = @{},
        [Parameter(Mandatory = $true)][string]$Message
    )

    $ok, $result, $err, $errCode = Invoke-McpTool -Name $Name -Arguments $Arguments
    if (-not $ok) {
        throw "${Message}: $err (code=$errCode)"
    }

    return $result
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

    if (-not [string]::IsNullOrWhiteSpace($PreferredId)) {
        $preferredNode = Get-NodeById -Tree $Tree -InstanceId $PreferredId
        if ($null -ne $preferredNode) {
            return $PreferredId, $preferredNode
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

function Assert-SessionMissing {
    param(
        [Parameter(Mandatory = $true)][bool]$Ok,
        [Parameter(Mandatory = $true)][string]$Err,
        [Parameter(Mandatory = $false)][string]$ErrCode,
        [Parameter(Mandatory = $true)][string]$Action
    )

    Assert-True -Condition (-not $Ok) -Message "$Action should fail for closed session"
    $text = ("" + $Err).ToLowerInvariant()
    Assert-True -Condition ($text.Contains("session does not exist")) -Message "$Action should return session does not exist error"
    Assert-True -Condition ($ErrCode -eq "SESSION_NOT_FOUND") -Message "$Action should return SESSION_NOT_FOUND"
}

Assert-True -Condition ($Iterations -ge 1) -Message "Iterations must be >= 1"

Write-Host "[1/4] initialize"
Invoke-Mcp -Method "initialize" -Params @{
    protocolVersion = "2025-11-25"
    capabilities = @{
        resources = @{ subscribe = $true }
        tools = @{}
    }
    clientInfo = @{
        name = "mcp-integration-mixed-resilience-contract-test"
        version = "0.1.0"
    }
} | Out-Null

Write-Host "[2/4] notifications/initialized"
Invoke-Mcp -Method "notifications/initialized" -Params @{} | Out-Null

$originalSource = ""
$targetId = ""

for ($i = 1; $i -le $Iterations; $i++) {
    Write-Host "[3/4][$i/$Iterations] mixed scenario: conflict + invalid-session recovery"

    $sessionA = ""
    $sessionB = ""
    $sessionC = ""
    $rootA = ""
    $rootB = ""
    $rootC = ""
    $restoredThisIteration = $false

    try {
        $openA = Invoke-McpToolOrThrow -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath } -Message "openSession A failed"
        $sessionA = [string]$openA.sessionId
        $rootA = [string]$openA.rootInstanceId
        $treeA = Invoke-McpToolOrThrow -Name "roblox.readTree" -Arguments @{ sessionId = $sessionA; instanceId = $rootA } -Message "readTree A failed"
        $targetId, $nodeA = Resolve-TargetFromTree -Tree $treeA -PreferredId $targetId
        $originalSource = [string]$nodeA.Properties.Source

        $openB = Invoke-McpToolOrThrow -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath } -Message "openSession B failed"
        $sessionB = [string]$openB.sessionId
        $rootB = [string]$openB.rootInstanceId
        $treeB = Invoke-McpToolOrThrow -Name "roblox.readTree" -Arguments @{ sessionId = $sessionB; instanceId = $rootB } -Message "readTree B failed"
        $targetIdB, $nodeB = Resolve-TargetFromTree -Tree $treeB -PreferredId $targetId
        Assert-True -Condition ($null -ne $nodeB) -Message "Session B target missing"

        $markerA = "-- integration-mixed-a-" + $i + "-" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")
        $markerB = "-- integration-mixed-b-" + $i + "-" + (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")

        $patchA = Invoke-McpToolOrThrow -Name "roblox.applyPatch" -Arguments @{
            sessionId = $sessionA
            patchId = "integration_mixed_a_" + $i
            baseCursor = [string]$treeA.cursor
            origin = "integration-mixed-resilience-contract-test"
            operations = @(
                @{
                    op = "setProperty"
                    instanceId = $targetId
                    property = "Source"
                    value = ($originalSource + "`n" + $markerA)
                }
            )
        } -Message "Session A patch failed"
        Assert-True -Condition ($patchA.accepted -eq $true) -Message "Session A patch should be accepted"

        $patchBStaleOk, $patchBStale, $patchBErr, $patchBErrCode = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
            sessionId = $sessionB
            patchId = "integration_mixed_b_stale_" + $i
            baseCursor = [string]$treeB.cursor
            origin = "integration-mixed-resilience-contract-test"
            operations = @(
                @{
                    op = "setProperty"
                    instanceId = $targetIdB
                    property = "Source"
                    value = ($originalSource + "`n" + $markerB)
                }
            )
        }
        if (-not $patchBStaleOk) {
            throw "Stale patch request failed unexpectedly: $patchBErr (code=$patchBErrCode)"
        }
        Assert-True -Condition ($patchBStale.accepted -eq $false) -Message "Stale session B patch should be rejected"
        $details = @($patchBStale.conflictDetails)
        Assert-True -Condition ($details.Count -gt 0) -Message "Stale conflict should include conflict details"
        Assert-True -Condition ([string]$details[0].reason -eq "CONFLICT_WRITE_STALE_CURSOR") -Message "Expected stale cursor conflict reason"

        $closeA = Invoke-McpToolOrThrow -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionA } -Message "closeSession A failed"
        Assert-True -Condition ($closeA.closed -eq $true) -Message "Session A should close"

        $readAOk, $null, $readAErr, $readAErrCode = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionA; instanceId = $rootA }
        Assert-SessionMissing -Ok $readAOk -Err $readAErr -ErrCode $readAErrCode -Action "readTree on closed session A"

        if ($sessionA -eq $sessionB) {
            $openBRecovery = Invoke-McpToolOrThrow -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath } -Message "openSession B recovery failed"
            $sessionB = [string]$openBRecovery.sessionId
            $rootB = [string]$openBRecovery.rootInstanceId
        }

        $treeBRecovered = Invoke-McpToolOrThrow -Name "roblox.readTree" -Arguments @{ sessionId = $sessionB; instanceId = $rootB } -Message "readTree B recovery failed"
        $targetIdB, $nodeBRecovered = Resolve-TargetFromTree -Tree $treeBRecovered -PreferredId $targetIdB
        $latestSource = [string]$nodeBRecovered.Properties.Source
        Assert-True -Condition ($latestSource.Contains($markerA)) -Message "Session B should observe marker A after re-read"

        $patchBRecovered = Invoke-McpToolOrThrow -Name "roblox.applyPatch" -Arguments @{
            sessionId = $sessionB
            patchId = "integration_mixed_b_recovered_" + $i
            baseCursor = [string]$treeBRecovered.cursor
            origin = "integration-mixed-resilience-contract-test"
            operations = @(
                @{
                    op = "setProperty"
                    instanceId = $targetIdB
                    property = "Source"
                    value = ($latestSource + "`n" + $markerB)
                }
            )
        } -Message "Session B recovered patch failed"
        Assert-True -Condition ($patchBRecovered.accepted -eq $true) -Message "Recovered session B patch should be accepted"

        $closeB = Invoke-McpToolOrThrow -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionB } -Message "closeSession B failed"
        Assert-True -Condition ($closeB.closed -eq $true) -Message "Session B should close"

        $openC = Invoke-McpToolOrThrow -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath } -Message "openSession C failed"
        $sessionC = [string]$openC.sessionId
        $rootC = [string]$openC.rootInstanceId
        $treeC = Invoke-McpToolOrThrow -Name "roblox.readTree" -Arguments @{ sessionId = $sessionC; instanceId = $rootC } -Message "readTree C failed"
        $targetIdC, $nodeC = Resolve-TargetFromTree -Tree $treeC -PreferredId $targetId
        $sourceC = [string]$nodeC.Properties.Source
        Assert-True -Condition ($sourceC.Contains($markerA)) -Message "Session C should contain marker A"
        Assert-True -Condition ($sourceC.Contains($markerB)) -Message "Session C should contain marker B"

        $restorePatch = Invoke-McpToolOrThrow -Name "roblox.applyPatch" -Arguments @{
            sessionId = $sessionC
            patchId = "integration_mixed_restore_" + $i
            baseCursor = [string]$treeC.cursor
            origin = "integration-mixed-resilience-contract-test"
            operations = @(
                @{
                    op = "setProperty"
                    instanceId = $targetIdC
                    property = "Source"
                    value = $originalSource
                }
            )
        } -Message "Restore patch failed"
        Assert-True -Condition ($restorePatch.accepted -eq $true) -Message "Restore patch should be accepted"
        $restoredThisIteration = $true
    }
    finally {
        if (-not $restoredThisIteration -and -not [string]::IsNullOrWhiteSpace($originalSource)) {
            try {
                $recoverySession = Invoke-McpToolOrThrow -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath } -Message "Recovery openSession failed"
                $recoveryId = [string]$recoverySession.sessionId
                $recoveryRoot = [string]$recoverySession.rootInstanceId
                $recoveryTree = Invoke-McpToolOrThrow -Name "roblox.readTree" -Arguments @{ sessionId = $recoveryId; instanceId = $recoveryRoot } -Message "Recovery readTree failed"
                $recoveryTargetId, $null = Resolve-TargetFromTree -Tree $recoveryTree -PreferredId $targetId
                Invoke-McpToolOrThrow -Name "roblox.applyPatch" -Arguments @{
                    sessionId = $recoveryId
                    patchId = "integration_mixed_emergency_restore_" + $i
                    baseCursor = [string]$recoveryTree.cursor
                    origin = "integration-mixed-resilience-contract-test"
                    operations = @(
                        @{
                            op = "setProperty"
                            instanceId = $recoveryTargetId
                            property = "Source"
                            value = $originalSource
                        }
                    )
                } -Message "Emergency restore patch failed" | Out-Null
                Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $recoveryId } | Out-Null
            }
            catch {
                Write-Host "Emergency restore failed: $($_.Exception.Message)"
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($sessionA)) {
            try { Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionA } | Out-Null } catch {}
        }
        if (-not [string]::IsNullOrWhiteSpace($sessionB)) {
            try { Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionB } | Out-Null } catch {}
        }
        if (-not [string]::IsNullOrWhiteSpace($sessionC)) {
            try { Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionC } | Out-Null } catch {}
        }
    }
}

Write-Host "[4/4] completed"
Write-Host "Integration mixed resilience contract test completed successfully."
