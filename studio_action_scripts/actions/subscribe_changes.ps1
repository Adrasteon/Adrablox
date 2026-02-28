param(
    [Parameter(Mandatory=$true)][string]$SessionId,
    [string]$Cursor = $null,
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"
if (Test-Path $nodeCli) {
    if ($null -ne $Cursor) {
        node $nodeCli 'subscribe' $SessionId $Cursor
    } else {
        node $nodeCli 'subscribe' $SessionId
    }
    exit $LASTEXITCODE
}

$argsObj = @{ name = 'roblox.subscribeChanges'; arguments = @{ sessionId = $SessionId } }
if ($null -ne $Cursor) { $argsObj.arguments.cursor = $Cursor }

$params = $argsObj | ConvertTo-Json -Depth 8

$flags = @()
if ($Pretty) { $flags += '-Pretty' }
& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @flags
