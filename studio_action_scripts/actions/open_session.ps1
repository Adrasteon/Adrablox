param(
    [string]$ProjectPath = "adrablox.project.json",
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

## Build JSON params safely (avoid PowerShell string-escaping issues)
$params = '{"name":"roblox.openSession","arguments":{"projectPath":"' + $ProjectPath + '"}}'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeCli = Join-Path $repoRoot "studio_action_scripts\cli\index.js"
if (Test-Path $nodeCli) {
    node $nodeCli 'open-session' $ProjectPath
    exit $LASTEXITCODE
}

## Add optional Pretty flag in a way compatible with Windows PowerShell
$prettyArg = @()
if ($Pretty) { $prettyArg = @('-Pretty') }

$rc = 0
try {
    & "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @prettyArg
    $rc = $LASTEXITCODE
} catch {
    Write-Host "send_mcp_rpc threw an exception: $_"
    $rc = 1
}

if ($rc -ne 0) {
    Write-Host "MCP RPC failed (exit code $LASTEXITCODE). Falling back to opening 'dist' folder or plugin file."
    $dist = Join-Path $repoRoot 'dist'
    if (Test-Path $dist) {
        $rbxm = Get-ChildItem -Path $dist -Filter *.rbxm -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($rbxm) {
            Write-Host "Opening plugin file $($rbxm.FullName)"
            Start-Process -FilePath $rbxm.FullName
            exit 0
        } else {
            Start-Process -FilePath $dist
            exit 0
        }
    } else {
        Start-Process -FilePath $repoRoot
        exit 0
    }
}
