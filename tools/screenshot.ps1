# Renders a screenshot of a scene. Examples:
#   .\tools\screenshot.ps1 -Out shots\city.png -GameArgs "--seed=5","--autoplay=40","--select=city"
#   .\tools\screenshot.ps1 -Scene res://scenes/main_menu.tscn -Out shots\menu.png
param(
    [string]$Out = "screenshot.png",
    [string]$Scene = "res://scenes/game.tscn",
    [string[]]$GameArgs = @(),
    [string]$Godot = ""
)

$project = Split-Path -Parent $PSScriptRoot
if (-not $Godot) {
    $Godot = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot_v4*_console.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Godot) { throw "Godot console executable not found; pass -Godot <path>" }
$outPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Out)).Replace("\", "/")
New-Item -ItemType Directory -Force (Split-Path -Parent $outPath) | Out-Null
& $Godot --path $project $Scene -- @GameArgs "--screenshot=$outPath"
