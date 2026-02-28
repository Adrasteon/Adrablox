if (-not (Test-Path "analysis_pssa.json")) {
    Write-Output "NO_ANALYSIS_JSON"
    exit 0
}

try {
    $j = Get-Content "analysis_pssa.json" -Raw | ConvertFrom-Json
} catch {
    Write-Output "FAILED_PARSE_ANALYSIS_JSON"
    exit 1
}

$errs = $j | Where-Object { ($_.Message -ne $null -and $_.Message -match 'Unexpected token') -or ($_.RuleName -ne $null -and $_.RuleName -match 'Unexpected') }
if ($errs -and $errs.Count -gt 0) {
    $errs | Select-Object ScriptName,Line,Message | Sort-Object ScriptName,Line | ConvertTo-Json -Compress | Out-File -Encoding utf8 analysis_unexpected.json
    Write-Output "WROTE: analysis_unexpected.json"
} else {
    Write-Output "NO_UNEXPECTED"
}
