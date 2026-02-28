$files = Get-Content -Raw -Path analysis_pssa_emptycatch_files.json | ConvertFrom-Json
foreach ($f in $files) {
    if (Test-Path $f) {
        Write-Output "Fixing empty catch in: $f"
        $content = Get-Content -Raw -Path $f
        $new = [regex]::Replace($content, 'catch\s*\{\s*\}', 'catch { Write-Error $_; throw }')
        if ($new -ne $content) { Set-Content -Path $f -Value $new -Encoding UTF8 }
    } else { Write-Output "Missing: $f" }
}
Write-Output 'Done'