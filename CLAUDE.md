# Hexfare

Generic Civ-style hex strategy framework in Godot 4.7 / GDScript. See README.md for rules,
layout and how to extend the data.

## Commands

Godot 4.7 is installed via WinGet (not on PATH):
`C:\Users\dwigh\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64_console.exe`
(the scripts in `tools/` find it automatically).

- All headless tests: `.\tools\run_tests.ps1` (runs `--import` first; ~25 s). One test: `-Only <name fragment>`.
- UI smoke test (needs a window, drives the real scene with injected input):
  `<godot> --path . res://tests/ui_smoke_test.tscn`
- Screenshot for visual checks: `.\tools\screenshot.ps1 -Out <png> -GameArgs "--seed=5","--autoplay=40","--select=city"`.
  Flags are documented at the top of `scripts/view/game_scene.gd` and in README.md. Look at the
  PNG after UI changes; screenshot mode ignores the real mouse cursor.
- Rebuild the sprite-sheet warrior (Blender 5.1 at `E:\Blender\blender.exe`):
  `E:\Blender\blender.exe -b --factory-startup --python art/warrior/build_warrior.py`, then `--import`.
  Preview: `<godot> --path . res://scenes/sprite_preview.tscn`. `art/` is hidden from Godot (`.gdignore`).
  Shared modelling/animation code is in `art/lib/` (spritekit, humanoid, gear, quadruped); build new
  units from it. After changing it, check the warrior and settler still match: `... build_warrior.py -- --out=<tmp>`
  and compare with `assets/units/warrior/`. **Before making or changing a unit sprite, read
  `docs/DESIGN.md`** (art direction, conventions, the sheet contract and a step-by-step recipe).
- Rebuild the water tiles: `E:\Blender\blender.exe -b --factory-startup --python art/tiles/build_water.py`,
  then `--import`. The other terrain tiles are still Kenney's. Tiles share `art/lib/tilekit.py`; add a
  terrain as another `art/tiles/build_<terrain>.py` and list its names in `data/terrain.json`.
- Run the game: `<godot> --path .` (main menu) or `<godot> --path . res://scenes/game.tscn -- --seed=5`.

## Architecture rules

- `Game` (scripts/core/game.gd) is the only code that mutates `GameState`. UI and AI both go
  through its action methods; add new player actions there.
- Rules live in static modules under `scripts/rules/`; the UI calls the same functions for previews.
- The view (`scripts/view/`, `scripts/ui/`) never mutates state. It re-syncs on `Game.changed`.
- All randomness goes through `state.rng` so games are deterministic (a test checks this).
- Everything saved must be JSON-safe; `Unit.ai` is AI scratch memory and must hold only
  ints/strings/arrays/dictionaries. JSON numbers load as floats: pass loaded data through `Defs.normalize`.
- Content and balance belong in `data/*.json`, not code. New units/buildings/techs need no code;
  the AI picks them up automatically.
- New test suites must be added to `SUITES` in `tests/run_tests.gd`.

## GitHub workflow

Repo: `Skigim/Hexfare` (default branch `main`). See CONTRIBUTING.md.
- Work is tracked as issues under SemVer milestones (`v0.2.0`, ...). Each issue has one type label
  (`bug`, `feature`, `content`, `balance`, `tech-debt`, `docs`, `infra`) and an `area:*` label.
- Put `Closes #n` in the PR body. PRs are squash-merged; branches are `feat/`, `fix/`, `content/`, `art/`.
- Closing a milestone = tag `vMAJOR.MINOR.PATCH` + a GitHub Release.

## GDScript pitfalls seen in this project

- `:=` cannot infer a type from a Variant (dictionary values, untyped array elements, `Array`
  methods): declare the type (`var owner: int = d.owner`).
- Typed arrays: start from a typed variable (`var a: Array[String] = []`); a ternary of array
  literals is not typed.
- `City.buildings` and `Player.techs` are dictionaries (`id -> true`), not arrays.
- Map clicks: convert `event.position` through the canvas transform (`GameScene._event_coord`);
  `get_global_mouse_position()` breaks injected input in tests.
- Don't write files with PowerShell `Set-Content`/`Out-File` (adds a BOM); use the Edit/Write tools.
- A suite that fails to parse shows up as "failed to load"; the parse error is on stderr.
- After adding a `class_name` script or an asset, Godot needs `--import` before `-s` scripts
  can see it (`run_tests.ps1` does this).
