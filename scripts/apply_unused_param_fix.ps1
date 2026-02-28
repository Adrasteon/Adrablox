param(
    [string]$Analysis = 'analysis_pssa.json'
)
if (-not (Test-Path $Analysis)) { Write-Output "NO_ANALYSIS_JSON"; exit 0 }
$j = Get-Content $Analysis -Raw | ConvertFrom-Json
$entries = $j | Where-Object { $_.RuleName -eq 'PSReviewUnusedParameter' -and $_.RuleSuppressionID }
$byFile = $entries | Group-Object -Property ScriptPath
foreach ($grp in $byFile) {
    $path = $grp.Name
    if (-not (Test-Path $path)) { Write-Output "Missing file: $path"; continue }
    $params = ($grp.Group | Select-Object -ExpandProperty RuleSuppressionID) | Sort-Object -Unique
    $text = Get-Content -LiteralPath $path -Encoding utf8 -Raw
    $lines = [System.Collections.ArrayList](Get-Content -LiteralPath $path -Encoding utf8)
    $modified = $false
    foreach ($p in $params) {
        $needle = "[void]$p"
        if ($text -match [regex]::Escape($needle)) { continue }
        # find param(...) block
        $startIdx = -1
        for ($i=0;$i -lt $lines.Count;$i++) {
            if ($lines[$i] -match "^\s*param\s*\(") { $startIdx = $i; break }
        }
        if ($startIdx -ge 0) {
            # find matching closing parenthesis
            $depth = 0
            $endIdx = -1
            for ($i=$startIdx;$i -lt $lines.Count;$i++) {
                $line = $lines[$i]
                $depth += ($line -split '\(').Count - 1
                $depth -= ($line -split '\)').Count - 1
                if ($depth -le 0) { $endIdx = $i; break }
            }
            if ($endIdx -ge 0) {
                $insertAt = $endIdx + 1
                $lines.Insert($insertAt, "[void]$p")
                $modified = $true
                Write-Output "Inserted [void]$p into $path at line $($insertAt+1)"
            } else {
                # fallback: insert after first non-empty line
                $lines.Insert(1, "[void]$p")
                $modified = $true
                Write-Output "Inserted [void]$p into $path at fallback position"
            }
        } else {
            # no param block found, insert at top
            $lines.Insert(0, "[void]$p")
            $modified = $true
            Write-Output "Inserted [void]$p into $path at top"
        }
    }
    if ($modified) {
        Copy-Item -Path $path -Destination ($path + '.bak') -Force
        $lines | Set-Content -LiteralPath $path -Encoding utf8
        Write-Output "Patched: $path"
    }
}
Write-Output 'Done'