"""Builds the 2D warrior sprite in Blender: the base humanoid (art/lib/humanoid.py) as a tribal
fighter, bare-armed in a team-dyed hide vest with fur on the shoulders and a leather cap, with a big
studded war club (art/lib/gear.py) that he swings two-handed, its combat poses, rendered in the six
hex facings by the shared pipeline (art/lib/spritekit.py). The swing's keys are fitted with
humanoid.reach (club hand and club direction), then the other hand onto the grip below it.

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

sk.COLORS.update({"hide": (0.76, 0.6, 0.4), "fur": (0.56, 0.42, 0.28)})
OUTFIT = {"boots": "hide", "legs": "skin", "sleeves": "skin", "forearms": "hide", "hips": "hide",
          "skirt": "hide", "belt": "dark_leather", "buckle": "bone", "chest": "team", "collar": None}

CLUB = {}        # the club in his right hand (gear.club's result), filled in by model()
LEFT_CLUB = {}   # the same club in his left hand, shown while the swing carries it round his left
FIT = {}         # the swing's fitted keys, filled in by fit_poses()


def fur_shoulder(b, side):
    gear.pauldron(b, side, "fur")


def model():
    b = humanoid.body(OUTFIT, shoulders=fur_shoulder)
    gear.hair(b, topknot=False, top=False)
    gear.leather_cap(b)
    gear.hood(b, "fur")   # a fur collar; the back stays team-coloured
    # The rig has no wrist, so one club can't point both ways across the body with both hands on
    # it: it is modelled in each hand and toggled (see SWING).
    CLUB.update(gear.club(b, "R", length=0.8, head=0.15, grip=0.14))
    LEFT_CLUB.update(gear.club(b, "L", length=0.8, head=0.15, grip=0.14, name="club_left"))
    for part in CLUB["parts"]:
        sk.toggle(part)
    for part in LEFT_CLUB["parts"]:
        sk.toggle(part, False)
    fit_poses()
    return sk.build_rig("warrior", b)


# --------------------------------------------------------------------------- poses

CLUB_RAISE, CLUB_TURN = 12, -15   # the guard's club arm: lifted out, forearm turned so the club clears the head


def club_arm(up=0.0, fore=0.0):
    """The guard's club arm, upper arm and forearm swung `up` and `fore` degrees further (breathing,
    walking)."""
    return {"upperarm.R": swing(12 + up) @ raise_("R", CLUB_RAISE), "forearm.R": swing(50 + fore) @ turn(CLUB_TURN)}


GUARD = {
    "spine": lean(4) @ turn(-10),
    "head": turn(9),
    **club_arm(),
    "upperarm.L": swing(10) @ raise_("L", 12),
    "forearm.L": swing(30),
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
        **club_arm(2.5 * b, 3 * b),
        "upperarm.L": swing(10 + 1.5 * b) @ raise_("L", 12),
    }, hips=(0, 0, -0.008 * (1 - math.cos(2 * math.pi * i / n))))


def walk(i, n, yaw=0.0):
    rot, hips, s = humanoid.walk_legs(i, n)
    rot.update({
        "spine": lean(8) @ turn(-10 - 8 * s),
        "head": lean(-4) @ turn(9 + 2 * s),
        **club_arm(-22 * s, 6 * s),
        "upperarm.L": swing(8 + 20 * s) @ raise_("L", 10),
        "forearm.L": swing(26 + 8 * s),
    })
    return pose(rot, hips=hips)


def carried(twist, v):
    """A point or direction given as if the warrior faced forward, carried round with a body
    turned `twist` degrees (positive toward his left)."""
    return tuple(turn(twist) @ Vector(v))


def swing_body(twist, lean_deg, head_lean=0.0, legs=None):
    """The swing's body: `twist` shared by hips (a third) and spine, the head turned back toward
    the target, the thighs turned against the hips so the feet stay put."""
    hips = twist / 3
    rot = dict(GUARD, **{
        "hips": turn(hips), "spine": lean(lean_deg) @ turn(twist - hips),
        "head": lean(head_lean) @ turn(-0.8 * twist),
    })
    for bone, q in (legs or {}).items():
        rot[bone] = turn(-hips) @ q
    return rot


WIDE = {"thigh.R": swing(-12) @ raise_("R", 7), "thigh.L": swing(16) @ raise_("L", 7), "shin.L": swing(-10)}
LUNGE = {"thigh.R": swing(-18) @ raise_("R", 7), "thigh.L": swing(26) @ raise_("L", 7),
         "shin.L": swing(-24), "shin.R": swing(-8)}
LUNGE_HIPS = (0, -0.03, -0.05)

def direction(az, el):
    """A club direction as if facing forward: az degrees round toward his left, el degrees up."""
    a, e = math.radians(az), math.radians(el)
    return (math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))


# name: (hand holding the club, body twist, lean, legs, hips offset, that fist and the club's
#        direction as if facing forward, arm guesses for reach: holding arm, other arm or None for
#        one hand). The arms are short, so both fists can only meet on the grip near the middle of
#        the chest: the twist carries the club round. The club is in the right hand while it is on
#        his right and in the left hand once it has crossed to his left. The blow lands on frame 4,
#        the club across the front and nearly level: swung at full stretch it would run off the cell.
SWING = {
    "gather": ("R", -25, 0, WIDE, (0, 0, 0), (-0.1, -0.28, 0.92), direction(-122, 49), (80, 20, 0, 90, 0), (60, 10, 0, 90, 0)),
    "coil": ("R", -50, -4, WIDE, (0, 0, -0.02), (-0.1, -0.26, 0.95), direction(-123, 34), (90, 30, 0, 90, 0), (80, 10, 0, 90, 0)),
    "sweep": ("R", -25, 4, LUNGE, LUNGE_HIPS, (-0.08, -0.36, 0.98), direction(-100, 20), (80, 10, 0, 60, 0), (70, 10, 0, 60, 0)),
    "strike": ("L", -15, 10, LUNGE, LUNGE_HIPS, (0.02, -0.42, 0.92), direction(90, 30), (60, 10, 0, 60, 0), (60, 10, 0, 60, 0)),
    "follow": ("L", 45, 8, LUNGE, (0, -0.035, -0.055), (0.06, -0.34, 0.9), direction(120, 40), (90, 30, 0, 90, 0), (80, 10, 0, 90, 0)),
    "lift": ("R", 10, 4, WIDE, (0, 0, -0.02), (-0.28, -0.2, 0.8), direction(-50, 55), (40, 10, 0, 70, 0), None),
}


def fit_poses():
    for name, (lead, twist, lean_deg, legs, hips, hand, axis, guess, guess_other) in SWING.items():
        club, other = (CLUB, "L") if lead == "R" else (LEFT_CLUB, "R")
        p, err = humanoid.reach(sk.pose(swing_body(twist, lean_deg, legs=legs), {"hips": hips}), lead,
                                carried(twist, hand), club["axis"], carried(twist, axis), guess=guess)
        err_other = 0.0
        if guess_other:   # None: one hand, the other arm stays as in the body pose
            grip = sk.posed_point(humanoid.BONES, p, "forearm." + lead, club["second_hand"])
            p, err_other = humanoid.reach(p, other, grip, guess=guess_other)
        p["show"] = {o.name: lead == "R" for o in CLUB["parts"]}
        p["show"].update({o.name: lead == "L" for o in LEFT_CLUB["parts"]})
        print("warrior: %s fitted, club arm error %.3f, other hand %.3f" % (name, err, err_other))
        FIT[name] = p


def attack(i, n, yaw=0.0):
    return keyed(i, [(0, pose()), (1, FIT["gather"]), (2, FIT["coil"]), (3, FIT["sweep"]), (4, FIT["strike"]),
                     (5, FIT["follow"]), (6.5, FIT["lift"]), (n, pose())])


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


_LYING = {}


def death(i, n, yaw):
    """Buckles, twists and falls onto the back; ends lying with the club on the ground along the
    body. The fall is centred in the cell so the head and club stay inside it."""
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
    # Lying on the back, arms out on the ground.
    lie = dict(fall, **{
        "root": turn(twist) @ lean(-90), "spine": lean(-4), "head": lean(-8) @ turn(20),
        "upperarm.R": swing(10) @ raise_("R", 70), "forearm.R": swing(8) @ turn(-90),
        "upperarm.L": swing(5) @ raise_("L", 85), "forearm.L": swing(15),
        "thigh.R": swing(14) @ raise_("R", 6), "shin.R": swing(-10),
        "thigh.L": swing(24) @ raise_("L", 8), "shin.L": swing(-30),
    })
    root = tuple(-back * 0.8 + Vector((0, 0, 0.13)))
    key = tuple(round(v, 4) for v in back)
    if key not in _LYING:
        # The club arm on the ground beside the body, the club along it toward the feet, its head
        # resting on the ground.
        p = pose(lie, root=root)
        shoulder = sk.posed_point(humanoid.BONES, p, "upperarm.R", humanoid.SHOULDER["R"])
        side = shoulder - sk.posed_point(humanoid.BONES, p, "spine", Vector((0, 0, 0.93)))
        side.z = 0
        side.normalize()
        hand = shoulder + side * 0.18 + back * 0.1
        hand.z = 0.07
        for _ in range(3):
            fitted, err = humanoid.reach(p, "R", hand, CLUB["axis"], -back + side * 0.3, guess=(10, 60, 0, 10, 0))
            low = sk.posed_point(humanoid.BONES, fitted, "forearm.R", CLUB["head"]).z
            hand.z += 0.12 - low
        print("warrior: lying club fitted, error %.3f, club head z=%.3f" % (err, low))
        _LYING[key] = fitted
    falling = pose(fall, root=tuple(-back * 0.63 + Vector((0, 0, 0.04))), hips=(0, 0, -0.06))
    # The body lands first and the club arm last, so the club never swings out past the cell.
    landing = sk.blend(falling, _LYING[key], 0.65)
    landing["rot"].update({bone: falling["rot"][bone] for bone in ("upperarm.R", "forearm.R")})
    return keyed(i, [(0, pose()), (2, pose(buckle, hips=(0, 0, -0.13))), (4.5, falling), (6, landing),
                     (n - 1, _LYING[key])])


# name: (pose function, frames, loops)
ANIMATIONS = {
    "idle": (idle, 12, True),
    "walk": (walk, 8, True),
    "attack": (attack, 9, False),
    "hit": (hit, 5, False),
    "death": (death, 8, False),
}

sk.build("warrior", model, ANIMATIONS)
