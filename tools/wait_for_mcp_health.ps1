param(
    [string]$Url = "http://127.0.0.1:44877/health",
    [int]$TimeoutSeconds = 60,
    [int]$PollIntervalMilliseconds = 500,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastError = $null

while ((Get-Date) -lt $deadline) {
    try {
        $health = Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 2
        if ($health.ok -eq $true) {
            if (-not $Quiet) {
                Write-Host "MCP server is healthy at $Url"
            }
            exit 0
        }
    }
    catch {
        $lastError = $_
    }

    Start-Sleep -Milliseconds $PollIntervalMilliseconds
}

if (-not $Quiet) {
    if ($lastError) {
        Write-Host "Timed out waiting for MCP health at $Url. Last error: $lastError"
    }
    else {
        Write-Host "Timed out waiting for MCP health at $Url."
    }
}

exit 1
