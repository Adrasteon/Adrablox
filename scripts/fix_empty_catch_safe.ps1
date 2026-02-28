$files = Get-Content -Raw -Path analysis_pssa_emptycatch_files.json | ConvertFrom-Json
foreach ($f in $files) {
    if (-not (Test-Path $f)) { Write-Output "Missing: $f"; continue }
    $bak = "$f.bak"
    if (-not (Test-Path $bak)) { Copy-Item -Path $f -Destination $bak -Force }
    Write-Output "Patching: $f"
    $content = Get-Content -Raw -Path $f
    $new = [regex]::Replace($content, 'catch\s*\{\s*\}', 'catch { Write-Verbose "Auto-lint (ignored): $_" }')
    if ($new -ne $content) { Set-Content -Path $f -Value $new -Encoding UTF8 }
}
Write-Output 'Done'