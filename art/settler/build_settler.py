"""Builds the settler sprite in Blender: a travelling adventurer (the base humanoid in a hat and
team-coloured cloak, with a staff) leading a pack donkey (the base quadruped with a pack saddle)
on a lead rope.

    blender -b --factory-startup --python art/settler/build_settler.py

Writes art/settler/settler.blend and assets/units/settler/. Settlers never fight (they are
captured or found a city), so besides idle and walk the sheet has only "build": founding a city,
the adventurer pulls the mallet off the belt and drives it into the ground three times. Its
"strike" mark is the last blow, when the game shows the new city.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))

import gear  # noqa: E402
import humanoid  # noqa: E402
import quadruped  # noqa: E402
import spritekit as sk  # noqa: E402
from spritekit import lean, raise_, swing, turn  # noqa: E402

CELL = (160, 192)
BASE = (46, 17)    # the stand under the pair, in sheet pixels

sk.COLORS.update({"tunic": (0.55, 0.6, 0.38), "trousers": (0.5, 0.42, 0.33)})
OUTFIT = {"boots": "dark_leather", "legs": "trousers", "sleeves": "tunic", "forearms": "tunic",
          "hips": "trousers", "skirt": "tunic", "chest": "tunic", "buckle": "dark_steel"}

# Where each actor stands (feet), chosen so the pair is centred on the hex: the adventurer a step
# ahead at the donkey's head, on its left, so the lead rope runs back from the right hand.
WALKER_AT = (0.28, -0.5, 0)
DONKEY_AT = (-0.32, 0.36, 0)
DONKEY_SCALE = 1.12
D = "donkey."      # bone prefix for the donkey in the shared rig


# --------------------------------------------------------------------------- poses

# Adventurer at rest: weight on the right leg, rope hand low and back toward the donkey, staff
# planted in the left hand, glancing back at the animal.
LEAD = dict(humanoid.STAND, **{
    "root": turn(-10),
    "spine": lean(3) @ turn(-6),
    "head": lean(3) @ turn(-14),
    "upperarm.R": swing(-12) @ raise_("R", 14), "forearm.R": swing(38),
    "upperarm.L": swing(16) @ raise_("L", 12), "forearm.L": swing(64),
    "thigh.R": swing(-3) @ raise_("R", 5), "thigh.L": swing(7) @ raise_("L", 3),
    "shin.L": swing(-8),
})


def walker_idle(i, n):
    breath, hips = humanoid.breathe(i, n)
    rot = sk.layer(LEAD, breath)
    rot = sk.layer(rot, {"head": turn(5 * sk.wave(i, n, phase=1.2)), "forearm.R": swing(4 * sk.wave(i, n, phase=2.0))})
    return sk.pose(rot, {"hips": hips})


def idle(i, n, yaw=0.0):
    return sk.merge(walker_idle(i, n), sk.prefixed(quadruped.stand_idle(i, n), D))


def walker_walk(i, n):
    """Walking ahead of the donkey: rope hand trailing, the staff swinging forward with the left
    arm, the other arm nearly still."""
    p = humanoid.walk(i, n, lean_deg=5)
    rot, s = p["rot"], sk.wave(i, n)
    rot.update({
        "root": turn(-4),
        "head": lean(-2) @ turn(-6 + 2 * s),
        "upperarm.R": swing(-12 - 5 * s) @ raise_("R", 14), "forearm.R": swing(36),
        "upperarm.L": swing(16 + 14 * s) @ raise_("L", 12), "forearm.L": swing(64),
    })
    return p


def walk(i, n, yaw=0.0):
    beast = quadruped.walk(i, n, leg_len=0.52 * DONKEY_SCALE)
    return sk.merge(walker_walk(i, n), sk.prefixed(beast, D))


# Founding a city. Poses are fitted to the ground with the rest-pose bone table (sk.posed_point):
# the mallet head lands on the ground and the staff's foot stays out of it.
BUILD_STANCE = dict(LEAD, **{"root": turn(-2), "head": lean(8) @ turn(-4)})
REACH = dict(BUILD_STANCE, **{
    "spine": lean(10) @ turn(-12), "upperarm.R": swing(-14) @ raise_("R", 22), "forearm.R": swing(22),
})
RAISED = dict(BUILD_STANCE, **{
    "spine": lean(-6) @ turn(-14), "head": lean(-2) @ turn(-4),
    "upperarm.R": swing(140) @ raise_("R", 52), "forearm.R": swing(45),
    "upperarm.L": swing(10) @ raise_("L", 14),
})
CROUCH = {"thigh.R": swing(30) @ raise_("R", 6), "shin.R": swing(-52),
          "thigh.L": swing(36) @ raise_("L", 4), "shin.L": swing(-58)}
STRIKE_HIPS = (0, 0.03, -0.07)
STRIKE_FRAMES = (7, 12, 17)
MALLET_SHOWN = {"hand": 3}      # on the belt before this frame, in the hand from it on


def _strike(rot):
    return dict(BUILD_STANCE, **CROUCH, **rot)


def _fit_strike():
    """Arm angles for the blow: the mallet head just touching the ground in front, the staff
    lifted clear of it."""
    def at_ground(a):
        p = sk.pose(_strike({"spine": lean(26) @ turn(-4), "upperarm.R": swing(a) @ raise_("R", 8),
                             "forearm.R": swing(12)}), {"hips": STRIKE_HIPS})
        return sk.posed_point(humanoid.BONES, p, "forearm.R", gear.mallet_head("R")).z
    best = min(range(20, 120), key=lambda a: abs(at_ground(a) - 0.072))
    rot = {"spine": lean(26) @ turn(-4), "upperarm.R": swing(best) @ raise_("R", 8), "forearm.R": swing(12)}

    def foot(a):
        p = sk.pose(_strike(dict(rot, **{"upperarm.L": swing(a) @ raise_("L", 16), "forearm.L": swing(56)})), {"hips": STRIKE_HIPS})
        return sk.posed_point(humanoid.BONES, p, "forearm.L", STAFF_FOOT[0]).z
    lift = min(range(0, 90), key=lambda a: abs(foot(a) - 0.03))
    return dict(rot, **{"upperarm.L": swing(lift) @ raise_("L", 16), "forearm.L": swing(56)})


STRIKE = None    # fitted in model(), once the staff exists


def walker_build(i, n):
    raised = sk.pose(RAISED)
    struck = sk.pose(_strike(STRIKE), {"hips": STRIKE_HIPS})
    keys = [(0, sk.pose(LEAD)), (2, sk.pose(REACH))]
    for f in STRIKE_FRAMES:
        keys += [(f - 2, raised), (f, struck)]
    keys += [(20, sk.pose(dict(BUILD_STANCE, **{"upperarm.R": swing(6) @ raise_("R", 10), "forearm.R": swing(30)}))),
             (n - 1, sk.pose(dict(BUILD_STANCE, **{"upperarm.R": swing(4) @ raise_("R", 10), "forearm.R": swing(26)})))]
    p = sk.keyed(i, keys)
    in_hand = i >= MALLET_SHOWN["hand"]
    show = {name: in_hand for name in MALLET["hand"]}
    show.update({name: not in_hand for name in MALLET["belt"]})
    show.update({name: i in STRIKE_FRAMES for name in DUST[0]})
    show.update({name: i - 1 in STRIKE_FRAMES for name in DUST[1]})
    p["show"] = show
    return p


def build(i, n, yaw=0.0):
    return sk.merge(walker_build(i, n), sk.prefixed(quadruped.stand_idle(i, n), D))


ANIMATIONS = {
    "idle": (idle, 16, True),
    "walk": (walk, 8, True),
    "build": (build, 24, False, {"strike": STRIKE_FRAMES[-1]}),
}
MALLET = {"hand": [], "belt": []}   # object names, filled in by model()
DUST = []                           # [small puff names, spreading puff names]
STAFF_FOOT = []


# --------------------------------------------------------------------------- model

def model():
    walker = humanoid.body(OUTFIT)
    gear.brimmed_hat(walker)
    gear.cloak(walker)
    gear.pouch(walker, "L")
    STAFF_FOOT[:] = [gear.staff(walker, sk.pose(LEAD), "L")]
    hand = walker.add(sk.marker("lead_hand", humanoid.HAND["R"]), "forearm.R")
    global STRIKE
    STRIKE = _fit_strike()
    struck = sk.pose(_strike(STRIKE), {"hips": STRIKE_HIPS})
    print("build: staff foot at z=%.3f in the strike" % sk.posed_point(humanoid.BONES, struck, "forearm.L", STAFF_FOOT[0]).z)
    for tag, belt in (("hand", False), ("belt", True)):
        MALLET[tag] = [sk.toggle(o, belt).name for o in gear.mallet(walker, "R", on_belt=belt)]
    impact = sk.posed_point(humanoid.BONES, struck, "forearm.R", gear.mallet_head("R"))
    impact.z = 0
    DUST[:] = [[sk.toggle(o, False).name for o in gear.dust_puff(walker, impact, "dust_" + tag, radius=r, size=z)]
               for tag, r, z in (("a", 0.06, 0.07), ("b", 0.12, 0.078))]
    walker.moved(WALKER_AT)

    donkey = quadruped.body(quadruped.DONKEY)
    quadruped.pack_saddle(donkey)
    tie = quadruped.halter(donkey)
    donkey.moved(DONKEY_AT, D, DONKEY_SCALE)

    rig = sk.build_rig("settler", walker.merge(donkey))
    sk.Rope("lead_rope", hand, tie, mat="leather", radius=0.011, slack=0.1)
    return rig


sk.build("settler", model, ANIMATIONS, cell=CELL, anchor=0.7, base=BASE)
