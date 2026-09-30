# Copies the Kenney assets Hexfare uses into res://assets.
# Re-run after adding entries below. All Kenney assets are CC0.
param(
    [string]$KenneyRoot = "E:\Documents\Kenney\Kenney Game Assets All-in-1 3.7.0"
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$hexTiles = Join-Path $KenneyRoot "2D assets\Hexagon Pack\PNG\Tiles\Terrain"
$hexObjects = Join-Path $KenneyRoot "2D assets\Hexagon Pack\PNG\Objects"
$boardIcons = Join-Path $KenneyRoot "Icons\Board Game Icons\PNG\Default (64px)"
$gameIcons = Join-Path $KenneyRoot "Icons\Game Icons\PNG\White\2x"
$fighterIcons = Join-Path $KenneyRoot "Icons\Game Icons Fighter Expansion\PNG\White\2x"
$uiFonts = Join-Path $KenneyRoot "UI assets\UI Pack\Font"

$manifest = @(
    # Terrain tiles (120x140 pointy-top hexes)
    @{ Src = "$hexTiles\Grass"; Dst = "terrain"; Files = @("grass_05", "grass_12", "grass_13", "grass_14", "grass_15", "grass_16") },
    @{ Src = "$hexTiles\Dirt"; Dst = "terrain"; Files = @("dirt_06", "dirt_12", "dirt_13", "dirt_15", "dirt_17", "dirt_18") },
    @{ Src = "$hexTiles\Sand"; Dst = "terrain"; Files = @("sand_07", "sand_13", "sand_16", "sand_17") },
    @{ Src = "$hexTiles\Stone"; Dst = "terrain"; Files = @("stone_07", "stone_12", "stone_13") },
    # Map objects (cities, overlays)
    @{ Src = $hexObjects; Dst = "objects"; Files = @("castle_small", "castle_large", "rockGrey_large", "rockGrey_medium1", "rockGrey_small1") },
    # Icons: units, resources, yields, buildings, UI
    @{ Src = $boardIcons; Dst = "icons"; Files = @(
        "sword", "bow", "shield", "chess_knight", "character", "flag_triangle", "fire",
        "resource_wheat", "resource_iron", "resource_apple", "resource_planks", "tokens", "suit_diamonds",
        "dollar", "flask_full", "flask_half", "award", "crown_a", "pawns", "suit_hearts", "hourglass",
        "structure_farm", "structure_wall", "structure_church", "structure_house", "structure_tower",
        "book_open", "pouch", "skull", "lock_closed", "hexagon_outline", "flag_square") },
    @{ Src = $gameIcons; Dst = "icons"; Files = @("gear", "target", "trophy", "star", "home", "information", "checkmark", "cross") },
    @{ Src = $fighterIcons; Dst = "icons"; Files = @("kick") }
)

foreach ($group in $manifest) {
    $dstDir = Join-Path $project "assets\$($group.Dst)"
    New-Item -ItemType Directory -Force $dstDir | Out-Null
    foreach ($name in $group.Files) {
        Copy-Item -LiteralPath (Join-Path $group.Src "$name.png") -Destination (Join-Path $dstDir "$name.png") -Force
    }
}

$fontDir = Join-Path $project "assets\fonts"
New-Item -ItemType Directory -Force $fontDir | Out-Null
Copy-Item -LiteralPath (Join-Path $uiFonts "Kenney Future.ttf") -Destination $fontDir -Force
Copy-Item -LiteralPath (Join-Path $uiFonts "Kenney Future Narrow.ttf") -Destination $fontDir -Force

Copy-Item -LiteralPath (Join-Path $KenneyRoot "2D assets\Hexagon Pack\License.txt") -Destination (Join-Path $project "assets\LICENSE-kenney.txt") -Force
Write-Output "Kenney assets copied to $project\assets"
