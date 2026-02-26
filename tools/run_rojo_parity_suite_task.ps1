$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot

$fixtures = @(
    @{ ProjectFile = 'default.project.json'; ReportPath = 'tools/parity_diff_report.json'; MutationFilePath = 'src/App.module.lua' },
    @{ ProjectFile = 'fixtures/complex.project.json'; ReportPath = 'tools/parity_diff_report_complex.json'; MutationFilePath = 'fixtures/complex_src/Systems/Config.module.lua' },
    @{ ProjectFile = 'fixtures/service_heavy.project.json'; ReportPath = 'tools/parity_diff_report_service_heavy.json'; MutationFilePath = 'fixtures/service_heavy_src/Shared/Config.module.lua' },
    @{ ProjectFile = 'fixtures/nested_modules.project.json'; ReportPath = 'tools/parity_diff_report_nested_modules.json'; MutationFilePath = 'fixtures/nested_modules_src/Game/Features/Economy/Prices.module.lua' }
)

Push-Location $workspace
try {
    foreach ($fixture in $fixtures) {
        $projectFile = [string]$fixture.ProjectFile
        $reportPath = [string]$fixture.ReportPath
        $mutationFilePath = [string]$fixture.MutationFilePath

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
