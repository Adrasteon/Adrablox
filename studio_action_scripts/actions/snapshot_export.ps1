param(
    [string]$SessionId,
    [string]$OutFile = "$PSScriptRoot\..\out\snapshot.json",
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"
if (Test-Path $nodeCli) {
    $args = @('snapshot-export', $SessionId, $OutFile)
    node $nodeCli @args
    exit $LASTEXITCODE
}

$params = "{\"name\":\"roblox.exportSnapshot\",\"arguments\":{\"sessionId\":\"$SessionId\"}}"

if (!(Test-Path (Split-Path $OutFile))) { New-Item -ItemType Directory -Path (Split-Path $OutFile) -Force | Out-Null }
& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @($Pretty ? '-Pretty' : @()) | Out-File -Encoding utf8 -FilePath $OutFile
