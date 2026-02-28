param(
    [string]$Analysis = 'analysis_pssa.json'
)
if (-not (Test-Path $Analysis)) { Write-Output "NO_ANALYSIS_JSON"; exit 0 }
$j = Get-Content $Analysis -Raw | ConvertFrom-Json
$entries = $j | Where-Object { $_.RuleName -eq 'PSAvoidUsingCmdletAliases' }
$byFile = $entries | Group-Object -Property ScriptPath
foreach ($grp in $byFile) {
    $path = $grp.Name
    if (-not (Test-Path $path)) { Write-Output "Missing file: $path"; continue }
    $text = Get-Content -Raw -LiteralPath $path -Encoding utf8
    $orig = $text
    foreach ($e in $grp.Group) {
        $alias = $e.Extent.Text
        $corrections = $e.SuggestedCorrections
        if ($alias -and $corrections -and $corrections.Count -gt 0) {
            $replacement = $corrections[0]
            # replace only whole-word occurrences of the alias
            $pattern = "\b" + [regex]::Escape($alias) + "\b"
            $text = [Regex]::Replace($text, $pattern, $replacement)
            Write-Output "Replaced alias $alias -> $replacement in $path"
        }
    }
    if ($text -ne $orig) {
        Copy-Item -Path $path -Destination ($path + '.bak') -Force
        Set-Content -LiteralPath $path -Value $text -Encoding utf8
        Write-Output "Patched: $path"
    }
}
Write-Output 'Done'