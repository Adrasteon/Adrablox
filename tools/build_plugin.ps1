param(
    [string]$PluginRoot = "plugin/mcp-studio",
    [string]$OutFile = "dist/mcp-studio.rbxmx",
    [string]$PluginName = "mcp-studio"
)

function Ensure-Exists([string]$path) {
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
}

if (-not (Test-Path $PluginRoot)) {
    Write-Error "Plugin root not found: $PluginRoot"
    exit 1
}

$absRoot = (Get-Item $PluginRoot).FullName
$srcRoot = Join-Path $absRoot "src"
$uiRoot = Join-Path $absRoot "ui"
$packaging = Join-Path $absRoot "packaging"
$mainScriptPath = Join-Path $packaging "PluginMain.server.lua"

if (-not (Test-Path $mainScriptPath)) {
    Write-Error "Main plugin script not found: $mainScriptPath"
    exit 1
}

Ensure-Exists (Split-Path $OutFile)

# Gather module files under src and ui, preserving folders
$moduleFiles = @()
if (Test-Path $srcRoot) {
    Get-ChildItem -Path $srcRoot -Recurse -File -Filter *.lua | ForEach-Object {
        $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\','/')
        $moduleFiles += [PSCustomObject]@{ Area = 'src'; Full = $_.FullName; Rel = $rel }
    }
}
if (Test-Path $uiRoot) {
    Get-ChildItem -Path $uiRoot -Recurse -File -Filter *.lua | ForEach-Object {
        $rel = $_.FullName.Substring($uiRoot.Length).TrimStart('\','/')
        $moduleFiles += [PSCustomObject]@{ Area = 'ui'; Full = $_.FullName; Rel = $rel }
    }
}

# Simple tree builder for each area
function Build-Tree([Array]$items) {
    $root = @{}
    foreach ($it in $items) {
        $parts = ($it.Rel -replace '\\','/') -split '/'
        $node = $root
        for ($i = 0; $i -lt $parts.Length - 1; $i++) {
            $p = $parts[$i]
            if (-not $node.ContainsKey($p)) { $node[$p] = @{ __folders = @{}; __files = @() } }
            $node = $node[$p].__folders
        }
        $fileRec = @{ Name = $parts[-1]; Full = $it.Full }
        # attach to the container's __files
        $container = $root
        if ($parts.Length -gt 1) {
            for ($i = 0; $i -lt $parts.Length - 1; $i++) { $container = $container[$parts[$i]] }
        }
        if (-not $container.ContainsKey('__files')) { $container.__files = @() }
        $container.__files += $fileRec
    }
    return $root
}

$srcTree = Build-Tree(($moduleFiles | Where-Object { $_.Area -eq 'src' }))
$uiTree = Build-Tree(($moduleFiles | Where-Object { $_.Area -eq 'ui' }))

# XML builder
$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
$null = $sb.AppendLine('<roblox version="4">')

$refCounter = 0
function NextRef { $script:refCounter += 1; return "R$script:refCounter" }

function Emit-Properties($s, $props) {
    $s.AppendLine('      <Properties>') | Out-Null
    foreach ($k in $props.Keys) {
        $v = $props[$k]
        if ($k -ieq 'Source') {
            $s.AppendLine('        <string name="Source"><![CDATA[') | Out-Null
            $s.AppendLine($v) | Out-Null
            $s.AppendLine(']]></string>') | Out-Null
        } else {
            $esc = [System.Security.SecurityElement]::Escape([string]$v)
            $s.AppendLine('        <string name="' + $k + '">' + $esc + '</string>') | Out-Null
        }
    }
    $s.AppendLine('      </Properties>') | Out-Null
}

function Emit-Module($s, $name, $fullPath, $indent) {
    $ref = NextRef
    $spaces = ' ' * $indent
    $s.AppendLine($spaces + '<Item class="ModuleScript" referent="' + $ref + '">') | Out-Null
    $content = Get-Content -Raw -Encoding UTF8 $fullPath
    Emit-Properties $s @{ Name = $name; Source = $content }
    $s.AppendLine($spaces + '</Item>') | Out-Null
    return $ref
}

function Emit-FolderRecursive($s, $folderName, $node, $indent) {
    $spaces = ' ' * $indent
    $ref = NextRef
    $s.AppendLine($spaces + '<Item class="Folder" referent="' + $ref + '">') | Out-Null
    Emit-Properties $s @{ Name = $folderName }
    # subfolders
    foreach ($sub in $node.__folders.Keys) {
        Emit-FolderRecursive $s $sub $node.__folders[$sub] ($indent + 4)
    }
    # files in this folder
    foreach ($fileRec in $node.__files) {
        Emit-Module $s ([System.IO.Path]::GetFileNameWithoutExtension($fileRec.Name)) $fileRec.Full ($indent + 4)
    }
    $s.AppendLine($spaces + '</Item>') | Out-Null
    return $ref
}

# Emit Plugin top-level
$pluginRef = NextRef
$sb.AppendLine('  <Item class="Plugin" referent="' + $pluginRef + '">') | Out-Null
Emit-Properties $sb @{ Name = $PluginName }

# Emit main Script (PluginMain.server.lua) as Script under Plugin
$mainContent = Get-Content -Raw -Encoding UTF8 $mainScriptPath
$mainRef = NextRef
$sb.AppendLine('    <Item class="Script" referent="' + $mainRef + '">') | Out-Null
Emit-Properties $sb @{ Name = 'PluginMain'; Source = $mainContent }

# Emit src folder as child of Script
if ($srcTree.Keys.Count -gt 0) {
    foreach ($folderName in $srcTree.Keys) {
        Emit-FolderRecursive $sb $folderName $srcTree[$folderName] 6
    }
    if ($srcTree.ContainsKey('__files')) {
        foreach ($fileRec in $srcTree.__files) { Emit-Module $sb ([System.IO.Path]::GetFileNameWithoutExtension($fileRec.Name)) $fileRec.Full 6 }
    }
}

$sb.AppendLine('    </Item>') | Out-Null

# Emit ui folder under Plugin (sibling to Script)
if ($uiTree.Keys.Count -gt 0) {
    foreach ($folderName in $uiTree.Keys) {
        Emit-FolderRecursive $sb $folderName $uiTree[$folderName] 4
    }
    if ($uiTree.ContainsKey('__files')) {
        foreach ($fileRec in $uiTree.__files) { Emit-Module $sb ([System.IO.Path]::GetFileNameWithoutExtension($fileRec.Name)) $fileRec.Full 4 }
    }
}

$sb.AppendLine('  </Item>') | Out-Null

$sb.AppendLine('</roblox>') | Out-Null

$sb.ToString() | Out-File -FilePath $OutFile -Encoding utf8

Write-Output "Wrote $OutFile"
