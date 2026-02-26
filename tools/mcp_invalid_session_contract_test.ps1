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

    $response = $null
    try {
        $response = Invoke-RestMethod -Uri $Endpoint -Method Post -ContentType "application/json" -Body ($bodyObject | ConvertTo-Json -Depth 30)
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

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
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
    Assert-True -Condition ($ErrCode -eq "SESSION_NOT_FOUND") -Message "$Action should return SESSION_NOT_FOUND error code"
}

Write-Host "[1/7] initialize"
Invoke-Mcp -Method "initialize" -Params @{
    protocolVersion = "2025-11-25"
    capabilities = @{
        resources = @{ subscribe = $true }
        tools = @{}
    }
    clientInfo = @{
        name = "mcp-invalid-session-contract-test"
        version = "0.1.0"
    }
} | Out-Null

Write-Host "[2/7] notifications/initialized"
Invoke-Mcp -Method "notifications/initialized" -Params @{} | Out-Null

Write-Host "[3/7] open session"
$openOk, $open, $openErr, $null = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath }
Assert-True -Condition $openOk -Message ("OpenSession failed: " + $openErr)
$sessionId = [string]$open.sessionId
$root = [string]$open.rootInstanceId

Write-Host "[4/7] close session"
$closeOk, $closed, $closeErr, $null = Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionId }
Assert-True -Condition $closeOk -Message ("closeSession request failed: " + $closeErr)
Assert-True -Condition ($closed.closed -eq $true) -Message "closeSession should close the session"

Write-Host "[5/7] closed-session operations should fail"
$readOk, $null, $readErr, $readErrCode = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionId; instanceId = $root }
Assert-SessionMissing -Ok $readOk -Err $readErr -ErrCode $readErrCode -Action "readTree"

$subOk, $null, $subErr, $subErrCode = Invoke-McpTool -Name "roblox.subscribeChanges" -Arguments @{ sessionId = $sessionId; cursor = "0" }
Assert-SessionMissing -Ok $subOk -Err $subErr -ErrCode $subErrCode -Action "subscribeChanges"

$patchOk, $null, $patchErr, $patchErrCode = Invoke-McpTool -Name "roblox.applyPatch" -Arguments @{
    sessionId = $sessionId
    patchId = "invalid_session_patch"
    baseCursor = "0"
    origin = "invalid-session-contract-test"
    operations = @(
        @{
            op = "setProperty"
            instanceId = $root
            property = "Source"
            value = "-- should fail"
        }
    )
}
Assert-SessionMissing -Ok $patchOk -Err $patchErr -ErrCode $patchErrCode -Action "applyPatch"

Write-Host "[6/7] new session should still open and read"
$open2Ok, $open2, $open2Err, $null = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = $ProjectPath }
Assert-True -Condition $open2Ok -Message ("Second openSession failed: " + $open2Err)

$read2Ok, $tree2, $read2Err, $null = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $open2.sessionId; instanceId = $open2.rootInstanceId }
Assert-True -Condition $read2Ok -Message ("Second readTree failed: " + $read2Err)
Assert-True -Condition ($null -ne $tree2.instances) -Message "Second readTree missing instances"

Write-Host "[7/7] close second session"
Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $open2.sessionId } | Out-Null

Write-Host "Invalid-session contract test completed successfully."
