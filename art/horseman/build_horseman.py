"""Builds the horseman sprite in Blender: a rider (the base humanoid with a crested helmet, a sword
and a short team-coloured cloak) on a horse (the base quadruped with the HORSE proportions and a
riding saddle on a team-coloured cloth), holding the reins, rendered in the six hex facings by the
shared pipeline (art/lib/spritekit.py).

    blender -b --factory-startup --python art/horseman/build_horseman.py [-- --only=idle,walk]

Writes art/horseman/horseman.blend and assets/units/horseman/. The rider's root bone is parented
to the horse's body bone, so the rider follows every step, rear and fall of the horse; the rider's
own poses only move the person in the saddle.
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

from mathutils import Quaternion, Vector  # noqa: E402

import gear  # noqa: E402
import humanoid  # noqa: E402
import quadruped  # noqa: E402
import spritekit as sk  # noqa: E402
from spritekit import X, Y, Z, keyed, lean, raise_, swing, turn  # noqa: E402

CELL = (208, 224)
ANCHOR = 0.72
BASE = (58, 22)    # the stand under the horse, in sheet pixels

H = "horse."       # bone prefix for the horse in the shared rig
HORSE_AT = (0, 0.18, 0)   # the horse's feet, so it is centred on the hex nose to tail
HORSE_SCALE = 1.3  # beside the big-headed rider a true-scale horse looks like a pony
LEG_LEN = 0.76 * HORSE_SCALE   # hip to hoof, for the walk's body dip

OUTFIT = {"boots": "dark_leather", "legs": "cloth", "sleeves": "team", "forearms": "leather",
          "skirt": "team", "chest": "team"}

BONES = {}         # the merged bone table, for fitting


def model():
    horse = quadruped.body(quadruped.HORSE)
    seat = quadruped.riding_saddle(horse)
    tie = quadruped.halter(horse, quadruped.HORSE)
    horse.moved(HORSE_AT, H, HORSE_SCALE)

    rider = humanoid.body(OUTFIT)
    gear.helmet(rider)
    gear.sword(rider, "R")
    gear.cloak(rider, length=0.42)
    hand = rider.add(sk.marker("rein_hand", humanoid.HAND["L"]), "forearm.L")
    rider.moved(seat * HORSE_SCALE + Vector(HORSE_AT) - Vector((0, 0, 0.45)))
    head, tail, _ = rider.bones["root"]
    rider.bones["root"] = (head, tail, H + "body")   # the rider rides the horse's body

    fit_rider()
    BONES.update(horse.merge(rider).bones)
    rig = sk.build_rig("horseman", horse)
    sk.Rope("reins", hand, tie, mat="dark_leather", radius=0.01, slack=0.06)
    return rig


# --------------------------------------------------------------------------- rider poses

SIT = dict(humanoid.RIDE, **{
    "spine": lean(4) @ turn(-4),
    "head": turn(6),
    "upperarm.R": swing(18) @ raise_("R", 14), "forearm.R": swing(62),
    "upperarm.L": swing(26) @ raise_("L", 6), "forearm.L": swing(58),
})
WINDUP = dict(SIT, **{
    "spine": lean(-10) @ turn(-24), "head": lean(-6) @ turn(18),
    "upperarm.L": swing(36) @ raise_("L", 10), "forearm.L": swing(60),
})
STRIKE = dict(SIT, **{
    "spine": lean(18) @ turn(16) @ raise_("R", 12), "head": lean(-12) @ turn(-8),
    "upperarm.L": swing(20) @ raise_("L", 10), "forearm.L": swing(50),
})
SWORD_AXIS = Vector((0, -math.cos(math.radians(15)), math.sin(math.radians(15))))   # as gear.sword


def fit_rider():
    """The cut, in the rider's own frame (feet at the origin, seated): the sword raised high
    behind, then swept down past the horse's shoulder on the right."""
    for name, rot, hand, axis, guess in (
            ("windup", WINDUP, (-0.3, 0.14, 1.3), (0.1, 0.85, 0.55), (160, 20, 0, 60, 0)),
            ("strike", STRIKE, (-0.44, -0.32, 0.72), (-0.35, -1, -0.7), (50, 40, 0, 10, 0)),
            ("follow", STRIKE, (-0.46, -0.22, 0.62), (-0.4, -0.7, -1), (40, 40, 0, 10, 0))):
        p, err = humanoid.reach(sk.pose(rot), "R", hand, SWORD_AXIS, axis, guess)
        print("horseman: %s fitted, error %.3f" % (name, err))
        FIT[name] = p["rot"]


FIT = {}


def rider_idle(i, n):
    breath, hips = humanoid.breathe(i, n)
    rot = sk.layer(SIT, breath)
    rot = sk.layer(rot, {"head": turn(6 * sk.wave(i, n, phase=1.4))})
    return sk.pose(rot, {"hips": hips})


def idle(i, n, yaw=0.0):
    return sk.merge(rider_idle(i, n), sk.prefixed(quadruped.stand_idle(i, n, nod=4.0), H))


def walk(i, n, yaw=0.0):
    """A brisk trot: the diagonal legs together, the rider rising and settling with the stride."""
    beast = quadruped.walk(i, n, stride=26.0, knee=55.0, leg_len=LEG_LEN)
    s = sk.wave(i, n, 2)
    rider = dict(SIT, **{
        "spine": lean(7 + 2 * s) @ turn(-4),
        "head": lean(-3 - 2 * s) @ turn(6),
        "upperarm.R": swing(20 + 3 * s) @ raise_("R", 14),
    })
    return sk.merge(sk.pose(rider, {"hips": (0, 0, 0.012 * s)}), sk.prefixed(beast, H))


REAR = {"body": lean(-9), "neck": lean(-10), "head": lean(-6),
        "leg.FR": swing(34), "shin.FR": swing(-70), "leg.FL": swing(22), "shin.FL": swing(-60),
        "leg.HR": swing(10), "leg.HL": swing(6), "tail": swing(-20)}
PLUNGE = {"body": lean(3), "neck": lean(8), "head": lean(10),
          "leg.FR": swing(-8), "leg.FL": swing(4), "leg.HR": swing(-4), "leg.HL": swing(-2), "tail": swing(-12)}


def attack(i, n, yaw=0.0):
    """The horse rears a little as the rider winds up, and plunges forward with the cut."""
    still = quadruped.stand_idle(0, n)
    rear = sk.pose(dict(still["rot"], **REAR), {"body": (0, 0, 0.04)})
    plunge = sk.pose(dict(still["rot"], **PLUNGE))
    rider = keyed(i, [(0, sk.pose(SIT)), (2.5, sk.pose(FIT["windup"])), (4, sk.pose(FIT["strike"])),
                      (5.2, sk.pose(FIT["follow"])), (n, sk.pose(SIT))])
    beast = keyed(i, [(0, still), (2.5, rear), (4, plunge), (5.5, plunge), (n, still)])
    return sk.merge(rider, sk.prefixed(beast, H))


def hit(i, n, yaw=0.0):
    still = quadruped.stand_idle(0, n)
    toss = sk.pose(dict(still["rot"], **{"neck": lean(-14), "head": lean(-12), "body": lean(-3), "tail": swing(-25)}),
                   {"root": (0, 0.06, 0)})
    recoil = dict(SIT, **{"spine": lean(-16) @ turn(-4), "head": lean(-12) @ turn(10),
                          "upperarm.R": swing(4) @ raise_("R", 30), "forearm.R": swing(40)})
    rider = keyed(i, [(0, sk.pose(SIT)), (1, sk.pose(recoil)), (n, sk.pose(SIT))])
    beast = keyed(i, [(0, still), (1, toss), (n, still)])
    return sk.merge(rider, sk.prefixed(beast, H))


def fall_spin(yaw):
    """Turn (degrees) that points the horse's left side along a screen horizontal, so the horse
    rolling onto that side throws the rider across the screen in every facing (a body lying
    toward or away from the camera would look like it was still standing)."""
    spin = math.degrees(-yaw)
    while spin > 90:
        spin -= 180
    while spin < -90:
        spin += 180
    return spin


def death(i, n, yaw):
    """The horse's legs buckle, it sinks, turns and rolls onto its left side; the rider goes down
    with it."""
    spin = fall_spin(yaw)
    side = 1.0
    still = quadruped.stand_idle(0, n)
    buckle = sk.pose(dict(still["rot"], **{
        "body": lean(6), "neck": lean(14), "head": lean(18),
        "leg.FR": swing(-30), "shin.FR": swing(90), "leg.FL": swing(-24), "shin.FL": swing(80),
        "leg.HR": swing(24), "shin.HR": swing(-40), "leg.HL": swing(18), "shin.HL": swing(-34),
    }), {"body": (0, 0, -0.22 * HORSE_SCALE)})
    legs_out = {"leg.FR": swing(30), "shin.FR": swing(-20), "leg.FL": swing(40), "shin.FL": swing(-30),
                "leg.HR": swing(-30), "shin.HR": swing(20), "leg.HL": swing(-20), "shin.HL": swing(10),
                "neck": lean(-20), "head": lean(-10), "tail": swing(-30)}
    k = HORSE_SCALE
    q = Quaternion(Z, math.radians(spin))
    lying = sk.pose(dict(legs_out, root=turn(spin) @ raise_("R", 88 * side)), {"root": q @ Vector((side * -1.1 * k, 0, 0.2 * k))})
    falling = sk.pose(dict(legs_out, root=turn(spin * 0.6) @ raise_("R", 50 * side), body=lean(4)),
                      {"root": q @ Vector((side * -0.6 * k, 0, 0.0)), "body": (0, 0, -0.15 * k)})
    beast = keyed(i, [(0, still), (2, buckle), (4.5, falling), (n - 1, lying)])
    slump = dict(SIT, **{"spine": lean(18), "head": lean(20),
                         "upperarm.R": swing(10) @ raise_("R", 20), "forearm.R": swing(20),
                         "upperarm.L": swing(10) @ raise_("L", 20), "forearm.L": swing(20)})
    sprawl = dict(SIT, **{"root": raise_("R", -6 * side), "spine": lean(-10), "head": lean(-10),
                          "upperarm.R": swing(30) @ raise_("R", 70), "forearm.R": swing(10),
                          "upperarm.L": swing(30) @ raise_("L", 70), "forearm.L": swing(10),
                          "thigh.R": swing(40) @ raise_("R", 20), "shin.R": swing(-30),
                          "thigh.L": swing(40) @ raise_("L", 20), "shin.L": swing(-30)})
    rider = keyed(i, [(0, sk.pose(SIT)), (2, sk.pose(slump)), (n - 1, sk.pose(sprawl))])
    return sk.merge(rider, sk.prefixed(beast, H))


ANIMATIONS = {
    "idle": (idle, 16, True),
    "walk": (walk, 8, True),
    "attack": (attack, 9, False),
    "hit": (hit, 5, False),
    "death": (death, 8, False),
}

sk.build("horseman", model, ANIMATIONS, cell=CELL, anchor=ANCHOR, base=BASE)
