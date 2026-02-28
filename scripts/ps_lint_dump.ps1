Import-Module PSScriptAnalyzer -ErrorAction Stop
$res = Invoke-ScriptAnalyzer -Path . -Recurse
$res | Select-Object -First 60 | Select-Object RuleName, Message, @{Name='File';Expression={$_.ScriptPath}}, Line, Column | ConvertTo-Json -Depth 5 | Out-File -FilePath analysis_pssa_sample.json -Encoding utf8
Write-Output 'WROTE: analysis_pssa_sample.json'