Import-Module PSScriptAnalyzer -ErrorAction Stop
$res = Invoke-ScriptAnalyzer -Path . -Recurse
$aliases = $res | Where-Object { $_.RuleName -eq 'PSAvoidUsingCmdletAliases' } | Group-Object -Property ScriptPath | Sort-Object Count -Descending | Select-Object Count,@{Name='File';Expression={$_.Name}}
$aliases | ConvertTo-Json -Depth 5 | Out-File -FilePath analysis_pssa_aliases.json -Encoding utf8
Write-Output 'WROTE: analysis_pssa_aliases.json'