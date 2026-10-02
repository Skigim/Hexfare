"""Builds the archer sprite in Blender: the base humanoid (art/lib/humanoid.py) in a team-coloured
jerkin and a feathered cap, with a quiver on the back and a longbow (art/lib/gear.py), rendered in
the six hex facings by the shared pipeline (art/lib/spritekit.py).

    blender -b --factory-startup --python art/archer/build_archer.py [-- --only=idle,attack]

Writes art/archer/archer.blend and assets/units/archer/. The shot is taken side-on: the bow arm
straight out toward the target, the string (an sk.Cord pulled to the drawing hand) drawn back
beside the jaw, so bow, string and arrow stay in one upright plane to the right of the head and
clear of the body. The "release" mark is the frame the arrow leaves, when the game launches the
projectile: the string snaps straight and the loosed arrow shows past the bow for that frame.
The rig has no wrist, so the bow is modelled twice, toggled by pose: upright in the hand for the
full draw (shown while the bow is up), and held at the side, string toward the body, at rest. The arms of every key pose are fitted with humanoid.reach.
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

CELL = (160, 176)
ANCHOR = 0.74

sk.COLORS.update({"hose": (0.4, 0.42, 0.3), "jerkin": (0.55, 0.42, 0.28)})
OUTFIT = {"boots": "dark_leather", "legs": "hose", "sleeves": "jerkin", "forearms": "leather",
          "hips": "hose", "skirt": "jerkin", "chest": "team", "collar": "jerkin"}

# The line of the shot: the arrow flies along x = AIM_X, z = AIM_Z toward -Y (the target), outside
# the right of the head (0.21 wide each side of the centre) so the drawn string never crosses it.
AIM_X = -0.29
AIM_Z = 1.0
BOW_Y = -0.48             # the bow hand, at arm's length toward the target
DRAW_Y = -0.05            # the drawing hand at full draw, beside the jaw
RELEASE = 7               # attack frame the arrow leaves
ARROW_SHOWN = (3, RELEASE)  # nocked from this frame until the release
LOOSED = 0.3              # how far the loosed arrow has flown on the release frame
BOW_UP = (2, 10)          # attack frames the drawn bow is in the hand (the resting bow otherwise)
STRING, REST_STRING = "bow_string", "bow_rest_string"
REST_HAND = (0.34, -0.1, 0.68)   # the left hand at rest
REST_UP = (0.15, -0.55, 1)       # the resting bow leans forward, its top showing from every side...
REST_BACK = (0.57, -0.82, 0)     # ...its back turned out, the string in toward the body, clear of the arm

FIT = {}       # key pose name -> fitted pose
BOW = {}       # the drawn bow
REST_BOW = {}  # the resting bow
ARROW = []     # nocked arrow part names
FLYING = []    # the loosed arrow's part names


def model():
    b = humanoid.body(OUTFIT)
    gear.hair(b, topknot=False, top=False)
    gear.feathered_cap(b)
    gear.quiver(b)
    fit_poses()
    draw = sk.pose(FIT["draw"])
    BOW.update(gear.bow(b, draw, "L"))
    REST_BOW.update(gear.bow(b, sk.pose(FIT["rest"]), "L", aim=REST_BACK, up=REST_UP, name="bow_rest"))
    for part in BOW["parts"]:
        sk.toggle(part, False)
    for part in REST_BOW["parts"]:
        sk.toggle(part)
    low = min(sk.posed_point(humanoid.BONES, sk.pose(FIT["rest"]), "forearm.L", tip).z for tip in REST_BOW["tips"])
    print("archer: lowest bow tip at rest z=%.3f" % low)
    ARROW[:] = [sk.toggle(o, False).name for o in gear.arrow(b, draw, "R")]
    # The loosed arrow rides the root, modelled turned back so it lies on the line of the shot when
    # the root turns into the stance.
    back = AIM_BODY["root"].inverted()
    nock = Vector((AIM_X, DRAW_Y - 0.02 - LOOSED, AIM_Z))
    FLYING[:] = [sk.toggle(o, False).name for o in gear.loose_arrow(b, back @ nock, back @ Vector((0, -1, 0)), "root", name="arrow_loosed")]
    hand = b.add(sk.marker("draw_hand", humanoid.HAND["R"] + Vector((0, 0.03, 0))), "forearm.R")
    rig = sk.build_rig("archer", b)
    sk.toggle(sk.Cord(STRING, BOW["top"], BOW["bottom"], hand).obj, False)
    sk.toggle(sk.Cord(REST_STRING, REST_BOW["top"], REST_BOW["bottom"], hand).obj)
    return rig


# --------------------------------------------------------------------------- poses

# Shooting stance: side-on to the target, left shoulder leading, head turned to look along the arrow.
AIM_BODY = dict(humanoid.STAND, **{
    "root": turn(-65),
    "spine": lean(-2) @ turn(-10),
    "head": lean(-4) @ turn(70),
    "thigh.R": swing(-4) @ raise_("R", 12), "thigh.L": swing(4) @ raise_("L", 10),
})
REST_BODY = dict(humanoid.STAND, **{
    "spine": lean(3) @ turn(8),
    "head": turn(-6),
    "upperarm.R": swing(2) @ raise_("R", 8), "forearm.R": swing(14),
})


def fit(name, rot, side, hand, guess, item=None, axis=None):
    p, err = humanoid.reach(sk.pose(rot), side, hand, item, axis, guess)
    print("archer: %s fitted (%s arm), error %.3f" % (name, side, err))
    return p["rot"]


def fit_poses():
    """The draw: bow arm straight out along the line of the arrow, drawing hand beside the jaw."""
    rot = fit("draw", AIM_BODY, "L", (AIM_X, BOW_Y, AIM_Z), (90, 20, 0, 5, 0))
    FIT["draw"] = fit("draw", rot, "R", (AIM_X, DRAW_Y, AIM_Z), (70, 40, 0, 120, 0))
    # Nocking: the hand brings the arrow up toward the string (from side-on it falls about 0.2
    # short, hidden by the speed of the draw), already along the line of the shot (gear.arrow
    # models it for the draw).
    arrow = humanoid.arm_rotation(FIT["draw"], "R").inverted() @ Vector((0, -1, 0))
    FIT["nock"] = fit("nock", rot, "R", (AIM_X, BOW_Y + 0.2, AIM_Z), (70, 30, 0, 60, 0), arrow, (0, -1, 0))
    # Loosed: the drawing hand flies back past the ear.
    FIT["loose"] = fit("loose", rot, "R", (AIM_X - 0.06, DRAW_Y + 0.14, AIM_Z + 0.08), (50, 60, 0, 130, 0))
    # At rest the left hand holds the resting bow by the hip, its lower tip clear of the ground.
    FIT["rest"] = fit("rest", REST_BODY, "L", REST_HAND, (10, 10, 0, 50, 0))


def pose(rot, pull=0.0, **locs):
    return sk.pose(rot, {k.replace("__", "."): v for k, v in locs.items()}, pull={STRING: pull})


def idle(i, n, yaw=0.0):
    breath, hips = humanoid.breathe(i, n)
    rot = sk.layer(FIT["rest"], breath)
    rot = sk.layer(rot, {"head": turn(5 * sk.wave(i, n, phase=1.0))})
    return pose(rot, hips=hips)


def walk(i, n, yaw=0.0):
    rot, hips, s = humanoid.walk_legs(i, n)
    rot.update({
        "spine": lean(6) @ turn(8 - 6 * s),
        "head": lean(-3) @ turn(-6 + 2 * s),
        "upperarm.R": swing(-22 * s) @ raise_("R", 7), "forearm.R": swing(18 - 8 * s),
        "upperarm.L": FIT["rest"]["upperarm.L"], "forearm.L": FIT["rest"]["forearm.L"],
    })
    return pose(rot, hips=hips)


def attack(i, n, yaw=0.0):
    p = keyed(i, [(0, pose(FIT["rest"])), (2.5, pose(FIT["nock"])), (4.5, pose(FIT["draw"], 1.0)),
                  (RELEASE - 1, pose(FIT["draw"], 1.0)), (RELEASE, pose(FIT["loose"])),
                  (RELEASE + 1.5, pose(FIT["loose"])), (n - 1, pose(FIT["rest"]))])
    up = BOW_UP[0] <= i < BOW_UP[1]
    p["show"] = {name: ARROW_SHOWN[0] <= i < ARROW_SHOWN[1] for name in ARROW}
    p["show"].update({name: i == RELEASE for name in FLYING})
    p["show"].update({o.name: up for o in BOW["parts"]})
    p["show"].update({o.name: not up for o in REST_BOW["parts"]})
    p["show"].update({STRING: up, REST_STRING: not up})
    return p


def hit(i, n, yaw=0.0):
    recoil = dict(FIT["rest"], **{
        "spine": lean(-14) @ turn(4), "head": lean(-12) @ turn(-8),
        "upperarm.R": swing(-6) @ raise_("R", 24), "forearm.R": swing(30),
    })
    return keyed(i, [(0, pose(FIT["rest"])), (1, pose(recoil, root=(0, 0.07, 0))), (n, pose(FIT["rest"]))])


def fall_spin(yaw):
    """Turn (radians) that points the back along whichever screen horizontal it faces more, so a
    body falling backward lands across the screen in every facing (as the warrior's)."""
    back = Vector((-math.sin(yaw), math.cos(yaw), 0))
    target = Quaternion(Z, -yaw) @ Vector((-1.0 if back.x <= 0 else 1.0, 0, 0))
    spin = math.atan2(target.y, target.x) - math.pi / 2
    return math.atan2(math.sin(spin), math.cos(spin))


_LYING = {}


def death(i, n, yaw):
    """Buckles and falls onto the back, the bow dropping flat beside the body."""
    spin = fall_spin(yaw)
    back = Quaternion(Z, spin) @ Vector((0, 1, 0))
    twist = math.degrees(spin)
    buckle = dict(FIT["rest"], **{
        "root": turn(twist * 0.3),
        "spine": lean(16) @ turn(-6), "head": lean(18),
        "upperarm.R": swing(18) @ raise_("R", 20), "forearm.R": swing(20),
        "thigh.R": swing(32), "shin.R": swing(-62), "thigh.L": swing(22), "shin.L": swing(-55),
    })
    fall = {
        "root": turn(twist * 0.8) @ lean(-62), "spine": lean(-6), "head": lean(-14),
        "upperarm.R": swing(50) @ raise_("R", 55), "forearm.R": swing(20),
        "upperarm.L": swing(40) @ raise_("L", 50), "forearm.L": swing(30),
        "thigh.R": swing(40), "shin.R": swing(-35), "thigh.L": swing(30), "shin.L": swing(-25),
    }
    lie = dict(fall, **{
        "root": turn(twist) @ lean(-90), "spine": lean(-4), "head": lean(-8) @ turn(-20),
        "upperarm.R": swing(10) @ raise_("R", 70), "forearm.R": swing(8),
        "thigh.R": swing(14) @ raise_("R", 6), "shin.R": swing(-10),
        "thigh.L": swing(24) @ raise_("L", 8), "shin.L": swing(-30),
    })
    root = tuple(-back * 0.62 + Vector((0, 0, 0.13)))
    key = tuple(round(v, 4) for v in back)
    if key not in _LYING:
        p = sk.pose(lie, {"root": root})
        shoulder = sk.posed_point(humanoid.BONES, p, "upperarm.L", humanoid.SHOULDER["L"])
        side = shoulder - sk.posed_point(humanoid.BONES, p, "spine", Vector((0, 0, 0.93)))
        side.z = 0
        hand = shoulder + side.normalized() * 0.3 - back * 0.2
        hand.z = 0.08
        for _ in range(6):   # raise the hand until the bow rests on its tips on the ground
            fitted, err = humanoid.reach(p, "L", hand, REST_BOW["up"], back + Vector((0, 0, 0.03)), guess=(10, 70, 0, 10, 0))
            low = min(sk.posed_point(humanoid.BONES, fitted, "forearm.L", tip).z for tip in REST_BOW["tips"])
            hand.z += 0.025 - low
        print("archer: lying bow fitted, error %.3f, lowest tip z=%.3f" % (err, low))
        _LYING[key] = pose(fitted["rot"], root=root)
    return keyed(i, [(0, pose(FIT["rest"])), (2, pose(buckle, hips=(0, 0, -0.13))),
                     (4.5, pose(fall, root=tuple(-back * 0.45 + Vector((0, 0, 0.04))), hips=(0, 0, -0.06))),
                     (n - 1, _LYING[key])])


# name: (pose function, frames, loops[, marks])
ANIMATIONS = {
    "idle": (idle, 12, True),
    "walk": (walk, 8, True),
    "attack": (attack, 12, False, {"release": RELEASE}),
    "hit": (hit, 5, False),
    "death": (death, 8, False),
}

sk.build("archer", model, ANIMATIONS, cell=CELL, anchor=ANCHOR)
