param(
    [string]$SessionId,
    [string]$InFile,
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

if (-not (Test-Path $InFile)) { Write-Error "Input file not found: $InFile"; exit 2 }

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"
if (Test-Path $nodeCli) {
    node $nodeCli 'snapshot-import' $SessionId $InFile
    exit $LASTEXITCODE
}

$content = Get-Content -Raw -Path $InFile
$params = "{\"name\":\"roblox.importSnapshot\",\"arguments\":{\"sessionId\":\"$SessionId\",\"snapshot\":$content}}"
& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @($Pretty ? '-Pretty' : @())
