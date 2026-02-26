$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$fixturesPath = Join-Path $workspace 'tools\parity_fixtures.json'

if (-not (Test-Path $fixturesPath)) {
    throw "Parity fixture manifest not found: $fixturesPath"
}

$fixturesRaw = Get-Content -Raw -Path $fixturesPath | ConvertFrom-Json
$fixtures = @($fixturesRaw)

if ($fixtures.Count -eq 0) {
    throw "Parity fixture manifest is empty: $fixturesPath"
}

Push-Location $workspace
try {
    foreach ($fixture in $fixtures) {
        $projectFile = [string]$fixture.projectFile
        $reportPath = [string]$fixture.reportPath
        $mutationFilePath = [string]$fixture.mutationFilePath

        if ([string]::IsNullOrWhiteSpace($projectFile) -or [string]::IsNullOrWhiteSpace($reportPath) -or [string]::IsNullOrWhiteSpace($mutationFilePath)) {
            throw "Invalid parity fixture entry in $fixturesPath. Each fixture must define projectFile, reportPath, and mutationFilePath."
        }

        Write-Host "Running parity diff fixture: $projectFile"
        & (Join-Path $workspace 'tools\run_rojo_parity_diff_task.ps1') `
            -ProjectFile $projectFile `
            -ReportPath $reportPath `
            -MutationFilePath $mutationFilePath `
            -FailOnDiff

        Write-Host "Fixture passed: $projectFile"
    }

    Write-Host "Rojo parity suite completed successfully."
}
finally {
    Pop-Location
}
