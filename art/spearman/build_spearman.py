"""Builds the spearman sprite in Blender: the base humanoid (art/lib/humanoid.py) with a pointed
helmet, a long leaf-headed spear and a tall oval shield (art/lib/gear.py), rendered in the six hex
facings by the shared pipeline (art/lib/spritekit.py).

    blender -b --factory-startup --python art/spearman/build_spearman.py [-- --only=idle,walk]

Writes art/spearman/spearman.blend and assets/units/spearman/. At rest the spear stands planted
beside the right foot; the attack lowers it level at the hip and drives it forward. Arm poses that
hold the spear at an angle are fitted with humanoid.reach, so the shaft points where the pose asks.
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

CELL = (208, 196)
ANCHOR = 0.74

sk.COLORS.update({"gambeson": (0.82, 0.75, 0.6)})
OUTFIT = {"boots": "dark_leather", "legs": "cloth", "sleeves": "gambeson", "forearms": "leather",
          "skirt": "leather", "chest": "team", "collar": "gambeson"}

SPEAR = {}   # gear.spear's result, filled in by model()


def model():
    b = humanoid.body(OUTFIT)
    gear.pointed_helmet(b)
    SPEAR.update(gear.spear(b, sk.pose(GUARD), "R"))
    gear.tall_shield(b, "L")
    fit_poses()
    return sk.build_rig("spearman", b)


# --------------------------------------------------------------------------- poses

GUARD = dict(humanoid.STAND, **{
    "spine": lean(3) @ turn(-6),
    "head": turn(6),
    "upperarm.R": swing(16) @ raise_("R", 18),
    "forearm.R": swing(84) @ turn(-10),
    "upperarm.L": swing(30) @ raise_("L", 14),
    "forearm.L": swing(78),
    "thigh.R": swing(-4) @ raise_("R", 5),
    "thigh.L": swing(6) @ raise_("L", 4),
})

# The attack: the spear tips forward, comes level at the hip drawn back, drives forward and rises
# again. Every key holds it beside the right hip (x about -0.4), so it never crosses the body.
LEVEL = dict(GUARD, **{
    "spine": turn(-18), "head": lean(-2) @ turn(16),
    "upperarm.L": swing(40) @ raise_("L", 16), "forearm.L": swing(72),
    "thigh.R": swing(-10) @ raise_("R", 6), "thigh.L": swing(14) @ raise_("L", 6), "shin.L": swing(-10),
})
LEVEL_HIPS = (0, 0, -0.02)
THRUST = dict(GUARD, **{
    "spine": lean(14) @ turn(8), "head": lean(-10) @ turn(-6),
    "upperarm.L": swing(30) @ raise_("L", 22), "forearm.L": swing(66),
    "thigh.R": swing(-18) @ raise_("R", 6), "thigh.L": swing(30) @ raise_("L", 6),
    "shin.L": swing(-26), "shin.R": swing(-8),
})
THRUST_HIPS = (0, -0.04, -0.06)
FIT = {}   # role pose name -> fitted pose (rotations with the spear arm solved)


def fit(name, rot, hand, axis, hips=(0, 0, 0), guess=(20, 10, 0, 40, 0)):
    p, err = humanoid.reach(sk.pose(rot, {"hips": hips}), "R", hand, SPEAR["axis"], axis, guess)
    print("spearman: %s fitted, error %.3f" % (name, err))
    FIT[name] = p["rot"]


def fit_poses():
    fit("tip", GUARD, (-0.39, -0.16, 0.78), (0, -0.55, 0.85), guess=(16, 18, 0, 70, -10))
    fit("level", LEVEL, (-0.4, 0.14, 0.72), (0, -1, -0.04), LEVEL_HIPS, guess=(-5, 20, 0, 40, -10))
    fit("thrust", THRUST, (-0.36, -0.2, 0.8), (0, -1, -0.24), THRUST_HIPS, guess=(30, 18, 0, 40, -10))
    fit("recover", GUARD, (-0.39, -0.12, 0.76), (0, -0.75, 0.66), guess=(10, 18, 0, 50, -10))
    # Walking: the spear carried upright with its butt clear of the ground.
    guard_hand = sk.posed_point(humanoid.BONES, sk.pose(GUARD), "forearm.R", humanoid.HAND["R"])
    fit("carry", GUARD, guard_hand + Vector((0, 0.02, 0.07)), (0, -0.12, 1), guess=(16, 18, 0, 84, -10))


def pose(rot, **locs):
    return sk.pose(rot, {k.replace("__", "."): v for k, v in locs.items()})


def idle(i, n, yaw=0.0):
    breath, hips = humanoid.breathe(i, n)
    rot = sk.layer(GUARD, breath)
    rot = sk.layer(rot, {"head": turn(4 * sk.wave(i, n, phase=1.0))})
    return pose(rot, hips=hips)


def walk(i, n, yaw=0.0):
    rot, hips, s = humanoid.walk_legs(i, n)
    rot.update({
        "spine": lean(6) @ turn(-6 - 6 * s),
        "head": lean(-3) @ turn(6 + 2 * s),
        "upperarm.L": swing(30 + 4 * s) @ raise_("L", 14), "forearm.L": swing(78),
    })
    for arm_bone in ("upperarm.R", "forearm.R"):
        rot[arm_bone] = FIT["carry"][arm_bone]
    return pose(rot, hips=hips)


def attack(i, n, yaw=0.0):
    thrust = pose(FIT["thrust"], hips=THRUST_HIPS)
    return keyed(i, [(0, pose(GUARD)), (1, pose(FIT["tip"])), (2, pose(FIT["level"], hips=LEVEL_HIPS)),
                     (4, thrust), (5.2, thrust), (7, pose(FIT["recover"])), (n, pose(GUARD))])


def hit(i, n, yaw=0.0):
    recoil = dict(GUARD, **{
        "spine": lean(-14) @ turn(-4), "head": lean(-12) @ turn(8),
        "upperarm.L": swing(40) @ raise_("L", 12), "forearm.L": swing(72),
    })
    return keyed(i, [(0, pose(GUARD)), (1, pose(recoil, root=(0, 0.07, 0))), (n, pose(GUARD))])


def fall_spin(yaw):
    """Turn (radians) that points the back along whichever screen horizontal it faces more, so a
    body falling backward lands across the screen in every facing (as the warrior's)."""
    back = Vector((-math.sin(yaw), math.cos(yaw), 0))
    target = Quaternion(Z, -yaw) @ Vector((-1.0 if back.x <= 0 else 1.0, 0, 0))
    spin = math.atan2(target.y, target.x) - math.pi / 2
    return math.atan2(math.sin(spin), math.cos(spin))


def death(i, n, yaw):
    """Buckles and falls onto the back, the spear dropping flat beside the body."""
    spin = fall_spin(yaw)
    back = Quaternion(Z, spin) @ Vector((0, 1, 0))
    twist = math.degrees(spin)
    buckle = dict(GUARD, **{
        "root": turn(twist * 0.3),
        "spine": lean(16) @ turn(-6), "head": lean(18),
        "upperarm.L": swing(20) @ raise_("L", 18), "forearm.L": swing(40),
        "thigh.R": swing(32), "shin.R": swing(-62), "thigh.L": swing(22), "shin.L": swing(-55),
    })
    fall = {
        "root": turn(twist * 0.8) @ lean(-62), "spine": lean(-6), "head": lean(-14),
        "upperarm.R": swing(30) @ raise_("R", 40), "forearm.R": swing(30),
        "upperarm.L": swing(40) @ raise_("L", 65), "forearm.L": swing(60),
        "thigh.R": swing(40), "shin.R": swing(-35), "thigh.L": swing(30), "shin.L": swing(-25),
    }
    lie = dict(fall, **{
        "root": turn(twist) @ lean(-90), "spine": lean(-4), "head": lean(-8) @ turn(20),
        "upperarm.L": swing(5) @ raise_("L", 85), "forearm.L": swing(90),
        "thigh.R": swing(14) @ raise_("R", 6), "shin.R": swing(-10),
        "thigh.L": swing(24) @ raise_("L", 8), "shin.L": swing(-30),
    })
    root = tuple(-back * 0.85 + Vector((0, 0, 0.13)))
    lie_pose = _lying(lie, root, back)
    return keyed(i, [(0, pose(GUARD)), (2, pose(buckle, hips=(0, 0, -0.13))),
                     (4.5, pose(fall, root=tuple(-back * 0.45 + Vector((0, 0, 0.04))), hips=(0, 0, -0.06))),
                     (n - 1, lie_pose)])


_LYING = {}


def _lying(rot, root, back):
    """The lying pose with the spear arm fitted: the hand on the ground beside the shoulder and
    the shaft flat along the body, head end past the head."""
    key = tuple(round(v, 4) for v in back)
    if key not in _LYING:
        p = sk.pose(rot, {"root": root})
        shoulder = sk.posed_point(humanoid.BONES, p, "upperarm.R", humanoid.SHOULDER["R"])
        side = shoulder - sk.posed_point(humanoid.BONES, p, "spine", Vector((0, 0, 0.93)))
        side.z = 0
        hand = shoulder + side.normalized() * 0.15 - back * 0.5
        hand.z = 0.08
        fitted, err = humanoid.reach(p, "R", hand, SPEAR["axis"], back + Vector((0, 0, 0.04)), guess=(10, 60, 0, 20, 0))
        lowest = sk.posed_point(humanoid.BONES, fitted, "forearm.R", SPEAR["tip"])
        print("spearman: lying spear fitted, error %.3f, head tip z=%.3f" % (err, lowest.z))
        _LYING[key] = fitted
    return _LYING[key]


# name: (pose function, frames, loops)
ANIMATIONS = {
    "idle": (idle, 12, True),
    "walk": (walk, 8, True),
    "attack": (attack, 9, False),
    "hit": (hit, 5, False),
    "death": (death, 8, False),
}

sk.build("spearman", model, ANIMATIONS, cell=CELL, anchor=ANCHOR)
