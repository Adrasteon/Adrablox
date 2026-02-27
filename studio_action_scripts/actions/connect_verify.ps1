param(
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

# Use the Node CLI if available; otherwise fall back to the PS bin wrapper
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"

if (Test-Path $nodeCli) {
    node $nodeCli health
    exit $LASTEXITCODE
}

& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method initialize -Params '{"protocolVersion":"2025-11-25","capabilities":{"resources":{"subscribe":true},"tools":{}},"clientInfo":{"name":"connect-verify","version":"0.1.0"}}' -Url $Url @($Pretty ? '-Pretty' : @())
& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method tools/list -Params '{}' -Url $Url @($Pretty ? '-Pretty' : @())
