Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = 'dist/release/mcp-studio-plugin-source-0.1.0-7609bdf.zip'
$dest = 'dist/release/tmp_plugin'
if (-not (Test-Path $zip)) {
    Write-Host "ZIP not found: $zip"
    exit 1
}
Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue
$z = [System.IO.Compression.ZipFile]::OpenRead($zip)
Write-Host '--- zip entries ---'
$z.Entries | ForEach-Object { Write-Host $_.FullName }
$entries = $z.Entries | Where-Object { $_.FullName -match '^(?i:(src|ui)[\\/]).+' }
foreach ($e in $entries) {
    $target = Join-Path $dest $e.FullName
    $dir = Split-Path $target -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $stream = $e.Open()
    $fs = [System.IO.File]::Create($target)
    $stream.CopyTo($fs)
    $fs.Close()
    $stream.Close()
    Write-Host '---' $e.FullName '---'
    Get-Content -Path $target -TotalCount 120
}
$z.Dispose()
Write-Host '--- filelist ---'
Get-ChildItem -Recurse -File $dest | ForEach-Object { Write-Host $_.FullName }
