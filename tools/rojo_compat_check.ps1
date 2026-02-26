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

$open = Invoke-RestMethod -Uri "$base/api/rojo" -Method Post -ContentType 'application/json' -Body (@{ projectPath = 'src' } | ConvertTo-Json)
$sessionId = [string]$open.sessionId
$root = [string]$open.rootInstanceId

$read = Invoke-RestMethod -Uri "$base/api/read/$root" -Method Get
$sub = Invoke-RestMethod -Uri "$base/api/subscribe/$sessionId/0" -Method Get
$readInstances = @($read.instances.PSObject.Properties).Count
$hasRoot = $null -ne $read.instances.PSObject.Properties[$root]

Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($sessionId)) -Message 'openSession did not return sessionId'
Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($root)) -Message 'openSession did not return rootInstanceId'
Assert-True -Condition ($read.sessionId -eq $sessionId) -Message 'read response sessionId mismatch'
Assert-True -Condition ($sub.sessionId -eq $sessionId) -Message 'subscribe response sessionId mismatch'
Assert-True -Condition ($readInstances -gt 0) -Message 'read response returned zero instances'
Assert-True -Condition $hasRoot -Message 'read response did not include requested root instance'
Assert-True -Condition ($null -ne $read.sessionCapabilities) -Message 'read response missing sessionCapabilities'
Assert-True -Condition ($read.sessionCapabilities.supportsStructuralOps -eq $false) -Message 'supportsStructuralOps expected false'
Assert-True -Condition ($null -ne $sub.sessionCapabilities) -Message 'subscribe response missing sessionCapabilities'
Assert-True -Condition ($null -ne $read.fileBackedInstanceIds) -Message 'read response missing fileBackedInstanceIds'
Assert-True -Condition ($null -ne $sub.fileBackedInstanceIds) -Message 'subscribe response missing fileBackedInstanceIds'

Write-Output ("sessionId={0}" -f $sessionId)
Write-Output ("readCursor={0}" -f $read.cursor)
Write-Output ("readInstances={0}" -f $readInstances)
Write-Output ("subscribeCursor={0}" -f $sub.cursor)
Write-Output ("subscribeUpdated={0}" -f @($sub.updated).Count)
Write-Output 'Rojo compatibility assertions passed.'
