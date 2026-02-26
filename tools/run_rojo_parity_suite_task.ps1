param(
    [string]$Categories = ""
)

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

$enabledFixtures = @($fixtures | Where-Object {
    if ($_.PSObject.Properties["enabled"]) {
        return [bool]$_.enabled
    }
    return $true
})

if ($enabledFixtures.Count -eq 0) {
    throw "Parity fixture manifest has no enabled fixtures: $fixturesPath"
}

$selectedFixtures = $enabledFixtures
if (-not [string]::IsNullOrWhiteSpace($Categories)) {
    $requestedCategories = @($Categories.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($requestedCategories.Count -eq 0) {
        throw "No valid categories were provided in -Categories."
    }

    $availableCategories = @($enabledFixtures | ForEach-Object { [string]$_.category } | Sort-Object -Unique)
    foreach ($category in $requestedCategories) {
        if ($availableCategories -notcontains $category) {
            throw "Requested category '$category' was not found among enabled fixtures in $fixturesPath"
        }
    }

    $selectedFixtures = @($enabledFixtures | Where-Object { $requestedCategories -contains [string]$_.category })
    if ($selectedFixtures.Count -eq 0) {
        throw "No enabled fixtures matched -Categories '$Categories'."
    }
}

Push-Location $workspace
try {
    foreach ($fixture in $selectedFixtures) {
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
