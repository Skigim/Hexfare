"""Builds the water tiles in Blender: flat blue ground with a few light wave marks, in a deep
(ocean) and a shallow (coast) colour scheme, with several variants of each so a sea does not
repeat. Rendered with the shared tile kit (art/lib/tilekit.py).

    blender -b --factory-startup --python art/tiles/build_water.py [-- --frames=8 --out=<dir>]

Writes assets/terrain/water_<kind>_<variant>.png. The marks stay inside the hex, so neighbouring
tiles never have to line up. Static by default; with --frames=N each mark bobs and sways over one
seamless loop (see tilekit.py for the strip format).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

import tilekit as tk  # noqa: E402

VARIANTS = 4

# kind: ground colour, mark colour, marks per tile
KINDS = {
    "ocean": {"ground": (0.17, 0.40, 0.80), "mark": (0.36, 0.60, 0.92),
              "marks": (3, 4)},
    "coast": {"ground": (0.33, 0.74, 0.88), "mark": (0.68, 0.91, 0.97),
              "marks": (2, 3)},
}


def place_marks(kind, variant, count):
    """Mark positions, spread out and clear of the edges. The same kind and variant always give
    the same tile."""
    rng = random.Random("%s-%d" % (kind, variant))
    area = tk.hex_inset(20)
    marks = []
    for _ in range(400):
        if len(marks) == count:
            break
        x, y = rng.uniform(20, 100), rng.uniform(22, 118)
        if not tk.inside(area, x, y):
            continue
        if any(math.hypot(x - m["x"], y - m["y"]) < 36 for m in marks):
            continue
        marks.append({"x": x, "y": y, "length": rng.uniform(20, 32), "bend": rng.uniform(2.5, 5),
                      "angle": rng.uniform(-14, 14), "phase": rng.random()})
    return marks


def make_tile(kind):
    spec = KINDS[kind]

    def draw(variant, i, n):
        t = i / n
        tk.base(spec["ground"])
        rng = random.Random("%s-%d-count" % (kind, variant))
        marks = place_marks(kind, variant, rng.randint(*spec["marks"]))
        for m in marks:
            # Offsets are relative to frame 0, so frame 0 is exactly the still tile.
            bob = math.sin(2 * math.pi * (t + m["phase"]))
            sway = math.cos(2 * math.pi * (t + m["phase"]))
            still = math.sin(2 * math.pi * m["phase"])
            still_sway = math.cos(2 * math.pi * m["phase"])
            x, y = m["x"] + 1.5 * (sway - still_sway), m["y"] + 1.2 * (bob - still)
            tk.stroke(tk.arc(x, y, m["length"], m["bend"], m["angle"]), 3.6, spec["mark"], layer=1)
            # a shorter swell trailing under it, so each mark reads as a wave rather than a dash
            tk.stroke(tk.arc(x + 9, y + 9, m["length"] * 0.55, m["bend"] * 0.7, m["angle"]), 3.0,
                      spec["mark"], layer=1)
    return draw


if __name__ == "__main__":
    # tilekit.build renders one tile name at a time: ocean first, then coast.
    for kind in KINDS:
        tk.build("water_" + kind, make_tile(kind), VARIANTS)
