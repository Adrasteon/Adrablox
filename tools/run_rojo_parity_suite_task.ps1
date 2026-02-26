$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot

$fixtures = @(
    @{ ProjectFile = 'default.project.json'; ReportPath = 'tools/parity_diff_report.json' },
    @{ ProjectFile = 'fixtures/complex.project.json'; ReportPath = 'tools/parity_diff_report_complex.json' }
)

Push-Location $workspace
try {
    foreach ($fixture in $fixtures) {
        $projectFile = [string]$fixture.ProjectFile
        $reportPath = [string]$fixture.ReportPath

        Write-Host "Running parity diff fixture: $projectFile"
        & (Join-Path $workspace 'tools\run_rojo_parity_diff_task.ps1') `
            -ProjectFile $projectFile `
            -ReportPath $reportPath `
            -FailOnDiff

        Write-Host "Fixture passed: $projectFile"
    }

    Write-Host "Rojo parity suite completed successfully."
}
finally {
    Pop-Location
}
