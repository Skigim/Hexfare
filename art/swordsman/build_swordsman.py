"""Builds the swordsman sprite in Blender: the base humanoid (art/lib/humanoid.py) in mail under a
team-coloured surcoat, with pauldrons, a great helm and a two-handed greatsword (art/lib/gear.py),
rendered in the six hex facings by the shared pipeline (art/lib/spritekit.py).

    blender -b --factory-startup --python art/swordsman/build_swordsman.py [-- --only=idle,walk]

Writes art/swordsman/swordsman.blend and assets/units/swordsman/. The sword arm is fitted to each
key pose with humanoid.reach (fist position and blade direction), then the other hand is fitted
onto the grip below it, so both hands stay on the sword.
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

CELL = (208, 184)
ANCHOR = 0.72

sk.COLORS.update({"mail": (0.56, 0.58, 0.62)})
OUTFIT = {"boots": "dark_leather", "legs": "mail", "sleeves": "mail", "forearms": "dark_leather",
          "hips": "mail", "skirt": "team", "chest": "team", "collar": "mail"}

SWORD = {}   # gear.greatsword's result, filled in by model()
FIT = {}     # key pose name -> fitted pose


def model():
    b = humanoid.body(OUTFIT, shoulders=gear.pauldron)
    gear.great_helm(b)
    SWORD.update(gear.greatsword(b, "R"))
    fit_poses()
    return sk.build_rig("swordsman", b)


# --------------------------------------------------------------------------- poses

STANCE = dict(humanoid.STAND, **{
    "spine": lean(4) @ turn(-12),
    "head": turn(10),
    "thigh.R": swing(-8) @ raise_("R", 6),
    "thigh.L": swing(10) @ raise_("L", 5),
    "shin.L": swing(-8),
})
WINDUP = dict(STANCE, **{
    "spine": lean(-8) @ turn(-26), "head": lean(-6) @ turn(20),
    "thigh.R": swing(-12) @ raise_("R", 6), "thigh.L": swing(16) @ raise_("L", 6),
})
STRIKE = dict(STANCE, **{
    "spine": lean(22) @ turn(12), "head": lean(-14) @ turn(-6),
    "thigh.R": swing(-18) @ raise_("R", 6), "thigh.L": swing(28) @ raise_("L", 6),
    "shin.L": swing(-24), "shin.R": swing(-8),
})
STRIKE_HIPS = (0, -0.03, -0.06)
RECOIL = dict(STANCE, **{"spine": lean(-14) @ turn(-16), "head": lean(-12) @ turn(12)})


def two_handed(name, rot, hand, axis, hips=(0, 0, 0), guess=(20, 10, 0, 40, 0), guess_l=(30, 10, 0, 60, 0)):
    """Fits the sword arm (fist at `hand`, blade along `axis`), then the other hand onto the grip."""
    p, err = humanoid.reach(sk.pose(rot, {"hips": hips}), "R", hand, SWORD["axis"], axis, guess)
    grip = sk.posed_point(humanoid.BONES, p, "forearm.R", SWORD["second_hand"])
    p, err_l = humanoid.reach(p, "L", grip, guess=guess_l)
    print("swordsman: %s fitted, sword arm error %.3f, other hand %.3f" % (name, err, err_l))
    FIT[name] = p["rot"]


def fit_poses():
    two_handed("guard", STANCE, (-0.22, -0.24, 0.72), (-0.6, -0.5, 1), guess=(30, 10, 0, 60, 0))
    two_handed("windup", WINDUP, (-0.22, 0.02, 1.32), (0.1, 0.75, 0.45), guess=(150, 20, 0, 60, 0), guess_l=(140, 10, 0, 80, 0))
    two_handed("strike", STRIKE, (-0.08, -0.36, 0.9), (0, -1, -0.15), STRIKE_HIPS, guess=(80, 6, 0, 10, 0))
    two_handed("recoil", RECOIL, (-0.12, -0.24, 0.78), (-0.1, -0.2, 1), guess=(30, 10, 0, 60, 0))
    # Walking: the blade rests on the right shoulder, one hand on the grip, the other arm free.
    p, err = humanoid.reach(sk.pose(STANCE), "R", (-0.2, -0.2, 0.86), SWORD["axis"], (0.05, 0.75, 0.75), guess=(30, 20, 0, 90, 0))
    print("swordsman: carry fitted, error %.3f" % err)
    FIT["carry"] = p["rot"]


def pose(rot, **locs):
    return sk.pose(rot, {k.replace("__", "."): v for k, v in locs.items()})


def idle(i, n, yaw=0.0):
    breath, hips = humanoid.breathe(i, n)
    # The arms ride the spine, so breathing moves both hands together and they stay on the grip.
    rot = sk.layer(FIT["guard"], {k: v for k, v in breath.items() if k in ("spine", "head")})
    rot = sk.layer(rot, {"head": turn(4 * sk.wave(i, n, phase=1.0))})
    return pose(rot, hips=hips)


def walk(i, n, yaw=0.0):
    rot, hips, s = humanoid.walk_legs(i, n)
    rot.update({
        "spine": lean(6) @ turn(-8 - 6 * s),
        "head": lean(-3) @ turn(8 + 2 * s),
        "upperarm.L": swing(22 * s) @ raise_("L", 8), "forearm.L": swing(20 + 8 * s),
    })
    for bone in ("upperarm.R", "forearm.R"):
        rot[bone] = FIT["carry"][bone]
    return pose(rot, hips=hips)


def attack(i, n, yaw=0.0):
    strike = pose(FIT["strike"], hips=STRIKE_HIPS)
    return keyed(i, [(0, pose(FIT["guard"])), (2.5, pose(FIT["windup"])), (4, strike),
                     (5.2, pose(FIT["strike"], hips=(0, -0.035, -0.065))), (n, pose(FIT["guard"]))])


def hit(i, n, yaw=0.0):
    return keyed(i, [(0, pose(FIT["guard"])), (1, pose(FIT["recoil"], root=(0, 0.07, 0))), (n, pose(FIT["guard"]))])


def fall_spin(yaw):
    """Turn (radians) that points the back along whichever screen horizontal it faces more, so a
    body falling backward lands across the screen in every facing (as the warrior's)."""
    back = Vector((-math.sin(yaw), math.cos(yaw), 0))
    target = Quaternion(Z, -yaw) @ Vector((-1.0 if back.x <= 0 else 1.0, 0, 0))
    spin = math.atan2(target.y, target.x) - math.pi / 2
    return math.atan2(math.sin(spin), math.cos(spin))


_LYING = {}


def death(i, n, yaw):
    """Sinks to the knees, then topples onto the back; the sword ends flat beside the body."""
    spin = fall_spin(yaw)
    back = Quaternion(Z, spin) @ Vector((0, 1, 0))
    twist = math.degrees(spin)
    buckle = dict(FIT["guard"], **{
        "root": turn(twist * 0.3),
        "spine": lean(20) @ turn(-8), "head": lean(18),
        "thigh.R": swing(40), "shin.R": swing(-75), "thigh.L": swing(30), "shin.L": swing(-70),
    })
    fall = {
        "root": turn(twist * 0.8) @ lean(-62), "spine": lean(-6), "head": lean(-14),
        "upperarm.R": swing(40) @ raise_("R", 40), "forearm.R": swing(30),
        "upperarm.L": swing(30) @ raise_("L", 55), "forearm.L": swing(40),
        "thigh.R": swing(40), "shin.R": swing(-35), "thigh.L": swing(30), "shin.L": swing(-25),
    }
    lie = dict(fall, **{
        "root": turn(twist) @ lean(-90), "spine": lean(-4), "head": lean(-8) @ turn(20),
        "upperarm.L": swing(8) @ raise_("L", 70), "forearm.L": swing(20),
        "thigh.R": swing(14) @ raise_("R", 6), "shin.R": swing(-10),
        "thigh.L": swing(24) @ raise_("L", 8), "shin.L": swing(-30),
    })
    root = tuple(-back * 0.62 + Vector((0, 0, 0.13)))
    key = tuple(round(v, 4) for v in back)
    if key not in _LYING:
        # The sword arm out to the side, the blade flat on the ground pointing past the head.
        p = sk.pose(lie, {"root": root})
        shoulder = sk.posed_point(humanoid.BONES, p, "upperarm.R", humanoid.SHOULDER["R"])
        side = shoulder - sk.posed_point(humanoid.BONES, p, "spine", Vector((0, 0, 0.93)))
        side.z = 0
        hand = shoulder + side.normalized() * 0.3 - back * 0.1
        hand.z = 0.07
        fitted, err = humanoid.reach(p, "R", hand, SWORD["axis"], back + side.normalized() * 0.5, guess=(10, 70, 0, 10, 0))
        tip = sk.posed_point(humanoid.BONES, fitted, "forearm.R", SWORD["tip"])
        print("swordsman: lying sword fitted, error %.3f, tip z=%.3f" % (err, tip.z))
        _LYING[key] = fitted
    return keyed(i, [(0, pose(FIT["guard"])), (2, pose(buckle, hips=(0, 0, -0.2))),
                     (4.5, pose(fall, root=tuple(-back * 0.45 + Vector((0, 0, 0.04))), hips=(0, 0, -0.06))),
                     (n - 1, _LYING[key])])


# name: (pose function, frames, loops)
ANIMATIONS = {
    "idle": (idle, 12, True),
    "walk": (walk, 8, True),
    "attack": (attack, 9, False),
    "hit": (hit, 5, False),
    "death": (death, 8, False),
}

sk.build("swordsman", model, ANIMATIONS, cell=CELL, anchor=ANCHOR)
