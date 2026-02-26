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
        $fixtureName = [string]$fixture.name
        $fixtureCategory = [string]$fixture.category
        $projectFile = [string]$fixture.projectFile
        $reportPath = [string]$fixture.reportPath
        $mutationFilePath = [string]$fixture.mutationFilePath

        if ([string]::IsNullOrWhiteSpace($fixtureName) -or [string]::IsNullOrWhiteSpace($fixtureCategory) -or [string]::IsNullOrWhiteSpace($projectFile) -or [string]::IsNullOrWhiteSpace($reportPath) -or [string]::IsNullOrWhiteSpace($mutationFilePath)) {
            throw "Invalid parity fixture entry in $fixturesPath. Each fixture must define name, category, projectFile, reportPath, and mutationFilePath."
        }

        Write-Host "Running parity diff fixture: $fixtureName ($fixtureCategory) -> $projectFile"
        & (Join-Path $workspace 'tools\run_rojo_parity_diff_task.ps1') `
            -ProjectFile $projectFile `
            -ReportPath $reportPath `
            -MutationFilePath $mutationFilePath `
            -FixtureName $fixtureName `
            -FixtureCategory $fixtureCategory `
            -FailOnDiff

        Write-Host "Fixture passed: $fixtureName"
    }

    Write-Host "Rojo parity suite completed successfully."
}
finally {
    Pop-Location
}
