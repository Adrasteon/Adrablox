$ErrorActionPreference = 'Stop'
$base = 'http://127.0.0.1:44877'

$open = Invoke-RestMethod -Uri "$base/api/rojo" -Method Post -ContentType 'application/json' -Body (@{ projectPath = 'src' } | ConvertTo-Json)
$sessionId = [string]$open.sessionId
$root = [string]$open.rootInstanceId

$read = Invoke-RestMethod -Uri "$base/api/read/$root" -Method Get
$sub = Invoke-RestMethod -Uri "$base/api/subscribe/$sessionId/0" -Method Get

Write-Output ("sessionId={0}" -f $sessionId)
Write-Output ("readCursor={0}" -f $read.cursor)
Write-Output ("readInstances={0}" -f $read.instances.PSObject.Properties.Count)
Write-Output ("subscribeCursor={0}" -f $sub.cursor)
Write-Output ("subscribeUpdated={0}" -f @($sub.updated).Count)
