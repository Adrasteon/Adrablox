Import-Module PSScriptAnalyzer -ErrorAction Stop
$res = Invoke-ScriptAnalyzer -Path . -Recurse
$findings = $res | Where-Object { $_.RuleName -eq 'PSAvoidAssignmentToAutomaticVariable' }
$files = $findings | Select-Object -ExpandProperty ScriptPath -Unique
$files | ConvertTo-Json -Depth 5 | Out-File -FilePath analysis_pssa_assignment_files.json -Encoding utf8
Write-Output 'WROTE: analysis_pssa_assignment_files.json'