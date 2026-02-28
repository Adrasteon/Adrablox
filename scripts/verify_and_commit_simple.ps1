Import-Module PSScriptAnalyzer -ErrorAction Stop
$errs = Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error -ErrorAction SilentlyContinue
if ($errs -and $errs.Count -gt 0) { $errs | ConvertTo-Json -Compress | Out-File analysis_pssa_errors.json -Encoding utf8; Write-Output 'PSSA_ERRORS'; exit 2 }

Write-Output 'NO_PSSA_ERRORS'

& git add -A
& git commit -m 'chore(ps): apply lint fixes - Write-Host->Write-Output, empty-catch logging, [void] unused params, alias replacements'
if ($LASTEXITCODE -ne 0) { Write-Output 'GIT_COMMIT_FAILED'; exit 3 }

Write-Output 'COMMITTED'
exit 0
