param(
    [string]$SessionId,
    [string]$OutFile = "$PSScriptRoot\..\out\snapshot.json",
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"
if (Test-Path $nodeCli) {
    $cliArgs = @('snapshot-export', $SessionId, $OutFile)
    node $nodeCli @cliArgs
    exit $LASTEXITCODE
}

# Build params object and convert to JSON to avoid quoting/escaping issues
$paramsObj = @{ name = 'roblox.exportSnapshot'; arguments = @{ sessionId = $SessionId } }
$params = $paramsObj | ConvertTo-Json -Depth 6

if (!(Test-Path (Split-Path $OutFile))) { New-Item -ItemType Directory -Path (Split-Path $OutFile) -Force | Out-Null }

$flags = @()
if ($Pretty) { $flags += '-Pretty' }

& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @flags | Out-File -Encoding utf8 -FilePath $OutFile
