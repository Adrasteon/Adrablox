try {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
} catch {
    Write-Output "PSScriptAnalyzer_Not_Available"
    exit 1
}

$errs = Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error -ErrorAction SilentlyContinue
if ($errs -and $errs.Count -gt 0) {
    $errs | ConvertTo-Json -Compress | Out-File -Encoding utf8 analysis_pssa_errors.json
    Write-Output "PSSA_ERRORS: wrote analysis_pssa_errors.json"
    exit 2
}

Write-Output "NO_PSSA_ERRORS — proceeding to commit"

# Stage and commit
$commitMsg = "chore(ps): apply lint fixes - Write-Host->Write-Output, empty-catch logging, [void] unused params, alias replacements"
# If there are no staged changes, exit gracefully
$hasChanges = (git status --porcelain)
if (-not $hasChanges) { Write-Output 'NO_CHANGES_TO_COMMIT'; exit 0 }

& git add -A

& git commit -m $commitMsg
if ($LASTEXITCODE -ne 0) { Write-Output 'GIT_COMMIT_FAILED'; exit 3 }

Write-Output 'COMMITTED'
exit 0
