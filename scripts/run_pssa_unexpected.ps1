try {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
} catch {
    Write-Output "PSScriptAnalyzer_Not_Available"
    exit 1
}

$res = Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error -ErrorAction SilentlyContinue
if (-not $res) {
    Write-Output "NO_PSSA_ERRORS"
    exit 0
}

$errs = $res | Where-Object { ($_.Message -ne $null -and $_.Message -match 'Unexpected') -or ($_.RuleName -ne $null -and $_.RuleName -match 'Parsing') -or ($_.Message -match 'Missing') }
if ($errs -and $errs.Count -gt 0) {
    $errs | Select-Object ScriptName,Line,RuleName,Severity,Message | Sort-Object ScriptName,Line | ConvertTo-Json -Compress | Out-File -Encoding utf8 analysis_pssa_errors.json
    Write-Output "WROTE: analysis_pssa_errors.json"
} else {
    Write-Output "NO_PSSA_ERRORS_MATCH"
}
