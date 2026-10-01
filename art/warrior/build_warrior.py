"""Builds the 2D warrior sprite in Blender: the base humanoid (art/lib/humanoid.py) in a tunic with
helmet, sword and round shield (art/lib/gear.py), its combat poses, rendered in the six hex
facings by the shared pipeline (art/lib/spritekit.py).

    blender -b --factory-startup --python art/warrior/build_warrior.py [-- --only=idle,walk]

Writes art/warrior/warrior.blend and assets/units/warrior/ (sheet, team-colour mask, layout).
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

from mathutils import Quaternion, Vector  # noqa: E402

import gear  # noqa: E402
import humanoid  # noqa: E402
import spritekit as sk  # noqa: E402
from spritekit import Z, keyed, lean, raise_, swing, turn  # noqa: E402

OUTFIT = {"boots": "dark_leather", "legs": "cloth", "sleeves": "team", "forearms": "leather",
          "skirt": "team", "chest": "team"}


def model():
    b = humanoid.body(OUTFIT, shoulders=gear.pauldron)
    gear.helmet(b)
    gear.sword(b, "R")
    gear.round_shield(b, "L")
    return sk.build_rig("warrior", b)


# --------------------------------------------------------------------------- poses

GUARD = {
    "spine": lean(4) @ turn(-10),
    "head": turn(9),
    "upperarm.R": swing(12) @ raise_("R", 12),
    "forearm.R": swing(50),
    "upperarm.L": swing(34) @ raise_("L", 16),
    "forearm.L": swing(70),
    "thigh.R": swing(-5) @ raise_("R", 4),
    "thigh.L": swing(7) @ raise_("L", 4),
    "shin.R": swing(-4),
    "shin.L": swing(-6),
}


def pose(overrides=None, **locs):
    """A full pose: GUARD with some bones replaced, plus bone offsets (armature space)."""
    rot = dict(GUARD)
    rot.update(overrides or {})
    return sk.pose(rot, {k.replace("__", "."): v for k, v in locs.items()})


def idle(i, n, yaw=0.0):
    b = math.sin(2 * math.pi * i / n)
    return pose({
        "spine": lean(4 + 1.6 * b) @ turn(-10),
        "head": lean(-1.2 * b) @ turn(9),
        "upperarm.R": swing(12 + 2.5 * b) @ raise_("R", 12),
        "forearm.R": swing(50 + 3 * b),
        "upperarm.L": swing(34 + 1.5 * b) @ raise_("L", 16),
    }, hips=(0, 0, -0.008 * (1 - math.cos(2 * math.pi * i / n))))


def walk(i, n, yaw=0.0):
    rot, hips, s = humanoid.walk_legs(i, n)
    rot.update({
        "spine": lean(8) @ turn(-10 - 8 * s),
        "head": lean(-4) @ turn(9 + 2 * s),
        "upperarm.R": swing(12 - 22 * s) @ raise_("R", 12),
        "forearm.R": swing(50 + 6 * s),
        "upperarm.L": swing(34 + 5 * s) @ raise_("L", 16),
    })
    return pose(rot, hips=hips)


WINDUP = {
    "spine": lean(-8) @ turn(-24), "head": lean(-6) @ turn(18),
    "upperarm.R": swing(172) @ raise_("R", 14), "forearm.R": swing(75),
    "upperarm.L": swing(40) @ raise_("L", 18),
    "thigh.R": swing(-12) @ raise_("R", 6), "thigh.L": swing(16) @ raise_("L", 6),
}
STRIKE = {
    "spine": lean(20) @ turn(12), "head": lean(-12) @ turn(-6),
    "upperarm.R": swing(58) @ raise_("R", 6), "forearm.R": swing(22),
    "upperarm.L": swing(28) @ raise_("L", 20),
    "thigh.R": swing(-16) @ raise_("R", 6), "thigh.L": swing(26) @ raise_("L", 6),
    "shin.L": swing(-22), "shin.R": swing(-8),
}


def attack(i, n, yaw=0.0):
    return keyed(i, [
        (0, pose()), (2.5, pose(WINDUP)), (4, pose(STRIKE, hips=(0, -0.03, -0.05))),
        (5, pose(dict(STRIKE, **{"spine": lean(23) @ turn(14), "upperarm.R": swing(50) @ raise_("R", 6)}), hips=(0, -0.035, -0.055))),
        (n, pose())])


def hit(i, n, yaw=0.0):
    recoil = {
        "spine": lean(-16) @ turn(-2), "head": lean(-14) @ turn(9),
        "upperarm.L": swing(46) @ raise_("L", 12), "forearm.L": swing(62),
        "upperarm.R": swing(-4) @ raise_("R", 26), "forearm.R": swing(28),
    }
    return keyed(i, [(0, pose()), (1, pose(recoil, root=(0, 0.07, 0))), (n, pose())])


def fall_spin(yaw):
    """Turn (radians) that points the warrior's back along whichever screen horizontal it faces
    more, so a body falling backward lands across the screen in every facing."""
    back = Vector((-math.sin(yaw), math.cos(yaw), 0))
    target = Quaternion(Z, -yaw) @ Vector((-1.0 if back.x <= 0 else 1.0, 0, 0))
    spin = math.atan2(target.y, target.x) - math.pi / 2
    return math.atan2(math.sin(spin), math.cos(spin))


def death(i, n, yaw):
    """Buckles, twists and falls onto the back; ends lying with the shield face-up beside it."""
    spin = fall_spin(yaw)
    back = Quaternion(Z, spin) @ Vector((0, 1, 0))
    twist = math.degrees(spin)
    buckle = {
        "root": turn(twist * 0.3),
        "spine": lean(16) @ turn(-6), "head": lean(18),
        "upperarm.R": swing(18) @ raise_("R", 20), "forearm.R": swing(20),
        "upperarm.L": swing(20) @ raise_("L", 18), "forearm.L": swing(35),
        "thigh.R": swing(32), "shin.R": swing(-62), "thigh.L": swing(22), "shin.L": swing(-55),
    }
    fall = {
        "root": turn(twist * 0.8) @ lean(-62), "spine": lean(-6), "head": lean(-14),
        "upperarm.R": swing(50) @ raise_("R", 55), "forearm.R": swing(20),
        "upperarm.L": swing(40) @ raise_("L", 65), "forearm.L": swing(60),
        "thigh.R": swing(40), "shin.R": swing(-35), "thigh.L": swing(30), "shin.L": swing(-25),
    }
    # Lying on the back: arms out on the ground, the sword turned flat, the shield face-up.
    lie = dict(fall, **{
        "root": turn(twist) @ lean(-90), "spine": lean(-4), "head": lean(-8) @ turn(20),
        "upperarm.R": swing(10) @ raise_("R", 70), "forearm.R": swing(8) @ turn(-90),
        "upperarm.L": swing(5) @ raise_("L", 85), "forearm.L": swing(90),
        "thigh.R": swing(14) @ raise_("R", 6), "shin.R": swing(-10),
        "thigh.L": swing(24) @ raise_("L", 8), "shin.L": swing(-30),
    })
    return keyed(i, [(0, pose()), (2, pose(buckle, hips=(0, 0, -0.13))),
                     (4.5, pose(fall, root=tuple(-back * 0.45 + Vector((0, 0, 0.04))), hips=(0, 0, -0.06))),
                     (n - 1, pose(lie, root=tuple(-back * 0.62 + Vector((0, 0, 0.13)))))])


# name: (pose function, frames, loops)
ANIMATIONS = {
    "idle": (idle, 12, True),
    "walk": (walk, 8, True),
    "attack": (attack, 9, False),
    "hit": (hit, 5, False),
    "death": (death, 8, False),
}

sk.build("warrior", model, ANIMATIONS)
