param(
    [string]$OutputDir = "dist/release",
    [switch]$RequireInstallable
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$outputRoot = Join-Path $workspace $OutputDir
$manifestPath = Join-Path $outputRoot "release_manifest.json"
$healthUrl = "http://127.0.0.1:44877/health"
$endpoint = "http://127.0.0.1:44877/mcp"
$validationRoot = Join-Path $workspace "dist/day0_published_validation"

$script:RequestId = 0

function Invoke-Mcp {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $false)]$Params
    )

    $script:RequestId += 1

    $bodyObject = @{
        jsonrpc = "2.0"
        id = $script:RequestId
        method = $Method
        params = $(if ($null -eq $Params) { @{} } else { $Params })
    }

    $response = Invoke-RestMethod -Uri $endpoint -Method Post -ContentType "application/json" -Body ($bodyObject | ConvertTo-Json -Depth 20)
    if ($null -ne $response.error) {
        throw "MCP error: $($response.error.message)"
    }

    return $response.result
}

function Invoke-McpTool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)]$Arguments = @{}
    )

    $result = Invoke-Mcp -Method "tools/call" -Params @{
        name = $Name
        arguments = $Arguments
    }

    if ($null -eq $result.structuredContent) {
        throw "Tool '$Name' missing structuredContent"
    }

    return $result.structuredContent
}

if (-not (Test-Path $manifestPath)) {
    throw "release manifest not found at $manifestPath"
}

$manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
$serverArchivePath = Join-Path $outputRoot ([string]$manifest.serverArchive)
$pluginSourceArchivePath = Join-Path $outputRoot ([string]$manifest.pluginSourceArchive)
$binaryName = [string]$manifest.binaryName

if (-not (Test-Path $serverArchivePath)) {
    throw "server archive not found at $serverArchivePath"
}
if (-not (Test-Path $pluginSourceArchivePath)) {
    throw "plugin source archive not found at $pluginSourceArchivePath"
}

$installableAvailable = [bool]$manifest.pluginInstallableAvailable
if ($RequireInstallable -and -not $installableAvailable) {
    throw "Installable plugin artifact is required but pluginInstallableAvailable=false in manifest."
}

if ($installableAvailable) {
    $pluginInstallablePath = Join-Path $outputRoot ([string]$manifest.pluginInstallableArtifact)
    if (-not (Test-Path $pluginInstallablePath)) {
        throw "installable plugin artifact not found at $pluginInstallablePath"
    }
}

$releaseReadme = Join-Path $outputRoot "README.md"
$releaseDay0 = Join-Path $outputRoot "day0_onboarding.md"
if (-not (Test-Path $releaseReadme)) {
    throw "release README missing at $releaseReadme"
}
if (-not (Test-Path $releaseDay0)) {
    throw "release day0_onboarding missing at $releaseDay0"
}

if (Test-Path $validationRoot) {
    Remove-Item -Path $validationRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $validationRoot -Force | Out-Null

$serverExtractPath = Join-Path $validationRoot "server"
$projectRoot = Join-Path $validationRoot "sample-project"
$projectSrc = Join-Path $projectRoot "src"

New-Item -ItemType Directory -Path $serverExtractPath -Force | Out-Null
New-Item -ItemType Directory -Path $projectSrc -Force | Out-Null

Set-Content -Path (Join-Path $projectSrc "example.module.lua") -Encoding UTF8 -Value "return { value = 1 }"
$projectJson = @"
{
  "name": "Day0PublishedValidation",
  "tree": {
    "$className": "DataModel",
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "$path": "src"
    }
  }
}
"@
Set-Content -Path (Join-Path $projectRoot "default.project.json") -Encoding UTF8 -Value $projectJson

Push-Location $workspace
try {
    Write-Host "Extracting packaged server archive..."
    Expand-Archive -Path $serverArchivePath -DestinationPath $serverExtractPath -Force

    $serverBinary = Get-ChildItem -Path $serverExtractPath -Recurse -File | Where-Object { $_.Name -eq $binaryName } | Select-Object -First 1
    if ($null -eq $serverBinary) {
        throw "Packaged server binary '$binaryName' not found after extraction."
    }

    if (-not $IsWindows) {
        Write-Host "Marking packaged server binary executable on Unix..."
        & chmod +x $serverBinary.FullName
    }

    Write-Host "Starting packaged MCP server binary..."
    $server = Start-Process -FilePath $serverBinary.FullName -WorkingDirectory $workspace -PassThru

    $ready = $false
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep -Milliseconds 500
        try {
            $health = Invoke-RestMethod -Uri $healthUrl -Method Get -TimeoutSec 2
            if ($health.ok -eq $true) {
                $ready = $true
                break
            }
        }
        catch {
        }
    }

    if (-not $ready) {
        throw "Packaged MCP server did not become healthy in time."
    }

    Write-Host "Validating MCP flow against temp published-artifact project..."
    $init = Invoke-Mcp -Method "initialize" -Params @{
        protocolVersion = "2025-11-25"
        capabilities = @{
            resources = @{ subscribe = $true }
            tools = @{}
        }
        clientInfo = @{
            name = "day0-published-validation"
            version = "0.1.0"
        }
    }

    if ([string]$init.protocolVersion -ne "2025-11-25") {
        throw "Unexpected protocol version: $($init.protocolVersion)"
    }

    Invoke-Mcp -Method "notifications/initialized" -Params @{} | Out-Null

    $open = Invoke-McpTool -Name "roblox.openSession" -Arguments @{ projectPath = (Join-Path $projectRoot "default.project.json") }
    $sessionId = [string]$open.sessionId
    $rootInstanceId = [string]$open.rootInstanceId
    $initialCursor = [int]$open.initialCursor
    if ([string]::IsNullOrWhiteSpace($sessionId) -or [string]::IsNullOrWhiteSpace($rootInstanceId)) {
        throw "openSession returned invalid identifiers"
    }

    $tree = Invoke-McpTool -Name "roblox.readTree" -Arguments @{ sessionId = $sessionId; instanceId = $rootInstanceId }
    if ($null -eq $tree.instances) {
        throw "readTree returned no instances"
    }

    $sub = Invoke-McpTool -Name "roblox.subscribeChanges" -Arguments @{ sessionId = $sessionId; cursor = [string]$initialCursor }
    if ($null -eq $sub.cursor) {
        throw "subscribeChanges returned no cursor"
    }

    $closed = Invoke-McpTool -Name "roblox.closeSession" -Arguments @{ sessionId = $sessionId }
    if ($closed.closed -ne $true) {
        throw "closeSession did not report closed=true"
    }

    Write-Host "Day-0 published artifact validation completed successfully."
}
finally {
    if ($server) {
        try {
            $process = Get-Process -Id $server.Id -ErrorAction Stop
            Write-Host "Stopping packaged MCP server..."
            Stop-Process -Id $process.Id -Force
        }
        catch {
        }
    }
    Pop-Location
}
