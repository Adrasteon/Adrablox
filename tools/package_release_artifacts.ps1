param(
    [string]$OutputDir = "dist/release",
    [switch]$SkipServerBuild
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$outputRoot = Join-Path $workspace $OutputDir
$serverStaging = Join-Path $outputRoot "server"
$pluginStaging = Join-Path $outputRoot "plugin"
$pluginSource = Join-Path $workspace "plugin/mcp-studio"

if (-not (Test-Path $pluginSource)) {
    throw "Plugin source not found at $pluginSource"
}

if (Test-Path $outputRoot) {
    Remove-Item -Path $outputRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $serverStaging -Force | Out-Null
New-Item -ItemType Directory -Path $pluginStaging -Force | Out-Null

$isWindowsPlatform = ($env:OS -eq "Windows_NT")
$isMacPlatform = (-not $isWindowsPlatform) -and ($PSVersionTable.OS -match "Darwin")

$binaryName = if ($isWindowsPlatform) { "mcp-server.exe" } else { "mcp-server" }
$platformName = if ($isWindowsPlatform) { "windows" } elseif ($isMacPlatform) { "macos" } else { "linux" }

Push-Location $workspace
try {
    if (-not $SkipServerBuild) {
        Write-Host "Building release server artifact..."
        cargo build --release -p mcp-server
        if ($LASTEXITCODE -ne 0) {
            throw "cargo build failed with exit code $LASTEXITCODE"
        }
    }

    $builtBinary = Join-Path $workspace "target/release/$binaryName"
    if (-not (Test-Path $builtBinary)) {
        throw "Built server binary not found at $builtBinary"
    }

    $serverBinaryOut = Join-Path $serverStaging $binaryName
    Copy-Item -Path $builtBinary -Destination $serverBinaryOut -Force

    $serverArchive = Join-Path $outputRoot ("mcp-server-{0}.zip" -f $platformName)
    Compress-Archive -Path $serverBinaryOut -DestinationPath $serverArchive -Force

    $pluginArchive = Join-Path $outputRoot "mcp-studio-plugin-source.zip"
    Compress-Archive -Path (Join-Path $pluginSource "*") -DestinationPath $pluginArchive -Force

    $readmeSource = Join-Path $workspace "README.md"
    $day0Source = Join-Path $workspace "docs/day0_onboarding.md"
    if (Test-Path $readmeSource) {
        Copy-Item -Path $readmeSource -Destination (Join-Path $outputRoot "README.md") -Force
    }
    if (Test-Path $day0Source) {
        Copy-Item -Path $day0Source -Destination (Join-Path $outputRoot "day0_onboarding.md") -Force
    }

    $manifestPath = Join-Path $outputRoot "release_manifest.json"
    $manifest = [ordered]@{
        createdUtc = (Get-Date).ToUniversalTime().ToString("o")
        platform = $platformName
        serverArchive = [System.IO.Path]::GetFileName($serverArchive)
        pluginArchive = [System.IO.Path]::GetFileName($pluginArchive)
        binaryName = $binaryName
        commit = (git rev-parse --short HEAD)
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $manifestPath -Encoding UTF8

    Write-Host "Release artifacts created at: $outputRoot"
    Write-Host "- $([System.IO.Path]::GetFileName($serverArchive))"
    Write-Host "- $([System.IO.Path]::GetFileName($pluginArchive))"
    Write-Host "- release_manifest.json"
}
finally {
    Pop-Location
}
