param(
    [string]$ProjectPath = "src",
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

$params = "{\"name\":\"roblox.openSession\",\"arguments\":{\"projectPath\":\"$ProjectPath\"}}"

& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @($Pretty ? '-Pretty' : @())
