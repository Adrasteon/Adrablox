Import-Module PSScriptAnalyzer -ErrorAction Stop
$res = Invoke-ScriptAnalyzer -Path . -Recurse
$writeHostFindings = $res | Where-Object { $_.RuleName -eq 'PSAvoidUsingWriteHost' }
$files = $writeHostFindings | Select-Object -ExpandProperty ScriptPath -Unique
$files | ConvertTo-Json -Depth 5 | Out-File -FilePath analysis_pssa_writehost_files.json -Encoding utf8
Write-Output 'WROTE: analysis_pssa_writehost_files.json'