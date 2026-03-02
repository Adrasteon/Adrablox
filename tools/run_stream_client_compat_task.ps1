param()

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$connectionManagerPath = Join-Path $workspace 'plugin/mcp-studio/src/ConnectionManager.lua'
$reportPath = Join-Path $workspace 'tools/stream_client_compat_report.json'

if (-not (Test-Path $connectionManagerPath)) {
    throw "ConnectionManager.lua not found at $connectionManagerPath"
}

$content = Get-Content -Raw -Path $connectionManagerPath

$checks = [ordered]@{
    usesCreateWebStreamClient = $content.Contains('CreateWebStreamClient')
    supportsWebSocketClientType = $content.Contains('Enum.WebStreamClientType.WebSocket')
    supportsRawStreamClientType = $content.Contains('Enum.WebStreamClientType.RawStream')
    hasWsThenRawThenHttpFallback = $content.Contains('WebSocket realtime unavailable; trying RawStream fallback') -and $content.Contains('Realtime transport unavailable; using HTTP polling')
    replaySendGuardedToWs = $content.Contains('if mode == "ws"') -and $content.Contains('client:Send')
    enforcesStreamClientCap = $content.Contains('MAX_STREAM_CLIENTS = 6') -and $content.Contains('Realtime stream client cap reached')
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })

$report = [ordered]@{
    status = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    file = 'plugin/mcp-studio/src/ConnectionManager.lua'
    checks = $checks
    failedChecks = $failed
}

$report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath -Encoding UTF8

if ($failed.Count -gt 0) {
    throw "Stream client compatibility checks failed: $($failed -join ', ')"
}

Write-Host "Stream client compatibility task completed successfully. Report: $reportPath"
