param(
    [Parameter(Mandatory=$true)][string]$ToolName,
    [string]$ArgumentsJson = "{}",
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

# Generic tool caller: prefers Node CLI when available
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"
if (Test-Path $nodeCli) {
    # Pass argumentsJson as a single arg; CLI will JSON.parse it
    node $nodeCli call $ToolName $ArgumentsJson
    exit $LASTEXITCODE
}

# Fallback to PowerShell helper
$argsObj = @{ name = $ToolName; arguments = (ConvertFrom-Json $ArgumentsJson) }
$params = $argsObj | ConvertTo-Json -Depth 8

$flags = @()
if ($Pretty) { $flags += '-Pretty' }

& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @flags
