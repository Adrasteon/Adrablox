# Replaces empty catch blocks with a minimal logging catch. Creates .bak backups.
param(
    [string]$Path = '.'
)
$pattern = '(?ms)catch\s*\{\s*\}'
Get-ChildItem -Path $Path -Recurse -Include *.ps1 | ForEach-Object {
    $file = $_.FullName
    $text = Get-Content -Raw -LiteralPath $file
    if ($text -match $pattern) {
        Copy-Item -Path $file -Destination ($file + '.bak') -Force
        $replacement = "catch {`r`n    Write-Output 'Ignored error (empty catch) in $($_.Name)'`r`n}"
        $new = [Regex]::Replace($text, $pattern, $replacement)
        Set-Content -LiteralPath $file -Value $new -Encoding utf8
        Write-Output "Patched: $file"
    }
}
Write-Output 'Done'