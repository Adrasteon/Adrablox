$ErrorActionPreference = 'Stop'
$base = 'http://127.0.0.1:44877'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-SubscribeCounts {
    param($SubscribeResponse)

    return @{
        Added = @($SubscribeResponse.added.PSObject.Properties).Count
        Updated = @($SubscribeResponse.updated).Count
        Removed = @($SubscribeResponse.removed).Count
        Cursor = [string]$SubscribeResponse.cursor
    }
}

$workspace = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $workspace 'src'

Assert-True -Condition (Test-Path $srcRoot) -Message 'src folder does not exist'

$targetFile = Join-Path $srcRoot 'App.module.lua'
if (-not (Test-Path $targetFile)) {
    $targetFile = Get-ChildItem -Path $srcRoot -Recurse -File -Include *.lua,*.luau | Select-Object -First 1 -ExpandProperty FullName
}
Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($targetFile)) -Message 'No .lua/.luau script found under src'

$marker = [Guid]::NewGuid().ToString('N')
$addedFile = Join-Path $srcRoot "__parity_added_$marker.module.lua"
$renamedFile = Join-Path $srcRoot "__parity_renamed_$marker.module.lua"

$originalSource = Get-Content -Raw -Path $targetFile

try {
    $open = Invoke-RestMethod -Uri "$base/api/rojo" -Method Post -ContentType 'application/json' -Body (@{ projectPath = 'src' } | ConvertTo-Json)
    $sessionId = [string]$open.sessionId
    $root = [string]$open.rootInstanceId

    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($sessionId)) -Message 'openSession did not return sessionId'
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($root)) -Message 'openSession did not return rootInstanceId'

    $read = Invoke-RestMethod -Uri "$base/api/read/$sessionId/$root" -Method Get
    $cursor = [string]$read.cursor

    Write-Output ("sessionId={0}" -f $sessionId)
    Write-Output ("initialCursor={0}" -f $cursor)

    Set-Content -Path $targetFile -Value ($originalSource + "`n-- parity-update-$marker") -NoNewline
    Start-Sleep -Milliseconds 400
    $subUpdate = Invoke-RestMethod -Uri "$base/api/subscribe/$sessionId/$cursor" -Method Get
    $updateCounts = Get-SubscribeCounts -SubscribeResponse $subUpdate
    Assert-True -Condition ($updateCounts.Updated -gt 0) -Message 'Expected update changefeed event after source edit'
    $cursor = $updateCounts.Cursor
    Write-Output ("afterUpdate added={0} updated={1} removed={2} cursor={3}" -f $updateCounts.Added, $updateCounts.Updated, $updateCounts.Removed, $cursor)

    Set-Content -Path $addedFile -Value ("return { tag = 'added-$marker' }") -NoNewline
    Start-Sleep -Milliseconds 400
    $subAdd = Invoke-RestMethod -Uri "$base/api/subscribe/$sessionId/$cursor" -Method Get
    $addCounts = Get-SubscribeCounts -SubscribeResponse $subAdd
    Assert-True -Condition ($addCounts.Added -gt 0) -Message 'Expected add changefeed event after creating file'
    $cursor = $addCounts.Cursor
    Write-Output ("afterAdd added={0} updated={1} removed={2} cursor={3}" -f $addCounts.Added, $addCounts.Updated, $addCounts.Removed, $cursor)

    Rename-Item -Path $addedFile -NewName (Split-Path -Leaf $renamedFile)
    Start-Sleep -Milliseconds 400
    $subRename = Invoke-RestMethod -Uri "$base/api/subscribe/$sessionId/$cursor" -Method Get
    $renameCounts = Get-SubscribeCounts -SubscribeResponse $subRename
    Assert-True -Condition ($renameCounts.Added -gt 0) -Message 'Expected add event during rename operation'
    Assert-True -Condition ($renameCounts.Removed -gt 0) -Message 'Expected remove event during rename operation'
    $cursor = $renameCounts.Cursor
    Write-Output ("afterRename added={0} updated={1} removed={2} cursor={3}" -f $renameCounts.Added, $renameCounts.Updated, $renameCounts.Removed, $cursor)

    Remove-Item -Path $renamedFile -Force
    Start-Sleep -Milliseconds 400
    $subRemove = Invoke-RestMethod -Uri "$base/api/subscribe/$sessionId/$cursor" -Method Get
    $removeCounts = Get-SubscribeCounts -SubscribeResponse $subRemove
    Assert-True -Condition ($removeCounts.Removed -gt 0) -Message 'Expected remove changefeed event after deleting file'
    $cursor = $removeCounts.Cursor
    Write-Output ("afterRemove added={0} updated={1} removed={2} cursor={3}" -f $removeCounts.Added, $removeCounts.Updated, $removeCounts.Removed, $cursor)

    Write-Output 'Rojo changefeed edge-case assertions passed.'
}
finally {
    if (Test-Path $renamedFile) {
        Remove-Item -Path $renamedFile -Force
    }
    if (Test-Path $addedFile) {
        Remove-Item -Path $addedFile -Force
    }
    Set-Content -Path $targetFile -Value $originalSource -NoNewline
}
