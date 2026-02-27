param(
    [Parameter(Mandatory=$true)][string]$SessionId,
    [Parameter(Mandatory=$true)][string]$InstanceId,
    [string]$Url = "http://127.0.0.1:44877/mcp",
    [switch]$Pretty
)

$params = "{\"name\":\"roblox.readTree\",\"arguments\":{\"sessionId\":\"$SessionId\",\"instanceId\":\"$InstanceId\"}}"

& "$PSScriptRoot\..\bin\send_mcp_rpc.ps1" -Method "tools/call" -Params $params -Url $Url @($Pretty ? '-Pretty' : @())
