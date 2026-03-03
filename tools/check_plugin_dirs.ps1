$paths = @()
$paths += Join-Path $env:LOCALAPPDATA 'Roblox\Plugins'
$paths += Join-Path $env:APPDATA 'Roblox\Plugins'
$paths += Join-Path $env:USERPROFILE 'Documents\Roblox\Plugins'
$result = @()
foreach ($p in $paths) {
    $exists = Test-Path $p
    $entry = [ordered]@{ path = $p; exists = $exists }
    if ($exists) {
        $files = Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            [ordered]@{ Name = $_.Name; FullName = $_.FullName; Attributes = $_.Attributes.ToString(); Length = ($_.Length -as [long]) }
        }
        $entry.files = $files
    } else {
        $entry.files = @()
    }
    $result += $entry
}
$result | ConvertTo-Json -Depth 5
