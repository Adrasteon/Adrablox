Import-Module PSScriptAnalyzer -ErrorAction Stop
$res = Invoke-ScriptAnalyzer -Path . -Recurse
$findings = $res | Where-Object { $_.RuleName -eq 'InvalidLeftHandSide' }
$findings | Select-Object @{Name='File';Expression={$_.ScriptPath}}, Line, Column, Message | ConvertTo-Json -Depth 10 | Out-File -FilePath analysis_pssa_invalidlhs.json -Encoding utf8
Write-Output 'WROTE: analysis_pssa_invalidlhs.json'