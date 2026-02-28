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
    $cliArgs = @('conflict-recover', $SessionId, $OperationsJson)
    if ($BaseCursor) { $cliArgs += $BaseCursor }
    node $nodeCli @cliArgs
    exit $LASTEXITCODE
}

$baseCursor = $null
if (-not [string]::IsNullOrEmpty($BaseCursor)) { $baseCursor = $BaseCursor }

$argsObj = @{
    name = 'roblox.applyPatch'
    arguments = @{
        sessionId = $SessionId
        patchId = 'ps_conflict_recover'
        baseCursor = $baseCursor
        origin = 'ps-conflict-recover'
        operations = (ConvertFrom-Json $OperationsJson)
    }
}

$params = $argsObj | ConvertTo-Json -Depth 10

$flags = @()
if ($Pretty) { $flags += '-Pretty' }

& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @flags
