param(
    [string]$ProjectPath = "default.project.json",
    [string]$McpBase = "http://127.0.0.1:44877",
    [string]$RojoBase = "http://127.0.0.1:34872",
    [string]$ReportPath = "tools/parity_diff_report.json",
    [string]$MutationFilePath = "",
    [string]$MutationMarker = "-- parity-mutation-marker",
    [int]$MutationSettleMs = 1200,
    [string]$FixtureName = "",
    [string]$FixtureCategory = "",
    [switch]$FailOnDiff
)

$ErrorActionPreference = "Stop"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Try-OpenApi {
    param(
        [string]$Base,
        [string]$ProjectPath,
        [switch]$PreferPost
    )

    $attempts = @()
    if ($PreferPost) {
        $attempts += "POST"
        $attempts += "GET"
    }
    else {
        $attempts += "GET"
        $attempts += "POST"
    }

    foreach ($method in $attempts) {
        try {
            if ($method -eq "POST") {
                $open = Invoke-RestMethod -Uri "$Base/api/rojo" -Method Post -ContentType 'application/json' -Body (@{ projectPath = $ProjectPath } | ConvertTo-Json)
                if ($open) {
                    return $open
                }
            }
            else {
                $open = Invoke-RestMethod -Uri "$Base/api/rojo" -Method Get
                if ($open) {
                    return $open
                }
            }
        }
        catch {
        }
    }

    throw "Unable to open session via $Base/api/rojo"
}

function Invoke-ReadCompat {
    param(
        [string]$Base,
        [string]$SessionId,
        [string]$RootId
    )

    $urls = @()
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $urls += "$Base/api/read/$SessionId/$RootId"
        $urls += "$Base/api/read/$RootId?sessionId=$SessionId"
    }
    $urls += "$Base/api/read/$RootId"

    foreach ($url in $urls) {
        try {
            return Invoke-RestMethod -Uri $url -Method Get
        }
        catch {
        }
    }

    throw "Unable to read tree from $Base"
}

function Invoke-SubscribeCompat {
    param(
        [string]$Base,
        [string]$SessionId,
        [string]$Cursor
    )

    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        return $null
    }

    $cursorValue = if ([string]::IsNullOrWhiteSpace($Cursor)) { "0" } else { $Cursor }
    $urls = @(
        "$Base/api/subscribe/$SessionId/$cursorValue",
        "$Base/api/subscribe/$SessionId"
    )

    foreach ($url in $urls) {
        try {
            return Invoke-RestMethod -Uri $url -Method Get
        }
        catch {
        }
    }

    return $null
}

function Get-InstanceList {
    param($Instances)

    if ($null -eq $Instances) {
        return @()
    }

    if ($Instances -is [System.Array]) {
        return @($Instances)
    }

    if ($Instances.PSObject -and $Instances.PSObject.Properties) {
        $list = @()
        foreach ($prop in $Instances.PSObject.Properties) {
            $list += $prop.Value
        }
        return $list
    }

    return @()
}

function Summarize-ReadPayload {
    param($Read)

    $nodes = Get-InstanceList -Instances $Read.instances
    $classHistogram = @{}
    $sourceNodeCount = 0
    $nameClassPairs = New-Object System.Collections.Generic.List[string]

    foreach ($node in $nodes) {
        $className = ""
        if ($node.PSObject.Properties["ClassName"]) {
            $className = [string]$node.ClassName
        }

        if ([string]::IsNullOrWhiteSpace($className)) {
            $className = "<unknown>"
        }

        if (-not $classHistogram.ContainsKey($className)) {
            $classHistogram[$className] = 0
        }
        $classHistogram[$className] += 1

        $name = if ($node.PSObject.Properties["Name"]) { [string]$node.Name } else { "" }
        $nameClassPairs.Add("$name|$className") | Out-Null

        if ($node.PSObject.Properties["Properties"] -and $node.Properties -and $node.Properties.PSObject.Properties["Source"]) {
            $sourceNodeCount += 1
        }
    }

    $pairsUnique = @($nameClassPairs | Sort-Object -Unique)
    $classSummary = @{}
    foreach ($key in ($classHistogram.Keys | Sort-Object)) {
        $classSummary[$key] = $classHistogram[$key]
    }

    return [ordered]@{
        cursor = ("" + $Read.cursor)
        instanceCount = $nodes.Count
        sourceNodeCount = $sourceNodeCount
        classHistogram = $classSummary
        uniqueNameClassCount = $pairsUnique.Count
    }
}

function Summarize-SubscribePayload {
    param($Sub)

    if ($null -eq $Sub) {
        return [ordered]@{
            available = $false
        }
    }

    $addedCount = 0
    if ($Sub.PSObject.Properties["added"] -and $Sub.added -and $Sub.added.PSObject.Properties) {
        $addedCount = @($Sub.added.PSObject.Properties).Count
    }

    return [ordered]@{
        available = $true
        cursor = ("" + $Sub.cursor)
        addedCount = $addedCount
        updatedCount = @($Sub.updated).Count
        removedCount = @($Sub.removed).Count
    }
}

function Compare-Hash {
    param(
        [hashtable]$Left,
        [hashtable]$Right,
        [string]$Prefix
    )

    $diffs = New-Object System.Collections.Generic.List[string]
    $allKeys = @($Left.Keys + $Right.Keys | Sort-Object -Unique)
    foreach ($key in $allKeys) {
        $leftHas = $Left.ContainsKey($key)
        $rightHas = $Right.ContainsKey($key)
        if (-not $leftHas -or -not $rightHas) {
            $diffs.Add("$Prefix$key presence mismatch (mcp=$leftHas rojo=$rightHas)") | Out-Null
            continue
        }

        $leftVal = $Left[$key]
        $rightVal = $Right[$key]
        if ("$leftVal" -ne "$rightVal") {
            $diffs.Add("$Prefix$key mismatch (mcp=$leftVal rojo=$rightVal)") | Out-Null
        }
    }

    return $diffs
}

function Compare-SubscribeSummary {
    param(
        $Left,
        $Right,
        [string]$Prefix
    )

    $diffs = New-Object System.Collections.Generic.List[string]

    if ($Left.available -and $Right.available) {
        if ($Left.addedCount -ne $Right.addedCount) {
            $diffs.Add("$Prefix.addedCount mismatch (mcp=$($Left.addedCount) rojo=$($Right.addedCount))") | Out-Null
        }
        if ($Left.updatedCount -ne $Right.updatedCount) {
            $diffs.Add("$Prefix.updatedCount mismatch (mcp=$($Left.updatedCount) rojo=$($Right.updatedCount))") | Out-Null
        }
        if ($Left.removedCount -ne $Right.removedCount) {
            $diffs.Add("$Prefix.removedCount mismatch (mcp=$($Left.removedCount) rojo=$($Right.removedCount))") | Out-Null
        }
    }
    return $diffs
}

function Try-ParseInt64 {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $parsed = 0
    if ([Int64]::TryParse($Value, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

$mcpOpen = Try-OpenApi -Base $McpBase -ProjectPath $ProjectPath -PreferPost
$rojoOpen = Try-OpenApi -Base $RojoBase -ProjectPath $ProjectPath

$mcpSession = [string]$mcpOpen.sessionId
$rojoSession = [string]$rojoOpen.sessionId

$mcpRoot = [string]$mcpOpen.rootInstanceId
$rojoRoot = [string]$rojoOpen.rootInstanceId

Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($mcpRoot)) -Message "MCP open response missing rootInstanceId"
Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($rojoRoot)) -Message "Rojo open response missing rootInstanceId"

$mcpRead = Invoke-ReadCompat -Base $McpBase -SessionId $mcpSession -RootId $mcpRoot
$rojoRead = Invoke-ReadCompat -Base $RojoBase -SessionId $rojoSession -RootId $rojoRoot

$mcpSub = Invoke-SubscribeCompat -Base $McpBase -SessionId $mcpSession -Cursor "0"
$rojoSub = Invoke-SubscribeCompat -Base $RojoBase -SessionId $rojoSession -Cursor "0"

$mcpReadSummary = Summarize-ReadPayload -Read $mcpRead
$rojoReadSummary = Summarize-ReadPayload -Read $rojoRead
$mcpSubSummary = Summarize-SubscribePayload -Sub $mcpSub
$rojoSubSummary = Summarize-SubscribePayload -Sub $rojoSub

$mutationSummary = [ordered]@{
    enabled = -not [string]::IsNullOrWhiteSpace($MutationFilePath)
    attempted = $false
    applied = $false
    restored = $false
    filePath = $MutationFilePath
    mcp = $null
    rojo = $null
}

$diffs = New-Object System.Collections.Generic.List[string]

if ($mcpReadSummary.instanceCount -ne $rojoReadSummary.instanceCount) {
    $diffs.Add("read.instanceCount mismatch (mcp=$($mcpReadSummary.instanceCount) rojo=$($rojoReadSummary.instanceCount))") | Out-Null
}

if ($mcpReadSummary.sourceNodeCount -ne $rojoReadSummary.sourceNodeCount) {
    $diffs.Add("read.sourceNodeCount mismatch (mcp=$($mcpReadSummary.sourceNodeCount) rojo=$($rojoReadSummary.sourceNodeCount))") | Out-Null
}

if ($mcpReadSummary.uniqueNameClassCount -ne $rojoReadSummary.uniqueNameClassCount) {
    $diffs.Add("read.uniqueNameClassCount mismatch (mcp=$($mcpReadSummary.uniqueNameClassCount) rojo=$($rojoReadSummary.uniqueNameClassCount))") | Out-Null
}

foreach ($entry in (Compare-Hash -Left $mcpReadSummary.classHistogram -Right $rojoReadSummary.classHistogram -Prefix "read.classHistogram.")) {
    $diffs.Add($entry) | Out-Null
}

foreach ($entry in (Compare-SubscribeSummary -Left $mcpSubSummary -Right $rojoSubSummary -Prefix "subscribe")) {
    $diffs.Add($entry) | Out-Null
}

if ($mcpSubSummary.available) {
    $mcpReadCursor = Try-ParseInt64 -Value ("" + $mcpReadSummary.cursor)
    $mcpSubCursor = Try-ParseInt64 -Value ("" + $mcpSubSummary.cursor)
    if ($null -eq $mcpSubCursor) {
        $diffs.Add("mcp.subscribe.cursor is not a valid integer (value=$($mcpSubSummary.cursor))") | Out-Null
    }
    elseif ($null -ne $mcpReadCursor -and $mcpSubCursor -lt $mcpReadCursor) {
        $diffs.Add("mcp.subscribe.cursor regressed (read=$mcpReadCursor subscribe=$mcpSubCursor)") | Out-Null
    }
}

if ($rojoSubSummary.available) {
    $rojoReadCursor = Try-ParseInt64 -Value ("" + $rojoReadSummary.cursor)
    $rojoSubCursor = Try-ParseInt64 -Value ("" + $rojoSubSummary.cursor)
    if ($null -eq $rojoSubCursor) {
        $diffs.Add("rojo.subscribe.cursor is not a valid integer (value=$($rojoSubSummary.cursor))") | Out-Null
    }
    elseif ($null -ne $rojoReadCursor -and $rojoSubCursor -lt $rojoReadCursor) {
        $diffs.Add("rojo.subscribe.cursor regressed (read=$rojoReadCursor subscribe=$rojoSubCursor)") | Out-Null
    }
}

if ($mutationSummary.enabled) {
    $workspace = Split-Path -Parent $PSScriptRoot
    $mutationFullPath = Join-Path $workspace $MutationFilePath
    Assert-True -Condition (Test-Path $mutationFullPath) -Message "Mutation file not found: $mutationFullPath"

    $mutationSummary.attempted = $true
    $backupPath = "$mutationFullPath.parity_tmp_backup"
    Copy-Item -Path $mutationFullPath -Destination $backupPath -Force
    $timestampTag = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")
    $appendLine = "$MutationMarker $timestampTag"

    try {
        Add-Content -Path $mutationFullPath -Value ("`r`n" + $appendLine)
        $mutationSummary.applied = $true

        Start-Sleep -Milliseconds $MutationSettleMs

        $mcpMutationSub = Invoke-SubscribeCompat -Base $McpBase -SessionId $mcpSession -Cursor $mcpReadSummary.cursor
        $rojoMutationSub = Invoke-SubscribeCompat -Base $RojoBase -SessionId $rojoSession -Cursor $rojoReadSummary.cursor

        $mcpMutationSummary = Summarize-SubscribePayload -Sub $mcpMutationSub
        $rojoMutationSummary = Summarize-SubscribePayload -Sub $rojoMutationSub

        $mutationSummary.mcp = $mcpMutationSummary
        $mutationSummary.rojo = $rojoMutationSummary

        foreach ($entry in (Compare-SubscribeSummary -Left $mcpMutationSummary -Right $rojoMutationSummary -Prefix "mutation.subscribe")) {
            $diffs.Add($entry) | Out-Null
        }

        if ($mcpMutationSummary.available) {
            $mcpBaseCursor = Try-ParseInt64 -Value ("" + $mcpReadSummary.cursor)
            $mcpMutationCursor = Try-ParseInt64 -Value ("" + $mcpMutationSummary.cursor)
            if ($null -eq $mcpMutationCursor) {
                $diffs.Add("mcp.mutation.subscribe.cursor is not a valid integer (value=$($mcpMutationSummary.cursor))") | Out-Null
            }
            elseif ($null -ne $mcpBaseCursor -and $mcpMutationCursor -lt $mcpBaseCursor) {
                $diffs.Add("mcp.mutation.subscribe.cursor regressed (base=$mcpBaseCursor mutation=$mcpMutationCursor)") | Out-Null
            }
        }

        if ($rojoMutationSummary.available) {
            $rojoBaseCursor = Try-ParseInt64 -Value ("" + $rojoReadSummary.cursor)
            $rojoMutationCursor = Try-ParseInt64 -Value ("" + $rojoMutationSummary.cursor)
            if ($null -eq $rojoMutationCursor) {
                $diffs.Add("rojo.mutation.subscribe.cursor is not a valid integer (value=$($rojoMutationSummary.cursor))") | Out-Null
            }
            elseif ($null -ne $rojoBaseCursor -and $rojoMutationCursor -lt $rojoBaseCursor) {
                $diffs.Add("rojo.mutation.subscribe.cursor regressed (base=$rojoBaseCursor mutation=$rojoMutationCursor)") | Out-Null
            }
        }
    }
    finally {
        if (Test-Path $backupPath) {
            Move-Item -Path $backupPath -Destination $mutationFullPath -Force
        }
        $mutationSummary.restored = $true
    }
}

$report = [ordered]@{
    timestampUtc = (Get-Date).ToUniversalTime().ToString("o")
    fixture = [ordered]@{
        name = $FixtureName
        category = $FixtureCategory
    }
    projectPath = $ProjectPath
    mcpBase = $McpBase
    rojoBase = $RojoBase
    compared = [ordered]@{
        open = [ordered]@{
            mcpRootInstanceId = $mcpRoot
            rojoRootInstanceId = $rojoRoot
            mcpHasSessionId = -not [string]::IsNullOrWhiteSpace($mcpSession)
            rojoHasSessionId = -not [string]::IsNullOrWhiteSpace($rojoSession)
        }
        readSummary = [ordered]@{
            mcp = $mcpReadSummary
            rojo = $rojoReadSummary
        }
        subscribeSummary = [ordered]@{
            mcp = $mcpSubSummary
            rojo = $rojoSubSummary
        }
        mutationSummary = $mutationSummary
    }
    diffCount = $diffs.Count
    diffs = @($diffs)
}
$workspace = Split-Path -Parent $PSScriptRoot
$fullReportPath = Join-Path $workspace $ReportPath
$reportDir = Split-Path -Parent $fullReportPath
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$report | ConvertTo-Json -Depth 20 | Set-Content -Path $fullReportPath

Write-Output ("reportPath={0}" -f $fullReportPath)
Write-Output ("diffCount={0}" -f $diffs.Count)

if ($diffs.Count -gt 0) {
    Write-Output "diffs:"
    foreach ($line in $diffs) {
        Write-Output ("- {0}" -f $line)
    }

    if ($FailOnDiff) {
        throw "Parity diff detected ($($diffs.Count) difference(s))."
    }
}
else {
    Write-Output "No parity diffs detected for compared summaries."
}
