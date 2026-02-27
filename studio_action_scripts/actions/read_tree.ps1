param(
    [Parameter(Mandatory=$true)][string]$SessionId,
    [Parameter(Mandatory=$true)][string]$InstanceId,
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

$params = "{\"name\":\"roblox.readTree\",\"arguments\":{\"sessionId\":\"$SessionId\",\"instanceId\":\"$InstanceId\"}}"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"
if (Test-Path $nodeCli) {
    node $nodeCli 'read-tree' $SessionId $InstanceId
    exit $LASTEXITCODE
}

& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @($Pretty ? '-Pretty' : @())
