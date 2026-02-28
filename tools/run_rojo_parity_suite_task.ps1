param(
    [string]$Categories = "",
    [string]$Fixtures = "",
    [int]$MutationSettleMs = 1200,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$fixturesPath = Join-Path $workspace 'tools\parity_fixtures.json'

if (-not (Test-Path $fixturesPath)) {
    throw "Parity fixture manifest not found: $fixturesPath"
}

$fixturesRaw = Get-Content -Raw -Path $fixturesPath | ConvertFrom-Json
$fixtureEntries = @()
if ($fixturesRaw -is [System.Array]) {
    $fixtureEntries = $fixturesRaw
}
else {
    $fixtureEntries = @($fixturesRaw)
}

if ($fixtureEntries.Count -eq 0) {
    throw "Parity fixture manifest is empty: $fixturesPath"
}

$enabledFixtures = @($fixtureEntries | Where-Object {
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

if (-not [string]::IsNullOrWhiteSpace($Fixtures)) {
    $requestedFixtureNames = @($Fixtures.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($requestedFixtureNames.Count -eq 0) {
        throw "No valid fixture names were provided in -Fixtures."
    }

    $availableFixtureNames = @($enabledFixtures | ForEach-Object { [string]$_.name } | Sort-Object -Unique)
    foreach ($fixtureName in $requestedFixtureNames) {
        if ($availableFixtureNames -notcontains $fixtureName) {
            throw "Requested fixture '$fixtureName' was not found among enabled fixtures in $fixturesPath"
        }
    }

    $selectedFixtures = @($selectedFixtures | Where-Object { $requestedFixtureNames -contains [string]$_.name })
    if ($selectedFixtures.Count -eq 0) {
        throw "No enabled fixtures matched combined -Categories '$Categories' and -Fixtures '$Fixtures' filters."
    }
}

Push-Location $workspace
try {
    Write-Output "Selected parity fixtures: $($selectedFixtures.Count)"

    foreach ($fixture in $selectedFixtures) {
        $fixtureName = [string]$fixture.name
        $fixtureCategory = [string]$fixture.category
        $projectFile = [string]$fixture.projectFile
        $reportPath = [string]$fixture.reportPath
        $mutationFilePath = [string]$fixture.mutationFilePath

        if ([string]::IsNullOrWhiteSpace($fixtureName) -or [string]::IsNullOrWhiteSpace($fixtureCategory) -or [string]::IsNullOrWhiteSpace($projectFile) -or [string]::IsNullOrWhiteSpace($reportPath) -or [string]::IsNullOrWhiteSpace($mutationFilePath)) {
            throw "Invalid parity fixture entry in $fixturesPath. Each fixture must define name, category, projectFile, reportPath, and mutationFilePath."
        }

        if ($DryRun) {
            Write-Output "[DRY-RUN] $fixtureName ($fixtureCategory) -> project=$projectFile report=$reportPath mutation=$mutationFilePath"
            continue
        }

        Write-Output "Running parity diff fixture: $fixtureName ($fixtureCategory) -> $projectFile"
        & (Join-Path $workspace 'tools\run_rojo_parity_diff_task.ps1') `
            -ProjectFile $projectFile `
            -ReportPath $reportPath `
            -MutationFilePath $mutationFilePath `
            -MutationSettleMs $MutationSettleMs `
            -FixtureName $fixtureName `
            -FixtureCategory $fixtureCategory `
            -FailOnDiff

        Write-Output "Fixture passed: $fixtureName"
    }

    if ($DryRun) {
        Write-Output "Rojo parity suite dry-run completed successfully."
    }
    else {
        Write-Output "Rojo parity suite completed successfully."
    }
}
finally {
    Pop-Location
}

