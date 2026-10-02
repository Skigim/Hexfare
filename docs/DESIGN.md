# Hexfare design guide

This file explains why Hexfare is built the way it is and gives a step-by-step recipe for adding a
new animated unit. It is written so an agent can follow it without the history behind it. Read
`CLAUDE.md` (commands, architecture rules, GDScript pitfalls) and the README first. This file does
not repeat them.

---

## 1. Philosophy

**A base to iterate on, not a finished game.** Hexfare is a generic Civ-like framework. Every system
should be easy to find, easy to change and easy to extend. Prefer the plain solution that the next
person can read over a clever one.

**Data over code.** Units, buildings, techs and balance live in `data/*.json`. A new unit with
the same behaviour as an existing one needs no code at all, and the AI picks it up automatically.
Code changes only when a unit does something new.

**One mutator, many readers.** `Game` is the only code that changes `GameState`. Rules are static
functions that both the AI and the UI previews call. The view (`scripts/view/`, `scripts/ui/`) only
reads state and plays animations off `Game` signals, so animation can never change the outcome of a
game. If an animation needs to hide something for a moment, the view delays *showing* it, never
*doing* it. For example, a founded city exists at once, but the map fades it in on the settler's
last hammer blow.

**Deterministic and tested.** All randomness goes through `state.rng`. Every rule has a headless
test, and the UI has a smoke test. Art is checked too: `tests/test_data.gd` loads every sprite sheet
and checks its roles, facings and bounds.

**Art is code.** Unit sprites are not drawn by hand. They are modelled, rigged, animated and rendered
by Python scripts run in headless Blender (`art/<unit>/build_<unit>.py` on top of `art/lib/`). This
choice has several benefits:
- Every unit has the same scale, camera, lighting and palette.
- Any unit can be rebuilt after a change to the shared library.
- An agent can make and review art: it writes code, renders, then looks at the PNGs.
- No third-party assets or licences are involved.

The map draws sprite sheets, and units without a sheet fall back to a coloured token.

### Art direction

- **Chunky and toy-like.** Big head, short limbs, simple primitive shapes (boxes with bevels,
  cylinders, spheres). There is no texture detail. Shapes and colour carry everything.
- **Two-band cel shading.** Every material is `sk.toon_material`: a lit colour and a cooler shadow,
  split hard. There are no gradients, textures or specular highlights.
- **The silhouette reads at about 100 px tall.** A humanoid is about 1.5 world units, which comes
  out at about 92 px in the sheet and about 74 px on screen at the default zoom. Thin or small props
  disappear, so exaggerate them:
  - The settler's mallet is half the figure's height.
  - A shovel read as a stick, so it was replaced with an axe.
- **One signature prop or shape per unit.** It says what the unit is at a glance: a big club swung
  two-handed, hat and staff with a donkey. A new unit must not be mistaken for an existing one
  at a glance.
- **Team colour on a large surface visible from every facing.** Examples are the tunic, the cloak and
  the saddle cloth, plus a small accent such as a crest or hat band. Only the material named `"team"`
  is tinted (see "Sheet contract" below).
- **Earthy palette for everything else.** Use leather, wood, steel, cloth and felt from
  `sk.COLORS`. Add new colours with `sk.COLORS.update({...})` and give them names that say what they
  are.
- **Motion is readable, not realistic.** Use big key poses, eased in and out (`sk.keyed`). Prefer
  small looping overlays to stillness: breathing, a head turn, an ear flick, a tail swish. Contacts
  must be right: feet, hooves, staff tips and tools land *on* the ground, not through it or above it.

---

## 2. How the pipeline fits together

```
art/lib/spritekit.py   materials, meshes, Body, rig, posing, solve, ropes, cords, camera, render,
                       sheet assembly
art/lib/humanoid.py    base person: bones, outfit-dressed body, STAND, RIDE, breathe, walk_legs, walk,
                       arm, reach
art/lib/quadruped.py   base four-legged animal from a proportions table (DONKEY, HORSE), halter,
                       pack saddle, riding saddle, stand_idle, walk
art/lib/gear.py        reusable kit: pauldron, helmet, sword, sabre, round_shield, hair, leather_cap,
                       club, great_helm, greatsword, pointed_helmet, spear, tall_shield, cowl, quiver,
                       bow, arrow, loose_arrow, brimmed_hat, feathered_cap, hood, cloak, pouch, staff,
                       mallet, dust_puff
art/<unit>/build_<unit>.py   only what is unique to that unit, ends with sk.build(...)
        |
        |  E:\Blender\blender.exe -b --factory-startup --python art/<unit>/build_<unit>.py
        v
art/<unit>/<unit>.blend                 for looking at or hand-tweaking (not used by the game)
assets/units/<unit>/<unit>.png          colour sheet, all roles x 6 facings
assets/units/<unit>/<unit>_mask.png     white where the team colour goes
assets/units/<unit>/<unit>.json         layout: cell, anchor, fps, directions, animations, marks, base
        |
        v
scripts/view/unit_sprite.gd   UnitSprite: loads a sheet, faces, plays roles, tints with the civ colour
scripts/view/unit_view.gd     UnitView: figure on a civ-coloured stand, badges, walk/attack/death tweens
scripts/view/map_view.gd      MapView: creates UnitViews, reacts to Game signals (moves, combat, founding)
```

The `<unit>` folder name **must** equal the unit's id in `data/units.json`.
`UnitSprite.has_sheet(id)` looks for `assets/units/<id>/<id>.json`. As soon as that file exists,
the unit is drawn as a figure everywhere.

---

## 3. Conventions in Blender space

- **Axes:** Z up. Actors face **-Y**, their right side is at **-X**, and their feet are on the origin.
  The build turns the rig for each facing, so model and pose everything facing -Y.
- **Scale:** fixed for every unit (`sk.PX_PER_UNIT = 160/2.6`). **Never change it.**
  - If a unit needs more room, give it a bigger cell.
  - Use these sizes when fitting things:

    | Part | Size |
    |---|---|
    | Humanoid height | about 1.5 |
    | Top of the skull | `humanoid.HEAD_TOP` (1.42) |
    | Hands at rest | `humanoid.HAND` (z 0.5) |
    | Donkey back | about 0.8 |
- **Camera:** orthographic, looking down at 40°. It renders 6 facings that point at the hex
  neighbours (e, ne, nw, w, sw, se), at 12 fps.
- **Bodies:** a `sk.Body` is a bone table `{name: (head, tail, parent)}` plus parts
  `[(object, bone)]`. Parts are rigid and parented to one bone each; there is no skinning. Model each
  part in the rest pose with `make_mesh` + `box`/`cylinder`/`sphere`/`shell`, then place it:
  - `at(obj, x, y, z)` sets the position.
  - `place(obj, origin, x_axis=…, z_axis=…)` sets the position and orientation.
  - `between(obj, a, b)` points a Z-built cylinder from a to b.

  Then call `body.add(obj, bone)`.
- **A rider:** build the mount, `moved()` it with its prefix, then move the rider so its hips sit
  on the saddle (`quadruped.riding_saddle` returns the seat point) and set its root's parent to the
  mount's body: `rider.bones["root"] = (head, tail, "horse.body")`. Merge the rider *into* the mount
  (`horse.merge(rider)`) so the parent bone is created first. The rider's poses (`humanoid.RIDE`
  for the legs) then move only the person; the mount's walk, rear or fall carries it. See
  `art/horseman/build_horseman.py`.
- **A machine:** a custom `sk.Body` bone table (`root`, a chassis bone, the moving parts as its
  children: wheels with their bone along the axle so `swing` rolls them, a throwing arm with its
  head on the pivot). See `art/catapult/build_catapult.py`.
- **Several actors in one rig:**
  - Build each actor at its own origin.
  - Move the second actor with `actor.moved(offset, prefix="donkey.", scale=…)`.
  - Combine the actors with `a.merge(b)` and call `sk.build_rig(name, merged)` once.
  - Pose the second actor with `sk.prefixed(pose, "donkey.")` and combine the poses with
    `sk.merge(...)`.
  - See `art/settler/build_settler.py`.

### Poses

A pose is `{"rot": {bone: Quaternion}, "loc": {bone: Vector}, "show": {object_name: bool}}`. Make one
with `sk.pose(rot, loc, show)`.

- **Rotations are relative to the parent bone but use the armature's rest axes**, whatever the
  bone's own roll. Use the helpers:

  | Helper | Positive means |
  |---|---|
  | `swing(deg)` | a hanging limb (arm, thigh, forearm, shin, beast leg) swings **forward**. Knees bend with a negative shin swing; elbows bend with a positive forearm swing. |
  | `lean(deg)` | an upright bone (spine, head, root) leans **forward**; a forward-pointing bone (a beast's head) tips **down** |
  | `raise_(side, deg)` | the limb lifts **out to its own side** (`"R"` or `"L"`) |
  | `turn(deg)` | the bone turns toward the actor's **left** |

  Combine them like the existing code does, e.g. `swing(140) @ raise_("R", 52)` or
  `lean(3) @ turn(-6)`.
- **`loc`** offsets a bone in armature space. It is mostly used for `"hips"`: crouching, the walk bob
  and the breathing settle.
- Bones a pose leaves out stay at rest. Start from a stance dictionary and override some bones:
  `dict(humanoid.STAND, **{...})`.
- **Helpers:**

  | Helper | What it does |
  |---|---|
  | `sk.layer(rot, delta)` | adds small rotations on top of a pose (breathing, sway) |
  | `sk.keyed(i, [(frame, pose), ...])` | eases between key poses |
  | `sk.wave(i, n, cycles, phase)` | sine that loops seamlessly over n frames |
  | `sk.pulse(i, n, start, length)` | a one-off 0→1→0 bump (a blink, an ear flick) |
  | `humanoid.breathe(i, n)` | a breathing layer to put on a standing pose |
  | `humanoid.walk_legs(i, n)` / `humanoid.walk(i, n)` | the shared walk cycle |
  | `quadruped.stand_idle(i, n)` / `quadruped.walk(i, n, leg_len=…)` | the animal's idle and walk |
- **Showing and hiding parts:**
  1. Register the object with `sk.toggle(obj, shown_by_default)`.
  2. Set `pose["show"][obj.name]` per frame.

  Use this for a tool that moves from the belt to the hand, or a dust puff on an impact frame.
- **Ropes:** `sk.Rope(name, marker_a, marker_b, slack=…)` connects two `sk.marker` empties parented
  to bones. It re-hangs after every pose.
- **Cords:** `sk.Cord(name, a, b, pull_to)` is a taut string between two markers (a bow string). A
  pose's `"pull"` for it (`sk.pose(rot, loc, pull={name: 0..1})`, blended by `keyed`) draws its
  middle toward the marker `pull_to` (the drawing hand). See `art/archer/build_archer.py`.
- **Fitting to the ground:** `sk.posed_point(bones, pose, bone, rest_point)` returns where a rest-pose
  point ends up in a pose. It is pure maths and runs before anything renders. Use it to solve angles
  so a tool tip, a staff foot or a hoof touches z ≈ 0. See `_fit_strike()` in the settler, which
  searches an arm angle for a target height. Use it instead of guessing angles and re-rendering.
- **Fitting an arm:** `humanoid.reach(pose, side, target, item, axis)` solves one arm's five angles
  so the fist lands on `target` and, given a held item's rest-pose direction (`item`), so the item
  points along `axis`. It returns the pose with that arm replaced and the remaining error; print the
  error from `model()`. Use it for anything held at an angle (a spear thrust, a sword cut, a bow
  held upright), for the second hand on a two-handed grip (fit it to a point on the grip), and for
  a weapon lying flat beside a fallen body. Gear that must stand at an angle in one pose is modelled
  for that pose (`gear.held_axis`, `gear.spear`, `gear.bow`) and its rest-pose axis returned for
  fitting the other poses.
- **Pose functions:** each animation is `f(i, n, yaw) -> pose` for frame `i` of `n`. `yaw` is the
  facing. Most functions ignore it; the warrior's death uses it so the body falls across the screen
  in every facing (`fall_spin`).

---

## 4. The sheet contract (what the game expects)

`sk.build(name, model, ANIMATIONS, cell=(w, h), anchor=…, base=(rx, ry))`:

- **`ANIMATIONS`** maps a role to `(pose_function, frames, loops)` or
  `(pose_function, frames, loops, {"mark": frame})`.
- **`cell`** is the size of one frame in pixels. The default is 128×160, which fits one standing
  humanoid. The settler (person and donkey) uses 160×192.
  - Grow the cell if anything clips the cell edge in **any** facing or frame; walking, deaths and
    raised weapons are the usual culprits.
  - Keep it as small as fits, because sheet memory scales with it.
- **`anchor`** is where the feet sit, as a fraction of the cell height from the top. The default is
  0.78. Lower it (e.g. 0.7) when the unit is wide and needs room below its feet in the south
  facings.
- **`base`** is the radius `(rx, ry)` of the civ-coloured oval stand drawn under the unit, in sheet
  pixels. Leave it unset for a single humanoid. The settler uses (46, 17).
- **Team colour:** any part made with material `"team"` is white in the mask and tinted with the
  owner's colour in game. The colour is multiplied, so `"team"` is the full colour. Only the
  material name `"team"` is tinted (`sk.TEAM`).

Roles the game plays. Times are at 12 fps.

| Role | Who needs it | Frames | Loop | What the game does with it |
|---|---|---|---|---|
| `idle` | everyone | 12–16 | yes | Default. Must loop seamlessly: use `wave`/`pulse` with whole cycles. |
| `walk` | everyone | 8 | yes | One full stride (both legs). The figure moves 0.7 s per hex (`UnitView.SPRITE_STEP_TIME`), about one cycle per hex. |
| `attack` | units that fight | ~9 | no | Melee: the view lunges and the defender flinches at `STRIKE_DELAY` = 0.3 s, so **the blow must land around frame 4**. Ranged: mark the frame the shot leaves as `"release"`; the projectile leaves then and the target flinches when it lands. Afterwards it returns to idle. |
| `hit` | units that fight | ~5 | no | A recoil. The shader adds a white flash. Afterwards it returns to idle. |
| `death` | units that fight | ~8 | no | Holds the last frame. The body lies 1.8 s and then fades. End lying flat, inside the cell, in every facing. |
| `build` | settlers (optional) | 24 | no | Played when founding a city. The `"strike"` mark is when the city, borders and cleared tile appear. |

- **Class rules.** Civilians (`"class": "civilian"`) are captured, never killed, so they only need
  `idle` and `walk` (`UnitSprite.BASIC_ROLES`). Every other class needs all of `UnitSprite.ROLES`, and
  `test_unit_sprite_sheets` enforces this.
- **Missing roles.** A role a sheet lacks plays `idle`.
- **New roles.** An extra role goes in `UnitSprite.EXTRA_ROLES` and needs a hook in
  `UnitView`/`MapView` (see section 6).
- **Marks.** A mark is a named frame the game can time things by. It is read with
  `UnitSprite.mark_time(role, mark)`. Use one whenever an animation and a game event must line up,
  instead of hard-coding seconds in GDScript.

---

## 5. Recipe: adding a new unit

Follow these steps in order. Each step lists the command to run and what "done" looks like. Paths
are relative to the repo root. In the Bash tool, Blender is `/e/Blender/blender.exe`.

### Step 0 — Write the brief (in your head or in the reply, a few lines)

1. **Id and class** from `data/units.json`, e.g. `archer`, `ranged`. This decides the roles
   (section 4).
2. **Concept in one sentence:** for example, "a hooded bowman with a quiver on the back".
3. **Signature prop or shape** that tells it apart from the warrior and the settler.
4. **Where the team colour goes:** a large surface visible from every facing.
5. **Actors:**
   - One humanoid: copy the warrior.
   - A humanoid with an animal: copy the settler.
   - A machine: a custom `sk.Body` bone table.
6. **What is reusable:** each new prop or body feature either goes in `art/lib/` (anything a second
   unit could use: a bow, a spear, a horse preset, a seated pose) or stays in the unit script
   (anything only this unit will ever have).

### Step 1 — Start the build script

Create `art/<id>/build_<id>.py`. Copy the closer template:
- `art/warrior/build_warrior.py` for a single fighter.
- `art/settler/build_settler.py` for two actors, toggled props or marks.

Keep these from the template:
- The header docstring, written for your unit.
- The `sys.path.insert(... "lib")` line and the imports.
- `ANIMATIONS`.
- The final `sk.build("<id>", model, ANIMATIONS, ...)` line.

`model()` must return the rig from `sk.build_rig("<id>", body)`.

Structure it like this:
- **Model:**
  - Call `humanoid.body(OUTFIT)` with an `OUTFIT` dictionary overriding slot materials. Use `None`
    to drop a piece.
  - Add `gear.*` calls.
  - Add new parts with `body.add(...)`.
- **Poses:** a base stance dictionary (like `GUARD` or `LEAD`), built on `humanoid.STAND`.
- **Animations:** one pose function per role. Reuse `humanoid.walk_legs`/`walk` and `breathe` rather
  than writing new cycles.

### Step 2 — Design pass: one facing, idle only

```bash
/e/Blender/blender.exe -b --factory-startup --python art/<id>/build_<id>.py -- --only=idle --dirs=se
```

- It prints `Wrote <temp folder>`. That folder holds `<id>.png`, a one-row strip of idle frames
  facing the viewer.
- Look at it with the Read tool. Upscale it first if it is hard to read (see section 7).
- Check the brief:
  - Is the silhouette clear?
  - Does the prop read?
  - Is the team colour visible?
  - Does anything float, clip into the body or go through the ground?
- Iterate on the model until it reads well.
- **Then show the user that strip (SendUserFile) before animating everything.** The design is the
  part they want to approve. The settler was done this way.

### Step 3 — Animate every role

Add the roles one at a time and check each one in at least two facings that see the actor from
different sides, e.g. `--only=walk --dirs=se,nw`. Then check all facings once:
`--only=walk`, no `--dirs`.

- **Fit contacts with `sk.posed_point`.** Anything that should touch the ground in a pose must be
  fitted this way rather than eyeballed: a weapon striking the ground, a staff, a crouch, a beast's
  hooves. Print the fitted height from `model()` so the build log shows it, as the settler does for
  its staff foot.
- **Melee attack:** the blow lands at frame 4 of about 9.
- **Death:** keep the body inside the cell in all six facings. If it falls backward or sideways,
  copy the warrior's `fall_spin(yaw)` idea.
- **Loops:** make sure looping roles have no jump between the last frame and the first.
  `wave`/`pulse` handle this automatically. With `keyed`, key the last frame equal to the first, or
  stop one frame before it.

### Step 4 — Full build

```bash
/e/Blender/blender.exe -b --factory-startup --python art/<id>/build_<id>.py
```

This writes `art/<id>/<id>.blend` and `assets/units/<id>/` (sheet, mask, JSON, and `.import`
files that ask Godot for VRAM compression). Expected build times:
- A single humanoid with the warrior's roles: about 1 minute.
- A two-actor unit: a few minutes.

Run it in the background if needed. Then check the sheet:
- **Clipping:** check every cell edge (section 7). If anything touches an edge, grow `cell` or move
  `anchor`, then rebuild.
- **Every role:** look at each role's strip in all six facings.

### Step 5 — Bring it into Godot and test

```powershell
.\tools\run_tests.ps1
```

This runs `--import` first. `test_unit_sprite_sheets` automatically checks the new sheet: roles for
its class, six facings, frames in bounds, and the mask matching the sheet.

A ranged unit's sheet must mark its `"release"`; `test_ranged_sheets_mark_their_release` checks it.

### Step 6 — Look at it in Godot

```powershell
& "<godot>" --path . res://scenes/sprite_preview.tscn -- --unit=<id> --screenshot=shots/<id>_preview.png
& "<godot>" --path . res://scenes/sprite_preview.tscn -- --unit=<id> --anim=walk --zoom=2 --screenshot=shots/<id>_walk.png
```

`<godot>` is the path in `CLAUDE.md`. The preview shows the unit on real hex tiles in all six
facings, with the team tint. `res://scenes/unit_gallery.tscn` shows every unit side by side in every
role (`--dir=se`, `--units=archer,warrior`, `--pause` to freeze each role on its key frame,
`--screenshot=<png>`): use it to compare a unit with the others. Read the PNGs and check:
- the size next to the tiles;
- each facing points at its neighbour;
- the stand (`base`) sits under the feet and the figure is not too wide for it;
- the team colour reads on the grass.

If the unit needs game-side wiring (section 6), also check it in the real game with
`tools/screenshot.ps1`, or with a scratch `SceneTree` script that captures timed frames (that is how
the settler's founding was checked).

### Step 7 — If you changed `art/lib/`, prove the old units did not change

```bash
/e/Blender/blender.exe -b --factory-startup --python art/warrior/build_warrior.py -- --out=<scratch>/warrior
/e/Blender/blender.exe -b --factory-startup --python art/settler/build_settler.py -- --out=<scratch>/settler
```

Then compare each pair of files with `assets/units/<unit>/` (section 7):
- The **masks must be identical**.
- The colour sheets may differ in a few dozen pixels of render noise (the warrior differs in about
  27). Anything more means the library change altered an existing unit.

The way to keep this true when extending the library:
- **Add parameters whose defaults reproduce today's output.** Never change an existing default.
- **Never reorder the parts in `humanoid.body`.**
- Put a new colour only in the module that uses it.

### Step 8 — Document and finish

- Add a sentence about the unit to the sprite-sheet paragraph in `README.md`, plus anything new in
  `art/lib/`.
- Update `CLAUDE.md` only if a command or rule changed.
- Don't commit unless asked.
- Leave the generated `.blend`, PNGs, JSON and `.import` files in place: they belong to the commit.

---

## 6. When the game needs code changes

None are needed for a melee or mounted unit with the five standard roles. Code is needed in these
cases:

- **Ranged units** (archer, catapult) are wired: `MapView._on_combat` calls `UnitView.shoot`, which
  faces the target, plays `attack` and returns the `"release"` mark's time; the projectile leaves
  then, and the defender's `struck(from, delay)` (and its death, if it was killed) waits for the
  release plus `MapView.PROJECTILE_TIME`. A new ranged unit only needs the mark.
- **A new role** (e.g. `build` for workers improving a tile):
  1. Add it to `UnitSprite.EXTRA_ROLES`.
  2. Play it from `UnitView`, driven by a `Game` signal that `MapView` connects to.
  3. Time any reveal with a mark.

  Follow the founding pattern: `Game.found_city` emits `city_founded`; `MapView._on_city_founded`
  sets `UnitView.founding`, delays the city's fade-in and hides its borders until the mark; and
  `UnitView.remove` plays `build` and then fades out.
- **A wide or tall unit** sharing a hex or standing in a city: tune the figure offsets in
  `MapView.unit_position`, and give the sheet a `base`.
- **Any new rule or player action:** it goes through `Game`, never the view.

---

## 7. Review helpers (PIL, run with `python`)

The system Python has Pillow. Save scratch scripts and images in the scratchpad, not the repo.

Upscale a strip or sheet for reading:

```python
from PIL import Image
im = Image.open(r"<temp>/<id>.png")
im.resize((im.width * 2, im.height * 2), Image.NEAREST).save(r"<scratch>/<id>_x2.png")
```

One role in one facing as a GIF. The cell index is `first + direction*frames + frame`, and the
directions are `e, ne, nw, w, sw, se`:

```python
import json
from PIL import Image
d = "assets/units/<id>/"; meta = json.load(open(d + "<id>.json")); sheet = Image.open(d + "<id>.png")
w, h = meta["cell"]; cols = meta["columns"]; a = meta["animations"]["walk"]; di = meta["directions"].index("se")
frames = []
for f in range(a["frames"]):
    i = a["first"] + di * a["frames"] + f
    cell = sheet.crop(((i % cols) * w, (i // cols) * h, (i % cols + 1) * w, (i // cols + 1) * h))
    bg = Image.new("RGBA", cell.size, (90, 120, 70, 255)); bg.alpha_composite(cell)
    frames.append(bg.resize((w * 2, h * 2), Image.NEAREST))
frames[0].save(r"<scratch>/walk_se.gif", save_all=True, append_images=frames[1:], duration=1000 // meta["fps"], loop=0)
```

Find cells whose content touches the cell edge, which means it is clipped:

```python
import json
from PIL import Image
d = "assets/units/<id>/"; meta = json.load(open(d + "<id>.json")); alpha = Image.open(d + "<id>.png").getchannel("A")
w, h = meta["cell"]; cols = meta["columns"]
for role, a in meta["animations"].items():
    for di, dname in enumerate(meta["directions"]):
        for f in range(a["frames"]):
            i = a["first"] + di * a["frames"] + f
            x, y = (i % cols) * w, (i // cols) * h
            c = alpha.crop((x, y, x + w, y + h))
            edges = [c.crop((0, 0, w, 1)), c.crop((0, h - 1, w, h)), c.crop((0, 0, 1, h)), c.crop((w - 1, 0, w, h))]
            if any(e.getextrema()[1] > 0 for e in edges):
                print("clipped:", role, dname, f)
```

Compare a rebuild with the committed sheets (section 5, step 7):

```python
from PIL import Image, ImageChops
for name in ("<unit>_mask.png", "<unit>.png"):
    a = Image.open(r"assets/units/<unit>/" + name).convert("RGBA")
    b = Image.open(r"<scratch>/<unit>/" + name).convert("RGBA")
    diff = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 8 else 0)
    print(name, a.size == b.size, sum(1 for v in diff.getdata() if v))
```

---

## 8. Lessons already learned (don't repeat them)

- **Stale world matrices.** Setting `obj.location` doesn't update `matrix_world` until
  `bpy.context.view_layer.update()`. `Body.moved` does this; code of your own that reads
  `matrix_world` must too.
- **Tilted parts.** Rotate tilted parts (a hat, a cloak) about their **attachment point**, not the
  world origin. The hat floated behind the head when its tilt was applied as `tip * z` from z = 0.
  `gear.brimmed_hat` anchors on the brim height.
- **Adjacent parts in one colour merge** into a single blob at sprite size. Give touching parts
  different shades (the hat's brim is `dark_felt`, its crown `felt`).
- **Thin props vanish.** Make props big and give them a distinctive outline: the axe over the
  shovel, and the mallet's 0.5 reach with a fat head.
- **Ears pointing straight up read as horns.** Angle them outward and give them a mid-tone inner
  colour.
- **A second actor hides behind the first** in some facings. Spread the actors apart (settler:
  person at (0.28, -0.5), donkey at (-0.32, 0.36), donkey scaled 1.12) and check all six facings.
- **Walks and swings clip the cell edges.** The settler grew to 160×192 with anchor 0.7. Run the
  clipping check (section 7) on every full build. The warrior's cell is the tightest: its death
  only fits because the fall is centred in the cell (the root ends `back * 0.8` from the feet) and
  the club arm lands last, and its swing only fits because the club stays close to the body (over a
  shoulder at either end, angled up across the front at the blow). Swung level at arm's length it
  would run off the cell in some facing. Don't copy its cell size for a unit with a bigger death or
  a wider swing.
- **A quadruped's body bob must come from its legs.** The dip is
  `leg_len * (1 - cos(stride angle))`, so the hooves stay planted. Adding lean or bob by eye lifts
  the hooves off the ground. If you scale the animal, pass `leg_len=0.52 * scale`.
- **Held items swing into the ground.** The staff went 0.12 below the ground during the hammer blow
  until the other arm's lift was fitted with `posed_point`. Fit every contact, and print the fitted
  value.
- **Small effects read as beads.** Dust made of a few small spheres looked like a necklace. Use
  fewer, bigger, overlapping, flattened puffs, shown for one or two frames.
- **Windows paths in Python strings:** `"art\build"` contains a backspace (`\b`). Use forward
  slashes or raw strings.
- **Don't edit generated files by hand** (sheets, masks, JSON). Change the script and rebuild. The
  `.import` files are written once and then kept, so Godot's compression settings survive rebuilds.
- **EEVEE's shadow pipeline runs even when no light casts shadows.** `setup_scene` turns it off
  (`scene.eevee.use_shadows = False`): the same pixels, about five times faster per frame on a
  software renderer.
- **The arm solver has local minima.** `humanoid.reach` restarts from several natural arm poses
  and keeps the best fit. If an error stays high (more than about 0.1), the target is out of reach
  or fights the item's axis: move the target or give the solver a better `guess`.
- **A body lying toward or away from the camera looks like it is still standing**, because the
  camera looks down at 40°. Every fall must end across the screen: the warrior and the foot units
  spin with `fall_spin`; the horse turns as it rolls so the rider lands across the screen.
- **Long weapons need wide cells.** A spear thrust or a lying spear runs about 1.6 units from the
  feet in the east and west facings. The spearman and swordsman use 208-pixel-wide cells; angle a
  thrust down a little rather than growing the cell further.
- **Big heads dwarf true-scale mounts and machines.** Beside the chunky humanoid a horse or a
  catapult at real proportions looks like a toy. Both are scaled 1.3 with `Body.moved(..., scale=)`;
  scale every distance in their poses (`leg_len`, fall offsets) with them.
- **Keys are blended bone by bone, so held things swing through the body between them.** The
  spearman's spear spun through his head on the way from upright to an overhand thrust, and the
  warrior's old overhead smash passed the club through his head on the way up. Add fitted in-between
  keys that carry the item round the outside (the spearman's `tip`, `level` and `recover`; the
  warrior's swing has a fitted key on every frame that moves), and check every frame, not just the
  keys, for parts passing through each other. A quick
  check: pose the rig in Blender and test each held part against the body with
  `mathutils.bvhtree.BVHTree.overlap`, ignoring the hand that holds it.
- **The rig has no wrist.** A held item is fixed to the forearm, so one modelled for one hold can't
  also sit right in a very different one. The archer's bow is modelled twice and toggled: upright
  for the full draw, and held at the side at rest, its string turned in toward the body (but far
  enough round to miss the arm). The warrior's club is modelled in each hand: with both hands on it,
  the right-hand club can point out to his right but not across to his left (the left arm would
  have to pass through the chest), so the left-hand one takes over once the swing has crossed the
  front.
- **Short arms meet only in front of the chest.** Both fists can share a grip only near the middle
  of the chest, a little in front of it. A two-handed swing keeps the hands there and turns the
  body to carry the weapon round (the warrior's `SWING` table); check that neither arm sinks into
  the chest where it reaches across.
- **Big heads and short arms can't draw a bow to the face.** The string would pass through the
  head. The archer's line of the shot runs beside the head (`AIM_X`), with the bow arm reaching
  across and the drawing hand at the side of the jaw.
- **Peaks hide faces.** The camera looks down at 40°, so a brim or peak sticking out over the brow
  hides the eyes in the front facings. Keep peaks short and high (`gear.feathered_cap`).
- **Curved blades bend toward the holder.** Held upright, the sabre's curve ran into the rider's
  helmet; the resting arm slopes it forward instead.

---

## 9. What exists and what the next units will want

Library inventory (see the docstrings for parameters):

- **`humanoid`:**
  - Bones: `BONES`.
  - Landmarks: `HAND`, `SHOULDER`, `HEAD_CENTER`, `HEAD_TOP`, `FACE_FRONT`.
  - Body: `body(outfit, shoulders)`, `arm_rotation`.
  - Motion: `STAND`, `RIDE` (seated on a mount), `breathe`, `walk_legs`, `walk`.
  - Fitting: `arm(side, ...)` (the five arm angles), `reach` (fist and held item to a target).
- **`gear`:**
  - Warrior kit: `pauldron`, `helmet(crest)`, `sword`, `sabre` (held like the sword, its blade
    curved back toward the spine), `round_shield(face)`.
  - Tribal kit: `hair` (open at the face; `top=False` under a hat), `leather_cap` (a band and
    crossed straps; `hair(top=False)` under it), `club` (studded, held like the sword; `grip=`
    lengthens the handle for a second hand, `name=` builds a second copy to toggle).
  - Swordsman kit: `great_helm`, `greatsword` (returns its blade axis and the second hand's grip).
  - Spearman kit: `pointed_helmet`, `spear` (planted for a given pose), `tall_shield`, `held_axis`.
  - Archer kit: `cowl`, `quiver`, `bow` (upright, or along `up`, for a given pose, with markers for
    a Cord string), `arrow` (nocked for a given pose; toggle it), `loose_arrow` (an arrow anywhere on
    any bone: one in flight).
  - Clothing: `brimmed_hat`, `feathered_cap`, `hood`, `cloak`, `pouch`.
  - Tools: `staff` (planted for a given pose), `mallet` (hand or belt) and `mallet_head`.
  - Effects: `dust_puff`.
- **`quadruped`:**
  - Body: `DONKEY` and `HORSE` proportions (optional keys: knee height, leg thickness, neck, mane,
    tail, sock colour), `bones(d)`, `body(d)`.
  - Kit: `halter` (returns the rope tie marker), `saddle_cloth`, `pack_saddle`, `riding_saddle`
    (returns the seat point).
  - Motion: `stand_idle`, `walk` (pass a bigger `stride` and `knee` for a trot).
- **`spritekit`:** see section 3 (`solve` is the small optimiser behind `reach`; `Cord` is a taut
  string).

Every unit in `data/units.json` now has a sheet:

| Unit | Class | Built from | Notes |
|---|---|---|---|
| warrior | melee | humanoid, tribal kit | big studded club swung two-handed across the front, every key fitted with `reach`; the club is modelled in each hand and toggled |
| settler | civilian | humanoid, quadruped (donkey), rope | `build` role with a `"strike"` mark |
| spearman | melee | humanoid, spearman kit | spear lowered to the hip and thrust forward, every key fitted with `reach` beside the hip |
| swordsman | melee | humanoid, swordsman kit | both hands fitted to the grip in every key pose |
| archer | ranged | humanoid, archer kit, feathered cap, `Cord` strings | side-on draw beside the head; two bows toggled (drawn, resting); the loosed arrow shows on the `"release"` frame |
| horseman | mounted | quadruped (horse, scaled 1.3), humanoid rider parented to `horse.body` | sabre; trot, rear on attack, rolls over on death |
| catapult | siege | custom engine `sk.Body` (scaled 1.3), humanoid crewman with a mallet | `"release"` mark; wheels roll a quarter turn per stride |

A new unit that looks like one of these should start from its script. A new mount (an elephant, a
camel) is a new proportions table in `quadruped` plus the horseman's rider setup; a new machine
(a ram, a ballista) follows the catapult.
