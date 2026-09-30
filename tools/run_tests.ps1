# Runs the headless test suite. Usage: .\tools\run_tests.ps1 [-Only name_fragment] [-Godot path\to\godot_console.exe]
param(
    [string]$Only = "",
    [string]$Godot = ""
)

$project = Split-Path -Parent $PSScriptRoot
if (-not $Godot) {
    $cmd = Get-Command godot*console* -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $Godot = $cmd.Source }
}
if (-not $Godot) {
    $Godot = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot_v4*_console.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Godot) { throw "Godot console executable not found; pass -Godot <path>" }

# Import first so class_name scripts and textures are registered.
& $Godot --headless --path $project --import *> $null
$testArgs = @("--headless", "--path", $project, "-s", "res://tests/run_tests.gd")
if ($Only) { $testArgs += @("--", "--only=$Only") }
& $Godot @testArgs
exit $LASTEXITCODE
