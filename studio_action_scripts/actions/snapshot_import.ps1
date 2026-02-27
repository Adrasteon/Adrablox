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

# Read snapshot JSON and convert to object so we can embed it safely
$snapshot = Get-Content -Raw -Path $InFile | ConvertFrom-Json

$paramsObj = @{ name = 'roblox.importSnapshot'; arguments = @{ sessionId = $SessionId; snapshot = $snapshot } }
$params = $paramsObj | ConvertTo-Json -Depth 10

$flags = @()
if ($Pretty) { $flags += '-Pretty' }

& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @flags
