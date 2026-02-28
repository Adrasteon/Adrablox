$files = Get-Content -Raw -Path analysis_pssa_emptycatch_files.json | ConvertFrom-Json
foreach ($f in $files) {
    Write-Output "Restoring: $f"
    git checkout -- "$f"
}
Write-Output 'Done'