$files = Get-Content -Raw -Path analysis_pssa_writehost_files.json | ConvertFrom-Json
foreach ($f in $files) {
    if (-not (Test-Path $f)) { Write-Output "Missing: $f"; continue }
    $bak = "$f.bak"
    if (-not (Test-Path $bak)) { Copy-Item -Path $f -Destination $bak -Force }
    Write-Output "Patching: $f"
    (Get-Content -Raw -Path $f) -replace 'Write-Host', 'Write-Output' | Set-Content -Path $f -Encoding UTF8
}
Write-Output 'Done'