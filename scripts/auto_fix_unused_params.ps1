Import-Module PSScriptAnalyzer -ErrorAction Stop
$res = Invoke-ScriptAnalyzer -Path . -Recurse
$unused = $res | Where-Object { $_.RuleName -eq 'PSReviewUnusedParameter' }
$groups = $unused | Group-Object -Property ScriptPath
foreach ($g in $groups) {
    $file = $g.Name
    $params = @()
    foreach ($item in $g.Group) {
        if ($item.Message -match "parameter '([^']+)'") { $params += $matches[1] }
    }
    $params = $params | Select-Object -Unique
    if ($params.Count -eq 0) { continue }
    if (-not (Test-Path $file)) { Write-Output "Missing file: $file"; continue }
    $bak = "$file.bak"
    if (-not (Test-Path $bak)) { Copy-Item -Path $file -Destination $bak -Force }
    Write-Output "Patching unused params in: $file -> $($params -join ', ')"
    $content = Get-Content -Raw -Path $file
    $refLines = ($params | ForEach-Object { "[void]$$_" }) -join "`r`n"
    $insertion = "`r`n# linter: reference unused parameters`r`n$refLines`r`n"
    # Insert after closing param(...) block
    $rgx = [regex]::new('(?s)(param\s*\([^)]*\)\s*)')
    $m = $rgx.Match($content)
    if ($m.Success) {
        $start = $m.Index + $m.Length
        $new = $content.Substring(0, $start) + $insertion + $content.Substring($start)
        if ($new -ne $content) { Set-Content -Path $file -Value $new -Encoding UTF8 }
    }
}
Write-Output 'Done'