param(
    [string]$OutputDir = "dist/release",
    [switch]$SkipPackaging
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$outputRoot = Join-Path $workspace $OutputDir
$manifestPath = Join-Path $outputRoot "release_manifest.json"
$healthUrl = "http://127.0.0.1:44877/health"
$mcpUrl = "http://127.0.0.1:44877/mcp"
$validationRoot = Join-Path $workspace "dist/day0_validation"

Push-Location $workspace
try {
    if (-not $SkipPackaging) {
        Write-Output "Building packaged release artifacts..."
        & (Join-Path $workspace "tools/package_release_artifacts.ps1") -OutputDir $OutputDir
    }

    if (-not (Test-Path $manifestPath)) {
        throw "release manifest not found at $manifestPath"
    }

    $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
    $serverArchivePath = Join-Path $outputRoot ([string]$manifest.serverArchive)
    # newer manifests use pluginSourceArchive; old ones may still have pluginArchive
    $pluginArchiveField = if ($manifest.PSObject.Properties.Name -contains 'pluginSourceArchive') { 'pluginSourceArchive' } else { 'pluginArchive' }
    $pluginArchivePath = Join-Path $outputRoot ([string]$manifest.$pluginArchiveField)
    $pluginInstallablePath = $null
    if ($manifest.pluginInstallableArtifact) {
        $pluginInstallablePath = Join-Path $outputRoot ([string]$manifest.pluginInstallableArtifact)
    }
    $binaryName = [string]$manifest.binaryName

    if (-not (Test-Path $serverArchivePath)) {
        throw "server archive not found at $serverArchivePath"
    }
    if (-not (Test-Path $pluginArchivePath)) {
        throw "plugin archive not found at $pluginArchivePath"
    }
    if ($pluginInstallablePath -and -not (Test-Path $pluginInstallablePath)) {
        throw "plugin installable artifact not found at $pluginInstallablePath"
    }

    if (Test-Path $validationRoot) {
        Remove-Item -Path $validationRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $validationRoot -Force | Out-Null

    $serverExtractPath = Join-Path $validationRoot "server"
    $pluginExtractPath = Join-Path $validationRoot "plugin"
    New-Item -ItemType Directory -Path $serverExtractPath -Force | Out-Null
    New-Item -ItemType Directory -Path $pluginExtractPath -Force | Out-Null

    Write-Output "Extracting server archive..."
    Expand-Archive -Path $serverArchivePath -DestinationPath $serverExtractPath -Force

    $serverBinary = Get-ChildItem -Path $serverExtractPath -Recurse -File | Where-Object { $_.Name -eq $binaryName } | Select-Object -First 1
    if ($null -eq $serverBinary) {
        throw "Packaged server binary '$binaryName' not found after archive extraction."
    }

    if (-not $IsWindows) {
        Write-Output "Marking packaged server binary executable on Unix..."
        & chmod +x $serverBinary.FullName
    }

    Write-Output "Starting packaged MCP server binary..."
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
            Write-Verbose "Health check failed (ignored): $_"
        }
    }

    if (-not $ready) {
        throw "Packaged MCP server did not become healthy in time."
    }

    Write-Output "Running smoke test against packaged MCP server..."
    & (Join-Path $workspace "tools/mcp_smoke_test.ps1") -Endpoint $mcpUrl -ProjectPath "src"

    Write-Output "Extracting plugin archive and validating expected contents..."
    Expand-Archive -Path $pluginArchivePath -DestinationPath $pluginExtractPath -Force

    $requiredPluginFiles = @(
        "src/init.lua",
        "src/ConnectionManager.lua",
        "src/SyncEngine.lua",
        "ui/Widget.lua"
    )

    foreach ($relativePath in $requiredPluginFiles) {
        $path = Join-Path $pluginExtractPath $relativePath
        if (-not (Test-Path $path)) {
            throw "Packaged plugin archive missing required file: $relativePath"
        }
    }

    if ($pluginInstallablePath) {
        Write-Output "Installable plugin artifact present: $([System.IO.Path]::GetFileName($pluginInstallablePath))"
    }

    Write-Output "Day-0 packaged artifact validation completed successfully."
}
finally {
    if ($server) {
        try {
            $process = Get-Process -Id $server.Id -ErrorAction Stop
            Write-Output "Stopping packaged MCP server..."
            Stop-Process -Id $process.Id -Force
        }
        catch {
            Write-Verbose "Failed to stop process (ignored): $_"
        }
    }
    Pop-Location
}

