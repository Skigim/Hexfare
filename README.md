# Hexfare

A deliberately generic, Civilization-style hex strategy game for **Godot 4.7**: found cities,
grow them, research a small tech tree and fight AI opponents on a random hex map. It is meant
as a clean, tested framework to iterate on, not a finished game. Content and balance live in
JSON, the rules are plain GDScript with no scene dependencies, and a headless test suite plays
whole AI games to catch regressions.

![Hexfare mid-game](docs/screenshot.png)

## Quick start

1. Install Godot 4.7 (the standard build; .NET is not needed).
2. In the Godot project manager choose **Import**, select `project.godot` in this folder, then press **F5**.
   From a terminal: `godot --path <this folder>`.
3. On the title screen pick a map size, the number of AI opponents and (optionally) a seed.

First turn: select your settler and press **B** to plan founding your capital, pick a technology,
then press **Enter** to submit the turn. Turns are planned, then resolved all at once: the city
appears when the turn resolves, and the next turn asks what it should build. The big button in the
bottom-right corner always says what still needs a decision.

## Controls

| Input | Action |
|---|---|
| Left-click | Select a unit or city (click again to cycle through what's on the tile) |
| Right-click | Plan a move for the selected unit (onto an enemy: an assault move); with your city selected, plan a bombardment of a unit in range |
| WASD / arrow keys, middle-drag | Pan |
| Mouse wheel | Zoom |
| Tab or `.` | Next unit without an order |
| Space | Skip the unit this turn (no order, and it stops asking) |
| F | Fortify (military) / sleep (civilian) |
| B | Plan founding a city (settler) |
| R | Plan a ranged attack (ranged units only), then click a target tile |
| C | Center the camera on the selection |
| T | Technology tree |
| Enter | Submit the turn (orders resolve) |
| Esc | Close the tech tree / cancel targeting / deselect / pause menu |
| F5 / F9 | Quick save / quick load |
| G | Hex grid |
| F10 | Reveal the whole map (debug) |

The unit panel's **Cancel Order** button drops a unit's planned order. Hovering an enemy with a
unit selected shows the combat forecast: both strengths with a breakdown of every modifier, and
the expected damage each way. Planned orders are drawn on the map as paths.

## Rules at a glance

- **Map**: random continents in three sizes (32×20, 44×28, 56×36). Grassland (2 food), plains
  (1 food, 1 production), desert, tundra (1 food), coast (1 food, 1 gold), ocean (1 food). Hills
  and forest each add 1 production, +3 defense and an extra move cost. Mountains and water are
  impassable; there are no boats.
- **Resources**: bonus (wheat, stone), strategic (horses and iron, hidden until Animal
  Husbandry / Bronze Working and required for horsemen / swordsmen), luxury (gold, gems).
- **Cities**: founded by settlers at least 3 tiles apart; the first one gets the Palace. Each
  citizen eats 2 food and works a tile (picked automatically, food first); surplus food grows the
  city. Culture claims one new tile at a time. Cities build one thing at a time; anything on the
  build list can be bought outright for 3× its production cost in gold (a planned purchase
  is paid for when the turn resolves).
- **Economy**: five yields (food, production, gold, science, culture). Every city adds 1 science
  and 1 culture, plus 0.5 science and 0.5 gold per citizen (rounded down). Buildings cost gold upkeep, and so do
  units beyond 3 free plus 1 per city. Running out of gold disbands a unit.
- **Turns**: every player plans orders, then all orders resolve simultaneously (see
  *Architecture*). Orders to move or found a city persist across turns until done or cancelled.
- **Movement**: Civ V-style. A unit with any moves left may enter any passable tile. Resolution
  runs in ticks of one step per unit; units with higher priority (a hidden per-unit number) claim
  contested tiles first. A blocked unit stops for the turn and keeps its order. Each tile holds
  at most one military and one civilian unit.
- **Combat**: Civ VI-style. Damage = 30 × e^((attack − defense) / 25) × random(0.8–1.2) on a
  100 HP scale. Modifiers: terrain +3, fortified +4, −1 per 10 HP lost, unit bonuses (spearman vs.
  mounted, catapult vs. cities). Ranged units attack a planned tile at the start of resolution,
  all at once, and take no retaliation. Melee units have no attack order: one whose next step
  enters an enemy-held tile (unit or city) attacks instead, whatever its order was, and then stops
  for the turn. Cities have 200 HP (+100 with walls), bombard a planned tile within 2 tiles once
  per turn, and fall to a melee unit that brings them to 0 HP (ranged attacks stop at 1 HP). A
  melee unit that kills a defender advances and captures any civilian there.
- **Technology**: 14 techs in 5 tiers. Choosing a tech deep in the tree queues its prerequisites;
  extra science carries over.
- **Victory**: domination (last civilization standing), science (research every tech) or the
  best score at turn 300. A civilization with no cities and no settlers is eliminated. The tech
  tree is short: AI civilizations usually finish it, and win on science, around turn 80–100.

## Project layout

```
data/            Content and balance (JSON). Start here when iterating.
scenes/          main_menu.tscn and game.tscn (thin: the UI is built in code)
scripts/core/    Game state (map, tiles, units, cities, players), Game (the command API), Orders and TurnResolver
scripts/rules/   Stateless rules: yields, pathfinding, combat, cities, tech, visibility, map generation
scripts/ai/      Rule-based AI opponent
scripts/view/    Map rendering (layers, unit and city views, camera) and the game screen controller
scripts/ui/      HUD panels, theme, main menu
tests/           Headless test suites and a windowed UI smoke test
tools/           PowerShell helpers: run tests, take screenshots, import Kenney assets
assets/          Kenney CC0 art copied from the all-in-one pack
```

## Architecture

- **`GameState`** holds everything that is saved: map, players, units, cities, turn and the RNG.
  These are plain `RefCounted` objects with `to_dict()` / `from_dict()` for JSON saves.
- **Orders.** Players never change the state directly. They *plan*: `Game.issue_order(pid, order)`
  validates an order (`scripts/core/orders.gd`: `move`, `attack`, `found_city`, `fortify`, `sleep`,
  `wake`, `disband` for units; `bombard` and `purchase` for cities) and stores it on the player, one
  per actor and slot. Planning is side-effect-free: it changes no unit, tile, gold or RNG state, and
  helpers such as `move_unit`, `found_city` and `purchase` only plan. `set_production` and
  `set_research` store intent the same way. Illegal orders return `{ok: false, reason}`.
- **Resolution.** `submit_turn(pid)` marks a player ready; when every human is ready the AIs plan
  and `Game.resolve_turn()` runs `TurnResolver`. `Game` is still the only code that changes the
  state, and the resolver is its sanctioned way to do it: ticks (ranged attacks and bombards first,
  then moves in priority order, then city founding), followed by an economy phase (disbands,
  purchases, growth, income, science, healing, eliminations, victory). `end_turn()` is the
  single-player shortcut for submit-and-resolve. Resolution is announced by `turn_resolved(events)`,
  a list of plain-data events.
- **Rules modules** (`Yields`, `Pathfinder`, `Combat`, `CityRules`, `TechRules`, `Visibility`,
  `MapGenerator`) are static functions over the state. The UI calls the same functions for its
  previews (paths, combat odds, turns to build). Previews show the *planned* situation from the
  current positions: other players' orders are hidden and enemies may move, so a forecast fight may
  not happen and an unplanned one may.
- **`AIPlayer`** plans through the same `issue_order` API, so it obeys the same rules as the player,
  and it never reads other players' orders. It does read the whole state, ignoring fog of war.
- **The view never mutates the game.** `MapView.sync()` reconciles the scene with the state after
  `Game.changed`; animations are driven by `turn_resolved` and `combat_resolved`. `GameScene` turns
  input into `Game` calls; HUD panels emit signals that `GameScene` handles.
- **Turn flow**: the human (always player 0) plans and presses Enter; the AIs plan; everything
  resolves at once and the next planning phase begins. `state.time` counts game seconds
  (`rules.turn.seconds` per turn) for the game-time economy to come.
- **Determinism**: all randomness goes through `state.rng`, which is saved with the game, so a
  seed plus the same orders replays identically. Planning never draws from it, and ties (unit
  priority, AI choices) use the integer mixer `Orders.mix`. The simulation tests rely on this.

## Extending

Most additions are data-only. The build list, tech tree and AI pick up new entries
automatically, and `tests/test_data.gd` checks the cross-references and art paths.

**A unit** (`data/units.json`):

```json
"pikeman": {
	"name": "Pikeman", "class": "melee", "icon": "shield", "tech": "construction",
	"cost": 70, "strength": 32, "moves": 2, "sight": 2,
	"bonus_vs": {"mounted": 12}
}
```

`class` is `civilian`, `melee`, `ranged`, `mounted` or `siege`. `cost` is production. Give a unit
`ranged_strength` and `range` to make it ranged. Optional: `tech`, `requires_resource`,
`bonus_vs` (a unit class, or `city`), `abilities` (`["found_city"]`), `pop_cost`.

**A building** (`data/buildings.json`): `name`, `icon`, `tech`, `cost`, `upkeep`, and any of
`yields` (flat), `yield_percent` (percent of the city's total), `defense` (city strength) and `hp`
(city max HP). `"buildable": false` hides it from the build list, like the palace.

**A tech** (`data/techs.json`): `name`, `tier` (the tech-tree column), `cost` (science),
`requires`. Units and buildings point at techs through their `tech` field, and resources through
`reveal_tech`. `tile_bonuses` add yields to matching tiles, e.g. Mining:
`[{"elevation": "hills", "yields": {"production": 1}}]`. A bonus can match on `terrain`,
`elevation`, `feature` and/or `resource`.

**Terrain and resources** (`data/terrain.json`, `data/resources.json`): terrain `art` lists
Kenney tile names per look (`flat`, `forest`, `hills`, `hills_forest`, `mountains`), and a
`"tile+object"` entry draws an object from `assets/objects` on top of the tile. Resources list
the terrains and elevations they spawn on and a relative `weight`.

**Civilizations** (`data/civs.json`): a name, a color and a list of city names.

**Balance** (`data/rules.json`): map sizes and generation ratios, starting units, growth and
border curves, city defense, healing, unit upkeep, combat constants, the purchase multiplier and
which victories are enabled.

**Art**: icons are `assets/icons/<name>.png`. To pull more art from the Kenney pack, add the file
names to the manifest in `tools/import_kenney_assets.ps1` and run it. Water is the exception: it is
rendered in Blender by `E:\Blender\blender.exe -b --factory-startup --python art/tiles/build_water.py`
(~10 s) into `assets/terrain/water_<kind>_<n>.png`. `art/lib/tilekit.py` is the shared tile kit
(hex silhouette, top-down camera, flat shapes, PNG output), so another terrain is a short script
beside `build_water.py`. `-- --frames=N` renders an N-frame loop per tile as a strip plus a
`{"frames", "fps"}` json, for animating later; the game draws still tiles only for now.

**Code-level features** (a new unit ability, a new yield, a new victory type) follow the same
path: add an order type (`Orders`, validated in `Game.validate_order`, carried out in
`TurnResolver`) or a rules-module function, expose it in the relevant HUD panel, teach `AIPlayer`
to plan it, and add a test.

## Tests and tools

```powershell
.\tools\run_tests.ps1                 # all headless suites (~25 s, 10k+ checks)
.\tools\run_tests.ps1 -Only capture   # tests whose name contains "capture"
```

- `test_hex`, `test_data`, `test_rules` and `test_ai` are fast unit tests. `test_simulation`
  plays complete AI games on several seeds and checks invariants (no stacked units, units only
  on land, worked tiles inside their city's borders, and so on), determinism and speed. A full
  round of AI turns takes about 30 ms on a small map and 60 ms on a medium one.
- The UI smoke test boots the real game scene, drives it with injected mouse and keyboard events
  and checks the results (founding, production, research, movement, end turn, save, menus). It
  needs a window: `godot --path . res://tests/ui_smoke_test.tscn`.
- Screenshots for visual checks:
  `.\tools\screenshot.ps1 -Out shots\city.png -GameArgs "--seed=5","--autoplay=40","--select=city"`.
- Sprite-sheet units (the 2D alternative) are built in Blender from scratch by a script:
  `E:\Blender\blender.exe -b --factory-startup --python art/warrior/build_warrior.py` (~1 min) models,
  rigs and animates the warrior, saves `art/warrior/warrior.blend` for hand tweaks, and renders
  idle/walk/attack/hit/death in six facings that point at the hex neighbours into
  `assets/units/warrior/` (sheet, team-colour mask, layout JSON). `-- --only=walk` / `--dirs=se`
  render just some animations or facings into a temp folder for a quick look; `--out=<dir>` writes
  the full sheets elsewhere. Unit scripts are short because the parts are shared, in `art/lib/`:
  `spritekit.py` (materials, meshes, rigs, posing, ropes, camera, rendering, sheets), `humanoid.py`
  (base body dressed from an outfit table, standing, breathing, walk cycle), `gear.py` (helmet,
  sword, shield, hat, cloak, staff...) and `quadruped.py` (a four-legged body sized from a proportions
  table, with a donkey preset, pack saddle and idle). `art/settler/build_settler.py` builds the settler, an adventurer
  leading a pack donkey (two actors in one rig, joined by a rope), with idle, walk and build (it
  hammers the ground with a mallet when founding a city; the city appears on the last blow, timed by
  the sheet's `"marks"`). Settlers never fight, so they have no attack, hit or death; a role a sheet
  lacks plays idle. Poses can show and hide parts (`sk.toggle`: the mallet moves from belt to hand). A sheet's JSON can size the stand drawn under
  the unit (`"base"`). `UnitSprite` (`scripts/view/unit_sprite.gd`) plays
  a sheet with the owner's colour; `res://scenes/sprite_preview.tscn` shows all six facings on hex
  tiles (`--unit=settler`, `--anim=walk`, `--zoom=2`, `--screenshot=out.png`). On the map, any unit with a sheet is drawn as
  a figure on a civ-coloured base (it walks, faces its moves, attacks, flinches and dies); the rest keep
  their tokens. Sheets are VRAM-compressed (BC7 colour, BC4 mask), which the build sets up.

The game scene accepts these flags after `--` (for example
`godot --path . res://scenes/game.tscn -- --seed=5 --autoplay=40`):

| Flag | Effect |
|---|---|
| `--seed=N`, `--size=small\|medium\|large`, `--players=N` | New-game settings |
| `--load` | Start from the quick save instead |
| `--autoplay=N` | The AI plans and submits your civilization's turns for N turns |
| `--reveal` | Reveal the map |
| `--select=city\|unit\|military` | Select your first city / first unit / unit nearest an enemy |
| `--tech`, `--zoom=Z` | Open the tech tree / set the camera zoom |
| `--hover=col,row`, `--hover-enemy`, `--hover-rel=dq,dr` | Hover a tile (shows tile info or the combat forecast) |
| `--screenshot=path.png`, `--delay=S` | Save a screenshot after S seconds (default 1) and quit |

## Not implemented (yet)

Intentionally left out to keep the base small: naval units and embarking, workers and tile
improvements, roads and rivers, happiness, diplomacy and trade, religion, great people, zone of
control, a multi-item build queue, choosing your civilization, and networked multiplayer (turns
are already planned and resolved simultaneously, but there is only one human seat). The AI sees
through fog of war, and resolution plays back every unit's route at once rather than tick by tick.

## Roadmap and contributing

Planned work is tracked in the [milestones](https://github.com/Skigim/Hexfare/milestones) and
[issues](https://github.com/Skigim/Hexfare/issues). See [CONTRIBUTING.md](CONTRIBUTING.md) for the
workflow and labels.

## License

The code and Blender scripts are [MIT](LICENSE). The bundled third-party art is CC0 (below).

## Credits

Art and fonts by [Kenney](https://kenney.nl), CC0 (see `assets/LICENSE-kenney.txt`). Built with [Godot Engine](https://godotengine.org).
