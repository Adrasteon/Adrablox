param(
    [string]$SessionId,
    [string]$OperationsJson = '[]',
    [string]$BaseCursor = $null,
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"
if (Test-Path $nodeCli) {
    $args = @('conflict-recover', $SessionId, $OperationsJson)
    if ($BaseCursor) { $args += $BaseCursor }
    node $nodeCli @args
    exit $LASTEXITCODE
}

$params = "{\"name\":\"roblox.applyPatch\",\"arguments\":{\"sessionId\":\"$SessionId\",\"patchId\":\"ps_conflict_recover\",\"baseCursor\":$([string]::IsNullOrEmpty($BaseCursor) ? 'null' : ('"' + $BaseCursor + '"')) ,\"origin\":\"ps-conflict-recover\",\"operations\":$OperationsJson}}"

& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @($Pretty ? '-Pretty' : @())
