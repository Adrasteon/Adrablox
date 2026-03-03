param(
    [string]$OutputDir = "dist/release",
    [switch]$RequireInstallable
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$outputRoot = Join-Path $workspace $OutputDir
$manifestPath = Join-Path $outputRoot "release_manifest.json"

if (-not (Test-Path $manifestPath)) {
    throw "release manifest not found at $manifestPath"
}

$manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json

function Assert-NonEmptyString {
    param(
        [Parameter(Mandatory = $true)][string]$FieldName,
        [Parameter(Mandatory = $true)]$Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        throw "Manifest field '$FieldName' is missing or empty."
    }
}

function Assert-Matches {
    param(
        [Parameter(Mandatory = $true)][string]$FieldName,
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    if ($Value -notmatch $Pattern) {
        throw "Manifest field '$FieldName' has unexpected format: $Value"
    }
}

Assert-NonEmptyString -FieldName "platform" -Value $manifest.platform
Assert-NonEmptyString -FieldName "serverArchive" -Value $manifest.serverArchive
Assert-NonEmptyString -FieldName "pluginSourceArchive" -Value $manifest.pluginSourceArchive
Assert-NonEmptyString -FieldName "pluginVersion" -Value $manifest.pluginVersion
Assert-NonEmptyString -FieldName "binaryName" -Value $manifest.binaryName
Assert-NonEmptyString -FieldName "commit" -Value $manifest.commit

$platform = [string]$manifest.platform
$serverArchive = [string]$manifest.serverArchive
$rojoCompatServerIncluded = [bool]$manifest.rojoCompatServerIncluded
$serverArchiveRojoCompat = if ($null -ne $manifest.serverArchiveRojoCompat) { [string]$manifest.serverArchiveRojoCompat } else { "" }
$pluginSourceArchive = [string]$manifest.pluginSourceArchive
$pluginInstallableArtifact = if ($null -ne $manifest.pluginInstallableArtifact) { [string]$manifest.pluginInstallableArtifact } else { "" }

Assert-Matches -FieldName "platform" -Value $platform -Pattern '^(windows|linux|macos)$'
Assert-Matches -FieldName "serverArchive" -Value $serverArchive -Pattern '^mcp-server-(windows|linux|macos)\.zip$'
if ($rojoCompatServerIncluded) {
    Assert-NonEmptyString -FieldName "serverArchiveRojoCompat" -Value $serverArchiveRojoCompat
    Assert-Matches -FieldName "serverArchiveRojoCompat" -Value $serverArchiveRojoCompat -Pattern '^mcp-server-(windows|linux|macos)-rojo-compat\.zip$'
}
Assert-Matches -FieldName "pluginSourceArchive" -Value $pluginSourceArchive -Pattern '^mcp-studio-plugin-source-[A-Za-z0-9._-]+\.zip$'

$serverArchivePath = Join-Path $outputRoot $serverArchive
$pluginSourceArchivePath = Join-Path $outputRoot $pluginSourceArchive

if (-not (Test-Path $serverArchivePath)) {
    throw "Server archive missing: $serverArchivePath"
}
if ($rojoCompatServerIncluded) {
    $serverArchiveRojoCompatPath = Join-Path $outputRoot $serverArchiveRojoCompat
    if (-not (Test-Path $serverArchiveRojoCompatPath)) {
        throw "Rojo-compat server archive missing: $serverArchiveRojoCompatPath"
    }
}
if (-not (Test-Path $pluginSourceArchivePath)) {
    throw "Plugin source archive missing: $pluginSourceArchivePath"
}

$installableAvailable = [bool]$manifest.pluginInstallableAvailable
if ($installableAvailable) {
    Assert-NonEmptyString -FieldName "pluginInstallableArtifact" -Value $pluginInstallableArtifact
    Assert-Matches -FieldName "pluginInstallableArtifact" -Value $pluginInstallableArtifact -Pattern '^mcp-studio-plugin-[A-Za-z0-9._-]+\.rbxm$'

    $pluginInstallablePath = Join-Path $outputRoot $pluginInstallableArtifact
    if (-not (Test-Path $pluginInstallablePath)) {
        throw "Installable plugin artifact missing: $pluginInstallablePath"
    }
}
elseif ($RequireInstallable) {
    throw "Installable plugin artifact is required but pluginInstallableAvailable=false in manifest."
}

Write-Host "Release manifest validation succeeded."
Write-Host "- platform=$platform"
Write-Host "- serverArchive=$serverArchive"
Write-Host "- rojoCompatServerIncluded=$rojoCompatServerIncluded"
if ($rojoCompatServerIncluded) {
    Write-Host "- serverArchiveRojoCompat=$serverArchiveRojoCompat"
}
Write-Host "- pluginSourceArchive=$pluginSourceArchive"
Write-Host "- pluginInstallableAvailable=$installableAvailable"
if ($installableAvailable) {
    Write-Host "- pluginInstallableArtifact=$pluginInstallableArtifact"
}
