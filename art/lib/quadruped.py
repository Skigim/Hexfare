"""The base four-legged animal: skeleton, body and shared motion, sized from a proportions table
so one build serves a donkey, a horse or an ox. Same conventions as the humanoid (faces -Y, feet
at the origin); a unit puts it beside a rider or handler with Body.moved(offset, prefix).

    beast = quadruped.body(quadruped.DONKEY)
    quadruped.pack_saddle(beast)
"""
import math

from mathutils import Vector

import spritekit as sk
from spritekit import X, Y, at, between, box, cylinder, lean, make_mesh, place, shell, sphere, swing, turn

sk.COLORS.update({
    "donkey": (0.6, 0.55, 0.52), "donkey_light": (0.92, 0.89, 0.84), "donkey_dark": (0.3, 0.26, 0.25),
    "donkey_inner": (0.76, 0.71, 0.68),
    "hoof": (0.22, 0.2, 0.19),
})

# Proportions (world units; the humanoid is about 1.5 tall) and coat colours. A chunky,
# toy-like donkey: big head, long ears, short legs.
DONKEY = {
    "barrel": (0.19, 0.41, 0.2), "barrel_z": 0.6, "front_y": -0.25, "hind_y": 0.27, "leg_x": 0.1,
    "neck": ((0, -0.3, 0.68), (0, -0.42, 0.93)), "head_len": 0.3, "head_dir": (0, -0.26, -0.1),
    "head_size": (0.17, 0.34, 0.19), "ear_len": 0.3, "tail": ((0, 0.42, 0.68), (0, 0.47, 0.4)),
    "coat": "donkey", "light": "donkey_light", "dark": "donkey_dark", "inner": "donkey_inner", "hoof": "hoof",
}

SIDES = (("R", -1), ("L", 1))
LEGS = (("FR", -1, "front_y"), ("FL", 1, "front_y"), ("HR", -1, "hind_y"), ("HL", 1, "hind_y"))


def bones(d):
    neck_a, neck_b = (Vector(v) for v in d["neck"])
    head_dir = Vector(d["head_dir"]).normalized()
    head_end = neck_b + head_dir * d["head_len"]
    z = d["barrel_z"]
    out = {
        "root": ((0, 0, 0), (0, 0, 0.2), None),
        "body": ((0, d["hind_y"] + 0.03, z), (0, d["front_y"] - 0.05, z + 0.02), "root"),
        "neck": (tuple(neck_a), tuple(neck_b), "body"),
        "head": (tuple(neck_b), tuple(head_end), "neck"),
        "tail": (d["tail"][0], d["tail"][1], "body"),
    }
    for side, sx in SIDES:
        ear = neck_b + Vector((sx * 0.055, 0.02, 0.07))
        out["ear." + side] = (tuple(ear), tuple(ear + Vector((sx * 0.1, 0.03, 1)).normalized() * d["ear_len"]), "head")
    for leg, sx, key in LEGS:
        x, y = sx * d["leg_x"], d[key]
        hind = leg[0] == "H"
        top, knee = z - 0.06 + (0.03 if hind else 0), 0.28
        out["leg." + leg] = ((x, y, top), (x, y + (0.02 if hind else 0), knee), "body")
        out["shin." + leg] = ((x, y + (0.02 if hind else 0), knee), (x, y, 0.03), "leg." + leg)
    return out


def body(d=DONKEY):
    b = sk.Body(bones(d))
    coat, light, dark = d["coat"], d["light"], d["dark"]
    rx, ry, rz = d["barrel"]
    z = d["barrel_z"]
    b.add(at(make_mesh("barrel", sphere(1.0, sx=rx, sy=ry, sz=rz, segments=16), coat, smooth=True), 0, 0.02, z), "body")
    b.add(at(make_mesh("belly", sphere(1.0, sx=rx * 0.88, sy=ry * 0.8, sz=rz * 0.75, segments=14), light, smooth=True), 0, 0.0, z - 0.07), "body")

    neck_a, neck_b = (Vector(v) for v in d["neck"])
    b.add(between(make_mesh("neck", cylinder(0.105, 0.085, (neck_b - neck_a).length + 0.1, 10), coat, smooth=True),
                  neck_a - (neck_b - neck_a).normalized() * 0.05, neck_b + (neck_b - neck_a).normalized() * 0.05), "neck")
    back = Vector((0, 0.065, 0.03))   # the mane runs along the back of the neck
    b.add(between(make_mesh("mane", box(0.04, 0.05, (neck_b - neck_a).length + 0.06), dark, bevel=0.015),
                  neck_a + back, neck_b + back + Vector((0, 0, 0.05)), roll_x=X), "neck")

    hd = Vector(d["head_dir"]).normalized()
    hx, hy, hz = d["head_size"]
    head = make_mesh("head", box(hx, hy, hz), coat, smooth=True, bevel=0.06, segments=2)
    place(head, neck_b + hd * (hy * 0.42), x_axis=X, y_axis=hd)
    b.add(head, "head")
    muzzle = make_mesh("muzzle", sphere(1.0, sx=hx * 0.5, sy=hy * 0.3, sz=hz * 0.46, segments=12), light, smooth=True)
    place(muzzle, neck_b + hd * (hy * 0.8) + Vector((0, 0, -0.015)), x_axis=X, y_axis=hd)
    b.add(muzzle, "head")
    for side, sx in SIDES:
        b.add(at(make_mesh("nostril." + side, sphere(0.014, segments=6), dark), *(neck_b + hd * (hy * 1.05) + Vector((sx * 0.035, 0, 0.0)))), "head")
        b.add(at(make_mesh("eye." + side, sphere(0.026, sz=1.3, segments=8), "eye", smooth=True), *(neck_b + hd * 0.1 + Vector((sx * hx * 0.5, 0, 0.05)))), "head")
        ear_a, ear_b = (Vector(v) for v in b.bones["ear." + side][:2])
        along = (ear_b - ear_a).normalized()
        ear = make_mesh("ear." + side, cylinder(0.05, 0.022, d["ear_len"], 8), coat, smooth=True)
        between(ear, ear_a, ear_a + along * d["ear_len"], roll_x=X)
        ear.scale = (1, 0.55, 1)
        b.add(ear, "ear." + side)
        inner = make_mesh("ear_inner." + side, cylinder(0.03, 0.01, d["ear_len"] * 0.7, 8), d["inner"], smooth=True)
        between(inner, ear_a + along * 0.05 - Y * 0.014, ear_a + along * d["ear_len"] * 0.75 - Y * 0.014, roll_x=X)
        inner.scale = (1, 0.4, 1)
        b.add(inner, "ear." + side)
        tip = make_mesh("ear_tip." + side, cylinder(0.024, 0.0, 0.07, 6), dark)
        between(tip, ear_a + (ear_b - ear_a).normalized() * (d["ear_len"] - 0.04), ear_a + (ear_b - ear_a).normalized() * (d["ear_len"] + 0.03), roll_x=X)
        b.add(tip, "ear." + side)
    b.add(at(make_mesh("forelock", box(0.06, 0.05, 0.05), dark, bevel=0.015), *(neck_b + Vector((0, -0.02, 0.09)))), "head")

    tail_a, tail_b = (Vector(v) for v in d["tail"])
    b.add(between(make_mesh("tail", cylinder(0.03, 0.018, (tail_b - tail_a).length, 6), coat, smooth=True), tail_a, tail_b), "tail")
    b.add(at(make_mesh("tail_tuft", sphere(0.04, sz=1.9, segments=8), dark, smooth=True), *(tail_b + Vector((0, 0.005, -0.03)))), "tail")

    for leg, sx, key in LEGS:
        hind = leg[0] == "H"
        top, knee, foot = (Vector(v) for v in (b.bones["leg." + leg][0], b.bones["leg." + leg][1], b.bones["shin." + leg][1]))
        upper = cylinder(0.05, 0.085 if hind else 0.065, (top - knee).length + 0.06, 8)
        b.add(between(make_mesh("leg." + leg, upper, coat, smooth=True), knee - Vector((0, 0, 0.03)), top + Vector((0, 0, 0.03))), "leg." + leg)
        b.add(between(make_mesh("shin." + leg, cylinder(0.038, 0.046, (knee - foot).length, 8), coat, smooth=True), foot, knee), "shin." + leg)
        b.add(at(make_mesh("hoof." + leg, cylinder(0.05, 0.043, 0.06, 8), d["hoof"]), foot.x, foot.y - 0.01, 0.03), "shin." + leg)
    return b


def halter(b, d=DONKEY, mat="leather"):
    """Head collar: a noseband and a strap behind the ears. Returns the marker under the chin
    where a lead rope ties on."""
    neck_b = Vector(d["neck"][1])
    hd = Vector(d["head_dir"]).normalized()
    hx, hy, hz = d["head_size"]
    for name, along, r in (("noseband", 0.62, 1.0), ("headstall", 0.06, 1.12)):
        c = neck_b + hd * (hy * along) + Vector((0, 0, -0.01))
        strap = make_mesh(name, shell(1.0, 1.0, 0.035, keep=lambda co: True, segments=14), mat)
        strap.scale = (hx * 0.62 * r, hz * 0.62 * r, 1)
        between(strap, c - hd * 0.0175, c + hd * 0.0175, roll_x=X)
        b.add(strap, "head")
    ring = neck_b + hd * (hy * 0.62) + Vector((0, 0, -hz * 0.62))
    b.add(at(make_mesh("halter_ring", sphere(0.018, segments=6), "dark_steel"), *ring), "head")
    return b.add(sk.marker("lead_tie", ring), "head")


def saddle_cloth(b, d=DONKEY, mat="team", length=0.36):
    rx, ry, rz = d["barrel"]
    obj = make_mesh("saddle_cloth", shell(rz + 0.012, rz + 0.012, length, keep=lambda co: co.y < 0.11, segments=18), mat, smooth=True)
    place(obj, Vector((0, -0.02, d["barrel_z"])), x_axis=X, z_axis=Y)
    obj.scale = (rx / rz + 0.04, 1, 1)
    return b.add(obj, "body")


def pack_saddle(b, d=DONKEY, cloth="team"):
    """Saddle cloth, girth, a leather pannier on each side, a bedroll across the top, a cooking
    pot and a shovel: a settler's kit."""
    rx, ry, rz = d["barrel"]
    z = d["barrel_z"]
    saddle_cloth(b, d, cloth)
    girth = make_mesh("girth", shell(1.0, 1.0, 0.045, keep=lambda co: True, segments=18), "dark_leather")
    girth.scale = (rx + 0.016, rz + 0.016, 1)
    between(girth, Vector((0, -0.11, z)), Vector((0, -0.065, z)), roll_x=X)
    b.add(girth, "body")
    for side, sx in SIDES:
        bag = b.add(at(make_mesh("pannier." + side, box(0.1, 0.25, 0.21), "leather", bevel=0.035), sx * (rx + 0.06), -0.02, z - 0.02), "body")
        bag.rotation_euler = (0, sx * math.radians(-8), 0)
        b.add(at(make_mesh("pannier_flap." + side, box(0.11, 0.22, 0.06), "dark_leather", bevel=0.02), sx * (rx + 0.075), -0.02, z + 0.07), "body")
    roll = make_mesh("bedroll", cylinder(0.072, 0.072, 0.44, 12), "linen", smooth=True)
    place(roll, Vector((0, 0.03, z + rz + 0.06)), x_axis=Y, z_axis=X)
    b.add(roll, "body")
    for x in (-0.12, 0.12):
        strap = make_mesh("bedroll_strap", cylinder(0.076, 0.076, 0.025, 12), "dark_leather")
        place(strap, Vector((x, 0.03, z + rz + 0.06)), x_axis=Y, z_axis=X)
        b.add(strap, "body")
    b.add(at(make_mesh("pot", cylinder(0.065, 0.06, 0.08, 10), "dark_steel", smooth=True), -(rx + 0.12), -0.13, z - 0.06), "body")
    b.add(at(make_mesh("pot_rim", cylinder(0.07, 0.07, 0.012, 10), "dark_steel"), -(rx + 0.12), -0.13, z - 0.02), "body")
    # A wood axe tucked under the right pannier's flap, head up by the bedroll.
    lo, hi = Vector((-(rx + 0.1), 0.12, z - 0.1)), Vector((-(rx + 0.07), -0.02, z + 0.26))
    b.add(between(make_mesh("axe_handle", cylinder(0.017, 0.017, (hi - lo).length, 6), "wood"), lo, hi), "body")
    head = make_mesh("axe_head", box(0.02, 0.1, 0.07), "dark_steel", bevel=0.008)
    place(head, hi + Vector((0, -0.04, -0.02)), x_axis=X, z_axis=(hi - lo).normalized())
    b.add(head, "body")


# --------------------------------------------------------------------------- shared motion

def stand_idle(i, n, tail_cycles=1, ear_twitch=(9, 4), nod=3.0):
    """Standing still: breathing, a slow head nod, the tail swishing, one ear flicking. Returns
    a pose on this beast's own (unprefixed) bones."""
    b = sk.wave(i, n)
    flick = sk.pulse(i, n, *ear_twitch)
    rot = {
        "body": lean(0.8 * b),
        "neck": lean(-1.5 * b),
        "head": lean(nod * sk.wave(i, n, phase=0.8)),
        "tail": turn(16 * sk.wave(i, n, tail_cycles, 0.4)) @ swing(-6),
        "ear.R": sk.quat(X, -28 * flick) @ sk.quat(Y, -12 * flick),
        "ear.L": sk.quat(X, -4 * b),
    }
    return sk.pose(rot, {"body": (0, 0, 0.004 * b)})


def walk(i, n, stride=22.0, knee=40.0, leg_len=0.52):
    """A walk cycle with the diagonal legs moving together (front right with hind left), one
    stride per n frames: legs swing and fold, the body dips as the planted legs slant (keeping
    their hooves on the ground; the legs hang from the body), the head nods and the tail sways."""
    p = 2 * math.pi * i / n
    rot = {}
    for leg, phase in (("FR", p), ("HL", p), ("FL", p + math.pi), ("HR", p + math.pi)):
        rot["leg." + leg] = swing(stride * math.sin(phase))
        rot["shin." + leg] = swing(-knee * max(0.0, math.cos(phase)) ** 1.5)
    rot.update({
        "neck": lean(-2 * math.cos(2 * p)),
        "head": lean(4 * math.cos(2 * p + 0.6)),
        "tail": turn(10 * math.sin(p)) @ swing(-10),
        "ear.R": sk.quat(X, -6 * math.sin(2 * p)),
        "ear.L": sk.quat(X, -6 * math.sin(2 * p + 0.5)),
    })
    dip = leg_len * (1 - math.cos(math.radians(stride * math.sin(p))))
    return sk.pose(rot, {"body": (0, 0, -dip)})
