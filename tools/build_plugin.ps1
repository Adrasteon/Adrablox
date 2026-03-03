param(
    [string]$PluginRoot = "plugin/mcp-studio",
    [string]$OutFile = "dist/mcp-studio.rbxmx",
    [string]$PluginName = "mcp-studio",
    [string]$MainScriptName = "MainScript",
    [string]$PluginBuilderFolderName = "AdrabloxMCP_PluginBuilder",
    [string]$PluginContainerFolderName = "AdrabloxMCP"
)

$ErrorActionPreference = "Stop"

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Escape-Xml([string]$Value) {
    if ($null -eq $Value) {
        return ""
    }
    return [System.Security.SecurityElement]::Escape($Value)
}

$script:RefCounter = 0
function New-Referent {
    $script:RefCounter += 1
    return "RBX$script:RefCounter"
}

function Emit-Properties($Builder, [hashtable]$Properties, [int]$Indent) {
    $spaces = " " * $Indent
    $Builder.AppendLine($spaces + "<Properties>") | Out-Null

    foreach ($key in $Properties.Keys) {
        $value = $Properties[$key]
        if ($key -eq "Source") {
            $Builder.AppendLine($spaces + "  <ProtectedString name=""Source""><![CDATA[") | Out-Null
            $Builder.AppendLine([string]$value) | Out-Null
            $Builder.AppendLine("]]></ProtectedString>") | Out-Null
        }
        else {
            $Builder.AppendLine($spaces + "  <string name=""$key"">" + (Escape-Xml ([string]$value)) + "</string>") | Out-Null
        }
    }

    $Builder.AppendLine($spaces + "</Properties>") | Out-Null
}

function Emit-ModuleScript($Builder, [System.IO.FileInfo]$File, [int]$Indent) {
    $spaces = " " * $Indent
    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    $source = Get-Content -Raw -Encoding UTF8 -LiteralPath $File.FullName
    $ref = New-Referent

    $Builder.AppendLine($spaces + "<Item class=""ModuleScript"" referent=""$ref"">") | Out-Null
    Emit-Properties $Builder @{ Name = $moduleName; Source = $source } ($Indent + 2)
    $Builder.AppendLine($spaces + "</Item>") | Out-Null
}

function Emit-FolderFromDirectory($Builder, [System.IO.DirectoryInfo]$Directory, [int]$Indent) {
    $spaces = " " * $Indent
    $ref = New-Referent

    $Builder.AppendLine($spaces + "<Item class=""Folder"" referent=""$ref"">") | Out-Null
    Emit-Properties $Builder @{ Name = $Directory.Name } ($Indent + 2)

    $childDirectories = Get-ChildItem -LiteralPath $Directory.FullName -Directory | Sort-Object Name
    foreach ($childDir in $childDirectories) {
        Emit-FolderFromDirectory $Builder $childDir ($Indent + 2)
    }

    $childLuaFiles = Get-ChildItem -LiteralPath $Directory.FullName -File -Filter *.lua | Sort-Object Name
    foreach ($childFile in $childLuaFiles) {
        Emit-ModuleScript $Builder $childFile ($Indent + 2)
    }

    $Builder.AppendLine($spaces + "</Item>") | Out-Null
}

function Emit-AreaFolder($Builder, [string]$AreaName, [string]$AreaPath, [int]$Indent) {
    if (-not (Test-Path -LiteralPath $AreaPath)) {
        return
    }

    $spaces = " " * $Indent
    $ref = New-Referent

    $Builder.AppendLine($spaces + "<Item class=""Folder"" referent=""$ref"">") | Out-Null
    Emit-Properties $Builder @{ Name = $AreaName } ($Indent + 2)

    $areaDir = Get-Item -LiteralPath $AreaPath
    $subDirectories = Get-ChildItem -LiteralPath $areaDir.FullName -Directory | Sort-Object Name
    foreach ($subDir in $subDirectories) {
        Emit-FolderFromDirectory $Builder $subDir ($Indent + 2)
    }

    $rootLuaFiles = Get-ChildItem -LiteralPath $areaDir.FullName -File -Filter *.lua | Sort-Object Name
    foreach ($luaFile in $rootLuaFiles) {
        Emit-ModuleScript $Builder $luaFile ($Indent + 2)
    }

    $Builder.AppendLine($spaces + "</Item>") | Out-Null
}

if (-not (Test-Path -LiteralPath $PluginRoot)) {
    throw "Plugin root not found: $PluginRoot"
}

$pluginRootInfo = Get-Item -LiteralPath $PluginRoot
$packagingPath = Join-Path $pluginRootInfo.FullName "packaging"
$mainScriptPath = Join-Path $packagingPath "PluginMain.server.lua"
$srcPath = Join-Path $pluginRootInfo.FullName "src"
$uiPath = Join-Path $pluginRootInfo.FullName "ui"

if (-not (Test-Path -LiteralPath $mainScriptPath)) {
    throw "Main plugin script not found: $mainScriptPath"
}

$outDir = Split-Path -Parent $OutFile
if (-not [string]::IsNullOrWhiteSpace($outDir)) {
    Ensure-Directory $outDir
}

$mainSource = Get-Content -Raw -Encoding UTF8 -LiteralPath $mainScriptPath

$xml = New-Object System.Text.StringBuilder
$xml.AppendLine('<?xml version="1.0" encoding="utf-8"?>') | Out-Null
$xml.AppendLine('<roblox version="4">') | Out-Null

$pluginBuilderRef = New-Referent
$xml.AppendLine("  <Item class=""Folder"" referent=""$pluginBuilderRef"">") | Out-Null
Emit-Properties $xml @{ Name = $PluginBuilderFolderName } 4

$pluginContainerRef = New-Referent
$xml.AppendLine("    <Item class=""Folder"" referent=""$pluginContainerRef"">") | Out-Null
Emit-Properties $xml @{ Name = $PluginContainerFolderName } 6

$mainRef = New-Referent
$xml.AppendLine("      <Item class=""Script"" referent=""$mainRef"">") | Out-Null
Emit-Properties $xml @{ Name = $MainScriptName; Source = $mainSource } 8
$xml.AppendLine('      </Item>') | Out-Null

Emit-AreaFolder $xml "src" $srcPath 8
Emit-AreaFolder $xml "ui" $uiPath 8

$xml.AppendLine('    </Item>') | Out-Null
$xml.AppendLine('  </Item>') | Out-Null
$xml.AppendLine('</roblox>') | Out-Null

$xml.ToString() | Out-File -FilePath $OutFile -Encoding utf8

Write-Output "Wrote $OutFile"