param(
    [string]$OutputDir = "dist/release",
    [switch]$Verify
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$outputRoot = Join-Path $workspace $OutputDir
$manifestPath = Join-Path $outputRoot "release_manifest.json"
$checksumsTxtPath = Join-Path $outputRoot "release_checksums.txt"
$checksumsJsonPath = Join-Path $outputRoot "release_checksums.json"

if (-not (Test-Path $manifestPath)) {
    throw "release manifest not found at $manifestPath"
}

$manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json

$artifactNames = @()
$artifactNames += [string]$manifest.serverArchive
$artifactNames += [string]$manifest.pluginSourceArchive
$artifactNames += "release_manifest.json"
if ([bool]$manifest.pluginInstallableAvailable -and -not [string]::IsNullOrWhiteSpace([string]$manifest.pluginInstallableArtifact)) {
    $artifactNames += [string]$manifest.pluginInstallableArtifact
}

$artifactNames = $artifactNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

if ($Verify) {
    if (-not (Test-Path $checksumsTxtPath)) {
        throw "checksum file not found at $checksumsTxtPath"
    }

    $lines = Get-Content -Path $checksumsTxtPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($lines.Count -eq 0) {
        throw "checksum file is empty: $checksumsTxtPath"
    }

    $checksumMap = @{}
    foreach ($line in $lines) {
        if ($line -notmatch '^([A-Fa-f0-9]{64})\s{2}(.+)$') {
            throw "invalid checksum line format: '$line'"
        }
        $checksumMap[$matches[2]] = $matches[1].ToLowerInvariant()
    }

    foreach ($artifactName in $artifactNames) {
        if (-not $checksumMap.ContainsKey($artifactName)) {
            throw "checksum entry missing for artifact: $artifactName"
        }

        $artifactPath = Join-Path $outputRoot $artifactName
        if (-not (Test-Path $artifactPath)) {
            throw "artifact missing for checksum verification: $artifactPath"
        }

        $actual = (Get-FileHash -Path $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $expected = [string]$checksumMap[$artifactName]
        if ($actual -ne $expected) {
            throw "checksum mismatch for ${artifactName}: expected=$expected actual=$actual"
        }
    }

    Write-Output "Release checksum verification succeeded."
    Write-Output "- verifiedArtifacts=$($artifactNames.Count)"
    Write-Output "- checksumFile=release_checksums.txt"
    return
}

$entries = @()
foreach ($artifactName in $artifactNames) {
    $artifactPath = Join-Path $outputRoot $artifactName
    if (-not (Test-Path $artifactPath)) {
        throw "artifact missing for checksum generation: $artifactPath"
    }

    $hash = Get-FileHash -Path $artifactPath -Algorithm SHA256
    $entries += [ordered]@{
        file = $artifactName
        sha256 = $hash.Hash.ToLowerInvariant()
    }
}

$txtLines = @($entries | ForEach-Object { "{0}  {1}" -f $_.sha256, $_.file })
Set-Content -Path $checksumsTxtPath -Value $txtLines -Encoding UTF8

$jsonPayload = [ordered]@{
    generatedUtc = (Get-Date).ToUniversalTime().ToString("o")
    algorithm = "SHA256"
    entries = $entries
}
$jsonPayload | ConvertTo-Json -Depth 6 | Set-Content -Path $checksumsJsonPath -Encoding UTF8

Write-Output "Release checksum generation succeeded."
Write-Output "- checksumFile=release_checksums.txt"
Write-Output "- checksumJson=release_checksums.json"
Write-Output "- artifactCount=$($entries.Count)"

