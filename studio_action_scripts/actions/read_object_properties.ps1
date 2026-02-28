param(
    [Parameter(Mandatory=$true)][string]$SessionId,
    [Parameter(Mandatory=$true)][string]$InstanceId,
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"
if (Test-Path $nodeCli) {
    node $nodeCli 'get-properties' $SessionId $InstanceId
    exit $LASTEXITCODE
}

$argsObj = @{ name = 'roblox.readObject'; arguments = @{ sessionId = $SessionId; instanceId = $InstanceId } }
$params = $argsObj | ConvertTo-Json -Depth 6

$flags = @()
if ($Pretty) { $flags += '-Pretty' }
& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @flags
