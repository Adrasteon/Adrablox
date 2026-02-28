Get-ChildItem -Path . -Filter '*.bak' -Recurse | ForEach-Object {
    $bak = $_.FullName
    $orig = $bak -replace '\.bak$',''
    if (Test-Path $orig) {
        Write-Output "Overwriting existing: $orig from $bak"
    } else {
        Write-Output "Restoring new: $orig from $bak"
    }
    Copy-Item -Path $bak -Destination $orig -Force
}
Write-Output 'Done'