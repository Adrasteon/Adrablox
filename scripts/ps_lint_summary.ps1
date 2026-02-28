Import-Module PSScriptAnalyzer -ErrorAction Stop
$res = Invoke-ScriptAnalyzer -Path . -Recurse
$groups = $res | Group-Object -Property ScriptPath | Sort-Object Count -Descending | Select-Object Count,@{Name='File';Expression={$_.Name}}
$groups | ConvertTo-Json -Depth 5 | Out-File -FilePath analysis_pssa_summary.json -Encoding utf8
Write-Output 'WROTE: analysis_pssa_summary.json'