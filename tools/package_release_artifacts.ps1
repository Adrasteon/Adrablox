param(
    [string]$OutputDir = "dist/release",
    [switch]$SkipServerBuild,
    [string]$PluginVersion = "",
    [switch]$RequireRojo
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$outputRoot = Join-Path $workspace $OutputDir
$serverStaging = Join-Path $outputRoot "server"
$pluginSource = Join-Path $workspace "plugin/mcp-studio"
$pluginProject = Join-Path $workspace "plugin/mcp-studio.plugin.project.json"

if (-not (Test-Path $pluginSource)) {
    throw "Plugin source not found at $pluginSource"
}

if (Test-Path $outputRoot) {
    Remove-Item -Path $outputRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $serverStaging -Force | Out-Null

$isWindowsPlatform = ($env:OS -eq "Windows_NT")
$isMacPlatform = (-not $isWindowsPlatform) -and ($PSVersionTable.OS -match "Darwin")

$binaryName = if ($isWindowsPlatform) { "mcp-server.exe" } else { "mcp-server" }
$platformName = if ($isWindowsPlatform) { "windows" } elseif ($isMacPlatform) { "macos" } else { "linux" }

Push-Location $workspace
try {
    $commitShort = (git rev-parse --short HEAD).Trim()
    if ([string]::IsNullOrWhiteSpace($PluginVersion)) {
        $PluginVersion = "0.1.0+{0}" -f $commitShort
    }
    $safePluginVersion = ($PluginVersion -replace '[^A-Za-z0-9._-]', '-')

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

        # On Windows, provide a small launcher so double-clicking the package
        # opens a visible console window that runs the server and shows stdout/stderr.
        if ($isWindowsPlatform) {
            $batPath = Join-Path $serverStaging "run-mcp-server.bat"
            $batContent = "@echo off`r`ncd /d "%~dp0"`r`nstart \"mcp-server\" cmd /k "%~dp0$mcp-server.exe%"`r`n"
            # The above uses %~dp0 to refer to the batch file directory; write ASCII to be safe.
            $batContent = "@echo off`r`ncd /d "%~dp0"`r`nstart \"mcp-server\" cmd /k "%~dp0mcp-server.exe"`r`n"
            Set-Content -Path $batPath -Value $batContent -Encoding ASCII

            $ps1Path = Join-Path $serverStaging "run-mcp-server.ps1"
            $ps1Content = @'
    $here = Split-Path -Parent $MyInvocation.MyCommand.Definition
    Start-Process -FilePath 'cmd.exe' -ArgumentList "/k `"$here\\mcp-server.exe`"" -WorkingDirectory $here
    '@
            Set-Content -Path $ps1Path -Value $ps1Content -Encoding UTF8
        }

    $serverArchive = Join-Path $outputRoot ("mcp-server-{0}.zip" -f $platformName)
    Compress-Archive -Path $serverBinaryOut -DestinationPath $serverArchive -Force

    $pluginSourceArchive = Join-Path $outputRoot ("mcp-studio-plugin-source-{0}.zip" -f $safePluginVersion)
    Compress-Archive -Path (Join-Path $pluginSource "*") -DestinationPath $pluginSourceArchive -Force

    $pluginInstallableArtifact = $null
    $pluginInstallableAvailable = $false
    $rojoCommand = Get-Command rojo -ErrorAction SilentlyContinue
    if ($RequireRojo -and -not $rojoCommand) {
        throw "Rojo CLI is required for this packaging run but was not found in PATH."
    }

    if ($rojoCommand) {
        if (-not (Test-Path $pluginProject)) {
            throw "Plugin project file not found at $pluginProject"
        }
        $pluginInstallableArtifact = Join-Path $outputRoot ("mcp-studio-plugin-{0}.rbxm" -f $safePluginVersion)
        Write-Host "Building installable plugin artifact via Rojo..."
        rojo build $pluginProject --output $pluginInstallableArtifact
        if ($LASTEXITCODE -ne 0) {
            throw "rojo build failed with exit code $LASTEXITCODE"
        }
        $pluginInstallableAvailable = $true
        if (-not (Test-Path $pluginInstallableArtifact) -or ((Get-Item $pluginInstallableArtifact).Length -eq 0)) {
            throw "Rojo built plugin artifact not found or is zero bytes at $pluginInstallableArtifact"
        }
    }
    else {
        Write-Host "Rojo CLI not found; skipping installable plugin artifact (.rbxm) generation."
    }

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
        pluginSourceArchive = [System.IO.Path]::GetFileName($pluginSourceArchive)
        pluginVersion = $PluginVersion
        pluginInstallableAvailable = $pluginInstallableAvailable
        pluginInstallableArtifact = $(if ($pluginInstallableAvailable) { [System.IO.Path]::GetFileName($pluginInstallableArtifact) } else { $null })
        binaryName = $binaryName
        commit = $commitShort
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $manifestPath -Encoding UTF8

    Write-Host "Release artifacts created at: $outputRoot"
    Write-Host "- $([System.IO.Path]::GetFileName($serverArchive))"
    Write-Host "- $([System.IO.Path]::GetFileName($pluginSourceArchive))"
    if ($pluginInstallableAvailable) {
        Write-Host "- $([System.IO.Path]::GetFileName($pluginInstallableArtifact))"
    }
    Write-Host "- release_manifest.json"
}
finally {
    Pop-Location
}
