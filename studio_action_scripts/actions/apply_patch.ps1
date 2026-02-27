param(
    [string]$SessionId,
    [string]$PatchId = "cli_patch_001",
    [string]$BaseCursor = $null,
    [string]$Origin = "cli",
    [string]$OperationsJson = "[]",
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

if (-not $SessionId) {
    Write-Error "SessionId is required. Usage: apply_patch.ps1 -SessionId <id> -OperationsJson '<json>'"
    exit 2
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"
if (Test-Path $nodeCli) {
    # Delegate to Node CLI apply-patch
    node $nodeCli 'apply-patch' $SessionId $PatchId $BaseCursor $Origin $OperationsJson
    exit $LASTEXITCODE
}

# Fallback: call PS helper
$params = "{\"name\":\"roblox.applyPatch\",\"arguments\":{\"sessionId\":\"$SessionId\",\"patchId\":\"$PatchId\",\"baseCursor\":$([string]::IsNullOrEmpty($BaseCursor) ? 'null' : ('\"' + $BaseCursor + '\"')),\"origin\":\"$Origin\",\"operations\":$OperationsJson}}"

& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @($Pretty ? '-Pretty' : @())
