Import-Module PSScriptAnalyzer -ErrorAction Stop
$res = Invoke-ScriptAnalyzer -Path . -Recurse
$rules = $res | Group-Object -Property RuleName | Sort-Object Count -Descending | Select-Object Count,@{Name='Rule';Expression={$_.Name}}
$rules | ConvertTo-Json -Depth 5 | Out-File -FilePath analysis_pssa_rule_summary.json -Encoding utf8
Write-Output 'WROTE: analysis_pssa_rule_summary.json'