$files = Get-Content -Raw -Path analysis_pssa_writehost_files.json | ConvertFrom-Json
foreach ($f in $files) {
    if (Test-Path $f) {
        Write-Output "Patching: $f"
        (Get-Content -Raw -Path $f) -replace 'Write-Host', 'Write-Output' | Set-Content -Path $f -Encoding UTF8
    } else {
        Write-Output "Missing: $f"
    }
}
Write-Output 'Done'