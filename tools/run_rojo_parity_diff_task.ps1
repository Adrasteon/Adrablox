param(
    [string]$ProjectFile = "default.project.json",
    [string]$ReportPath = "tools/parity_diff_report.json",
    [string]$MutationFilePath = "",
    [string]$MutationMarker = "-- parity-mutation-marker",
    [int]$MutationSettleMs = 1200,
    [string]$FixtureName = "",
    [string]$FixtureCategory = "",
    [switch]$FailOnDiff
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
$mcpHealthUrl = 'http://127.0.0.1:44877/health'
$rojoBase = 'http://127.0.0.1:34872'

if (-not (Test-Path $cargoExe)) {
    throw "cargo not found at $cargoExe"
}

function Get-RojoExecutable {
    $command = Get-Command rojo -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        return $command.Source
    }

    $candidates = @(
        "$env:LocalAppData\Microsoft\WinGet\Links\rojo.exe",
        "$env:ProgramFiles\Rojo\rojo.exe",
        "$env:ProgramFiles\Rojo\bin\rojo.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $wingetPackages = Join-Path $env:LocalAppData 'Microsoft\WinGet\Packages'
    if (Test-Path $wingetPackages) {
        $match = Get-ChildItem -Path $wingetPackages -Directory -Filter 'Rojo.Rojo*' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($match) {
            $fromPackage = Join-Path $match.FullName 'rojo.exe'
            if (Test-Path $fromPackage) {
                return $fromPackage
            }
        }
    }

    throw "rojo CLI not found in PATH or common install paths. Install Rojo and ensure `rojo` is available."
}

$rojoExe = Get-RojoExecutable

Push-Location $workspace
try {
    $mcpOut = Join-Path $env:TEMP 'mcp_parity_mcp.out.log'
    $mcpErr = Join-Path $env:TEMP 'mcp_parity_mcp.err.log'
    $rojoOut = Join-Path $env:TEMP 'mcp_parity_rojo.out.log'
    $rojoErr = Join-Path $env:TEMP 'mcp_parity_rojo.err.log'

    Remove-Item $mcpOut, $mcpErr, $rojoOut, $rojoErr -ErrorAction SilentlyContinue

    Write-Host "Starting MCP server..."
    $mcpServer = Start-Process -FilePath $cargoExe -ArgumentList @('run','-p','mcp-server') -WorkingDirectory $workspace -PassThru -RedirectStandardOutput $mcpOut -RedirectStandardError $mcpErr

    Write-Host "Starting Rojo serve..."
    $rojoServer = Start-Process -FilePath $rojoExe -ArgumentList @('serve',$ProjectFile,'--address','127.0.0.1','--port','34872') -WorkingDirectory $workspace -PassThru -RedirectStandardOutput $rojoOut -RedirectStandardError $rojoErr

    $mcpReady = $false
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep -Milliseconds 500
        if ($mcpServer.HasExited) {
            $stderr = if (Test-Path $mcpErr) { Get-Content -Raw $mcpErr } else { "" }
            $stdout = if (Test-Path $mcpOut) { Get-Content -Raw $mcpOut } else { "" }
            throw "MCP server exited early with code $($mcpServer.ExitCode). stdout=`n$stdout`nstderr=`n$stderr"
        }
        try {
            $health = Invoke-RestMethod -Uri $mcpHealthUrl -Method Get -TimeoutSec 2
            if ($health.ok -eq $true) {
                $mcpReady = $true
                break
            }
        }
        catch {
        }
    }

    if (-not $mcpReady) {
        throw "MCP server did not become healthy in time."
    }

    $rojoReady = $false
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep -Milliseconds 500
        if ($rojoServer.HasExited) {
            $stderr = if (Test-Path $rojoErr) { Get-Content -Raw $rojoErr } else { "" }
            $stdout = if (Test-Path $rojoOut) { Get-Content -Raw $rojoOut } else { "" }
            throw "Rojo serve exited early with code $($rojoServer.ExitCode). stdout=`n$stdout`nstderr=`n$stderr"
        }
        try {
            $null = Invoke-RestMethod -Uri "$rojoBase/api/rojo" -Method Get -TimeoutSec 2
            $rojoReady = $true
            break
        }
        catch {
            try {
                $null = Invoke-RestMethod -Uri "$rojoBase/api/rojo" -Method Post -ContentType 'application/json' -Body (@{ projectPath = 'default.project.json' } | ConvertTo-Json) -TimeoutSec 2
                $rojoReady = $true
                break
            }
            catch {
            }
        }
    }

    if (-not $rojoReady) {
        throw "Rojo serve did not become ready in time."
    }

    Write-Host "Both servers are ready. Running parity diff check..."
    $parityArgs = @{
        ProjectPath = $ProjectFile
        ReportPath = $ReportPath
        MutationFilePath = $MutationFilePath
        MutationMarker = $MutationMarker
        MutationSettleMs = $MutationSettleMs
        FixtureName = $FixtureName
        FixtureCategory = $FixtureCategory
    }
    if ($FailOnDiff) {
        $parityArgs.FailOnDiff = $true
    }
    & (Join-Path $workspace 'tools\rojo_parity_diff_check.ps1') @parityArgs

    Write-Host "Rojo parity diff task completed."
}
finally {
    if ($rojoServer -and -not $rojoServer.HasExited) {
        Write-Host "Stopping Rojo serve..."
        Stop-Process -Id $rojoServer.Id -Force
    }
    if ($mcpServer -and -not $mcpServer.HasExited) {
        Write-Host "Stopping MCP server..."
        Stop-Process -Id $mcpServer.Id -Force
    }
    Pop-Location
}
