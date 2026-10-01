"""The base humanoid every person-shaped unit builds on: a chunky, big-headed figure about 1.5
units tall, its skeleton, a body dressed from an outfit, and the motions every person shares
(standing, breathing, the walk cycle). Gear (gear.py) and unit-specific poses go on top.

    body = humanoid.body({"chest": "team", "skirt": None})
    gear.sword(body, "R")
    rig = sk.build_rig("hero", body)
"""
import math

from mathutils import Quaternion, Vector

import spritekit as sk
from spritekit import at, box, cylinder, lean, make_mesh, raise_, sphere, swing, turn

BONES = {
    # name: (head, tail, parent)
    "root": ((0, 0, 0), (0, 0, 0.25), None),
    "hips": ((0, 0, 0.5), (0, 0, 0.62), "root"),
    "spine": ((0, 0, 0.62), (0, 0, 1.0), "hips"),
    "head": ((0, 0, 1.0), (0, 0, 1.5), "spine"),
    "upperarm.R": ((-0.25, 0, 0.93), (-0.27, 0, 0.72), "spine"),
    "forearm.R": ((-0.27, 0, 0.72), (-0.28, 0, 0.5), "upperarm.R"),
    "upperarm.L": ((0.25, 0, 0.93), (0.27, 0, 0.72), "spine"),
    "forearm.L": ((0.27, 0, 0.72), (0.28, 0, 0.5), "upperarm.L"),
    "thigh.R": ((-0.11, 0, 0.48), (-0.11, 0, 0.28), "hips"),
    "shin.R": ((-0.11, 0, 0.28), (-0.11, 0, 0.06), "thigh.R"),
    "thigh.L": ((0.11, 0, 0.48), (0.11, 0, 0.28), "hips"),
    "shin.L": ((0.11, 0, 0.28), (0.11, 0, 0.06), "thigh.L"),
}
SIDES = (("R", -1), ("L", 1))
ARM = ("root", "hips", "spine", "upperarm.%s", "forearm.%s")

# Landmarks in the rest pose (arms hanging), for fitting gear.
HAND = {"R": Vector((-0.28, 0, 0.5)), "L": Vector((0.28, 0, 0.5))}
SHOULDER = {"R": Vector((-0.25, 0, 0.93)), "L": Vector((0.25, 0, 0.93))}
HEAD_CENTER = Vector((0, 0, 1.22))
HEAD_TOP = 1.42      # top of the skull
FACE_FRONT = -0.2    # y of the face

# What each slot of the body is made of. None leaves the piece out.
OUTFIT = {
    "boots": "dark_leather", "legs": "cloth", "sleeves": "cloth", "forearms": "leather",
    "hands": "skin", "hips": "cloth", "skirt": "cloth", "belt": "leather", "buckle": "gold",
    "chest": "cloth", "collar": "leather", "skin": "skin", "eyes": "eye",
}


def body(outfit=None, shoulders=None):
    """A dressed figure in the rest pose. `shoulders(body, side)` is called between the leg and
    arm pieces of each side (pauldrons), keeping the build order of the original warrior."""
    o = dict(OUTFIT)
    o.update(outfit or {})
    b = sk.Body(BONES)

    def add(slot, name, build, bone, pos, **kw):
        if o[slot] is not None:
            b.add(at(make_mesh(name, build, o[slot], **kw), *pos), bone)

    for side, sx in SIDES:
        add("boots", "boot." + side, box(0.15, 0.24, 0.13), "shin." + side, (sx * 0.11, -0.03, 0.065), bevel=0.035)
        add("legs", "shin." + side, cylinder(0.062, 0.068, 0.2), "shin." + side, (sx * 0.11, 0, 0.2), smooth=True)
        add("legs", "thigh." + side, cylinder(0.07, 0.08, 0.22), "thigh." + side, (sx * 0.11, 0, 0.38), smooth=True)
        if shoulders:
            shoulders(b, side)
        add("sleeves", "sleeve." + side, cylinder(0.058, 0.064, 0.22), "upperarm." + side, (sx * 0.26, 0, 0.82), smooth=True)
        add("forearms", "forearm." + side, cylinder(0.06, 0.055, 0.2), "forearm." + side, (sx * 0.275, 0, 0.62), smooth=True)
        add("hands", "fist." + side, sphere(0.068), "forearm." + side, (sx * 0.28, 0, 0.5), smooth=True)

    add("hips", "hips", box(0.3, 0.2, 0.14), "hips", (0, 0, 0.5), bevel=0.04)
    add("skirt", "skirt", cylinder(0.215, 0.18, 0.2, 8), "hips", (0, 0, 0.5))
    add("belt", "belt", cylinder(0.19, 0.19, 0.055, 8), "hips", (0, 0, 0.615))
    add("buckle", "buckle", box(0.07, 0.03, 0.05), "hips", (0, -0.19, 0.615), bevel=0.01)
    if o["chest"] is not None:
        chest = make_mesh("chest", cylinder(0.18, 0.215, 0.36, 8), o["chest"])
        chest.scale = (1, 0.82, 1)
        b.add(at(chest, 0, 0, 0.82), "spine")
    add("collar", "collar", cylinder(0.12, 0.1, 0.06, 8), "spine", (0, 0, 1.01))

    add("skin", "head", box(0.42, 0.4, 0.4), "head", tuple(HEAD_CENTER), smooth=True, bevel=0.13, segments=3)
    for side, sx in SIDES:
        add("eyes", "eye." + side, sphere(0.032, sz=1.4, segments=8), "head", (sx * 0.085, -0.195, 1.2), smooth=True)
    return b


def arm_rotation(rot, side):
    """Armature-space rotation of a hand's forearm under a set of bone rotations."""
    return sk.chain(rot, [b % side if "%" in b else b for b in ARM])


# --------------------------------------------------------------------------- shared motion

# A relaxed stance to start a unit's own poses from: arms a little out and bent, feet apart.
STAND = {
    "upperarm.R": swing(4) @ raise_("R", 7), "forearm.R": swing(12),
    "upperarm.L": swing(4) @ raise_("L", 7), "forearm.L": swing(12),
    "thigh.R": swing(-2) @ raise_("R", 4), "thigh.L": swing(3) @ raise_("L", 4),
    "shin.R": swing(-3), "shin.L": swing(-4),
}


def breathe(i, n, depth=1.0):
    """Breathing on top of any standing pose: chest rises, head counters, shoulders lift, hips
    settle. Returns (rotation layer for sk.layer, hips offset)."""
    b = math.sin(2 * math.pi * i / n)
    rot = {
        "spine": lean(1.6 * depth * b),
        "head": lean(-1.2 * depth * b),
        "upperarm.R": swing(2.0 * depth * b),
        "upperarm.L": swing(1.5 * depth * b),
    }
    return rot, Vector((0, 0, -0.008 * depth * (1 - math.cos(2 * math.pi * i / n))))


def walk_legs(i, n, stride=26.0, knee=45.0, hip_turn=6.0, bob=0.022, drop=0.012):
    """The lower half of a walk cycle (hips and legs), one stride per n frames. Returns
    (rotations, hips offset, s) where s = sin(phase) swings +1/-1 with the right leg, for
    matching arm swing and counter-twist."""
    p = 2 * math.pi * i / n
    s = math.sin(p)
    rot = {"hips": turn(hip_turn * s)}
    for side, phase in (("R", p), ("L", p + math.pi)):
        rot["thigh." + side] = swing(stride * math.sin(phase))
        rot["shin." + side] = swing(-knee * max(0.0, math.cos(phase)) ** 1.5 - 4)
    return rot, Vector((0, 0, bob * math.cos(2 * p) - drop)), s


def walk(i, n, arm_swing=22.0, lean_deg=6.0, **legs):
    """A plain walk: legs, counter-twisting spine, arms swinging against the legs. Units that
    carry something override the arms."""
    rot, hips, s = walk_legs(i, n, **legs)
    rot.update({
        "spine": lean(lean_deg) @ turn(-6 * s),
        "head": lean(-lean_deg * 0.5) @ turn(2 * s),
        "upperarm.R": swing(-arm_swing * s) @ raise_("R", 7), "forearm.R": swing(18 - 8 * s),
        "upperarm.L": swing(arm_swing * s) @ raise_("L", 7), "forearm.L": swing(18 + 8 * s),
    })
    return sk.pose(rot, {"hips": hips})
