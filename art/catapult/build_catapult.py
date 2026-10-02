"""Builds the catapult sprite in Blender: a wheeled throwing engine (a custom sk.Body: frame,
wheels, a throwing arm on a rope skein, a padded crossbar and a pennant) with one crewman (the base
humanoid with a mallet) beside it, rendered in the six hex facings by the shared pipeline
(art/lib/spritekit.py).

    blender -b --factory-startup --python art/catapult/build_catapult.py [-- --only=idle,attack]

Writes art/catapult/catapult.blend and assets/units/catapult/. Walking, the wheels roll and the
crewman walks alongside. The attack: the crewman knocks out the release pin with his mallet and
the arm whips up against the crossbar; its "release" mark is the frame the stone leaves, when the
game launches the projectile. Team colour: the crossbar's padding, the pennant and the crewman.
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

from mathutils import Quaternion, Vector  # noqa: E402

import gear  # noqa: E402
import humanoid  # noqa: E402
import spritekit as sk  # noqa: E402
from spritekit import X, Y, Z, at, between, box, cylinder, keyed, lean, make_mesh, place, raise_, sphere, swing, turn  # noqa: E402

CELL = (208, 216)
ANCHOR = 0.7
BASE = (58, 23)    # the stand under the engine and crew, in sheet pixels

C = "crew."                    # bone prefix for the crewman
CREW_AT = (0.78, 0.5, 0)       # beside the engine's left rear, by the release pin
MACHINE_AT = (-0.16, -0.06, 0)
MACHINE_SCALE = 1.3            # at true scale beside the big-headed crewman the engine looks like a toy

sk.COLORS.update({"dark_wood": (0.38, 0.25, 0.15), "rope": (0.8, 0.7, 0.52), "stone": (0.58, 0.57, 0.55),
                  "smock": (0.62, 0.55, 0.42)})
OUTFIT = {"boots": "dark_leather", "legs": "cloth", "sleeves": "smock", "forearms": "smock",
          "hips": "cloth", "skirt": "team", "chest": "team"}

# The engine (feet at the origin, facing -Y like every actor).
PIVOT = Vector((0, -0.2, 0.5))     # the arm's axle, through the skein
BUCKET = Vector((0, 0.66, 0.5))    # the arm's cup, cocked back
FRAME_Z = 0.34
WHEEL_R = 0.2
TRACK = 0.43
WHEELS = {"FR": (-1, -0.42), "FL": (1, -0.42), "HR": (-1, 0.44), "HL": (1, 0.44)}
FLAG = Vector((0.3, 0.62, 1.32))   # top of the pennant pole
FIRED = -102                       # arm swing when it hits the crossbar (up and a little forward)
RELEASE = 5                        # attack frame the stone leaves
STRIKE_FRAME = 3                   # attack frame the mallet knocks the pin
RELOADED = 11                      # the stone is back in the cup from this attack frame

STONE = []    # object names of the stone in the cup


def engine():
    bones = {
        "root": ((0, 0, 0), (0, 0, 0.2), None),
        "frame": ((0, 0.6, FRAME_Z), (0, -0.6, FRAME_Z), "root"),
        "arm": (tuple(PIVOT), tuple(BUCKET), "frame"),
        "flag": (tuple(FLAG), tuple(FLAG + Vector((0, 0.3, 0))), "frame"),
    }
    for k, (sx, y) in WHEELS.items():
        bones["wheel." + k] = ((sx * TRACK, y, WHEEL_R), (sx * (TRACK + 0.1), y, WHEEL_R), "frame")
    b = sk.Body(bones)

    def beam(name, a, c, r, mat="wood", bone="frame"):
        return b.add(between(make_mesh(name, cylinder(r, r, (Vector(c) - Vector(a)).length, 8), mat, smooth=True), a, c), bone)

    for sx in (-1, 1):
        b.add(at(make_mesh("side_beam.%d" % sx, box(0.09, 1.34, 0.1), "wood", bevel=0.02), sx * 0.3, 0, FRAME_Z), "frame")
        beam("post.%d" % sx, (sx * 0.3, -0.38, FRAME_Z), (sx * 0.28, -0.5, 1.04), 0.04)
        beam("brace.%d" % sx, (sx * 0.3, 0.02, FRAME_Z), (sx * 0.29, -0.44, 0.88), 0.03, "dark_wood")
    for y in (-0.62, 0.62):
        b.add(at(make_mesh("cross_beam", box(0.7, 0.09, 0.09), "wood", bevel=0.02), 0, y, FRAME_Z), "frame")
    for y in (-0.42, 0.44):
        beam("axle", (-TRACK, y, WHEEL_R), (TRACK, y, WHEEL_R), 0.035, "dark_wood")
    beam("crossbar", (-0.36, -0.5, 1.04), (0.36, -0.5, 1.04), 0.05)
    b.add(at(make_mesh("crossbar_pad", box(0.36, 0.16, 0.16), "team", bevel=0.05, segments=3), 0, -0.47, 1.04), "frame")
    skein = beam("skein", (-0.27, PIVOT.y, PIVOT.z), (0.27, PIVOT.y, PIVOT.z), 0.085, "rope")
    for sx in (-1, 1):
        beam("skein_washer.%d" % sx, (sx * 0.26, PIVOT.y, PIVOT.z), (sx * 0.33, PIVOT.y, PIVOT.z), 0.11, "dark_wood")
    beam("windlass", (-0.3, 0.58, 0.48), (0.3, 0.58, 0.48), 0.05, "dark_wood")
    for sx in (-1, 1):
        for a in (0, 90):
            spoke = make_mesh("windlass_spoke", box(0.03, 0.3, 0.03), "wood")
            place(spoke, Vector((sx * 0.36, 0.58, 0.48)), x_axis=X, y_axis=Vector((0, math.cos(math.radians(a)), math.sin(math.radians(a)))))
            b.add(spoke, "frame")
    beam("flag_pole", (0.3, 0.62, FRAME_Z), tuple(FLAG + Vector((0, 0, 0.04))), 0.022)
    pennant = make_mesh("pennant", cylinder(0.1, 0.0, 0.36, 3), "team")
    place(pennant, FLAG + Vector((0, 0.17, -0.07)), x_axis=X, z_axis=Y)
    pennant.scale = (0.2, 1, 1)
    b.add(pennant, "flag")

    arm_dir = (BUCKET - PIVOT).normalized()
    beam("arm", PIVOT - arm_dir * 0.08, BUCKET, 0.045, "wood", "arm")
    beam("arm_band", PIVOT + arm_dir * 0.38, PIVOT + arm_dir * 0.43, 0.056, "dark_steel", "arm")
    cup = make_mesh("cup", sphere(0.12, sz=0.7, cut_below=0.0, segments=12), "dark_wood", smooth=True)
    place(cup, BUCKET + Vector((0, 0, 0.04)), x_axis=X, z_axis=-Z)   # a bowl, open upward when cocked
    b.add(cup, "arm")
    STONE[:] = [sk.toggle(b.add(at(make_mesh("stone", sphere(0.1, segments=12), "stone", smooth=True), *(BUCKET + Vector((0, 0, 0.08)))), "arm")).name]

    for k, (sx, y) in WHEELS.items():
        c = Vector((sx * TRACK, y, WHEEL_R))
        bone = "wheel." + k
        b.add(between(make_mesh("wheel_rim." + k, cylinder(WHEEL_R, WHEEL_R, 0.07, 18), "dark_wood", smooth=True),
                      c - X * 0.035, c + X * 0.035), bone)
        b.add(between(make_mesh("wheel_disc." + k, cylinder(WHEEL_R * 0.8, WHEEL_R * 0.8, 0.08, 18), "wood", smooth=True),
                      c - X * 0.04, c + X * 0.04), bone)
        for a in (0, 90):   # four spokes: the roll repeats every quarter turn
            spoke = make_mesh("wheel_spoke." + k, box(0.09, WHEEL_R * 1.7, 0.04), "dark_wood")
            place(spoke, c + X * sx * 0.045, x_axis=X, y_axis=Vector((0, math.cos(math.radians(a)), math.sin(math.radians(a)))))
            b.add(spoke, bone)
        b.add(between(make_mesh("wheel_hub." + k, cylinder(0.05, 0.05, 0.12, 8), "dark_steel"), c - X * 0.06, c + X * 0.06), bone)
    return b


def model():
    machine = engine()
    crew = humanoid.body(OUTFIT)
    gear.cowl(crew, "leather", tail=False)
    gear.mallet(crew, "R")
    fit_crew()
    # The release pin sits where the mallet lands (crew frame -> engine frame).
    struck = sk.pose(FIT["strike"], {"hips": STRIKE_HIPS})
    head = sk.posed_point(humanoid.BONES, struck, "forearm.R", gear.mallet_head("R"))
    pin = (head + Vector(CREW_AT) - Vector(MACHINE_AT)) / MACHINE_SCALE - Vector((0, 0, 0.07))
    print("catapult: release pin at %s (frame top z=%.2f)" % (tuple(round(v, 2) for v in pin), FRAME_Z + 0.05))
    machine.add(between(make_mesh("pin_post", cylinder(0.035, 0.035, pin.z - FRAME_Z, 8), "dark_wood"),
                        Vector((pin.x, pin.y, FRAME_Z)), pin), "frame")
    machine.add(at(make_mesh("pin", box(0.1, 0.06, 0.05), "dark_steel", bevel=0.01), *pin), "frame")
    machine.moved(MACHINE_AT, scale=MACHINE_SCALE)
    crew.moved(CREW_AT, C)
    return sk.build_rig("catapult", machine.merge(crew))


# --------------------------------------------------------------------------- poses

STANDBY = dict(humanoid.STAND, **{
    "root": turn(-12),
    "spine": lean(3) @ turn(-4),
    "head": turn(-10),
    "upperarm.R": swing(14) @ raise_("R", 10), "forearm.R": swing(48),
})
WINDUP = dict(STANDBY, **{
    "root": turn(-62),
    "spine": lean(-8) @ turn(-12), "head": lean(10) @ turn(4),
    "upperarm.R": swing(150) @ raise_("R", 30), "forearm.R": swing(50),
    "upperarm.L": swing(20) @ raise_("L", 20), "forearm.L": swing(40),
})
STRIKE_HIPS = (0, 0.02, -0.06)
FIT = {}


def fit_crew():
    """The blow: a mallet swing down onto the pin beside the cup, at about frame height."""
    def struck(a):
        rot = dict(WINDUP, **{"spine": lean(28) @ turn(-10), "head": lean(4),
                              "upperarm.R": swing(a) @ raise_("R", 10), "forearm.R": swing(14),
                              "thigh.R": swing(20), "shin.R": swing(-30), "thigh.L": swing(-6), "shin.L": swing(-10)})
        return rot, sk.posed_point(humanoid.BONES, sk.pose(rot, {"hips": STRIKE_HIPS}), "forearm.R", gear.mallet_head("R")).z
    best = min(range(-30, 130), key=lambda a: abs(struck(a)[1] - (FRAME_Z + 0.2) * MACHINE_SCALE))
    FIT["strike"] = struck(best)[0]
    print("catapult: mallet strike at arm swing %d, head z=%.3f" % (best, struck(best)[1]))


def crew_idle(i, n):
    breath, hips = humanoid.breathe(i, n)
    rot = sk.layer(STANDBY, breath)
    rot = sk.layer(rot, {"head": turn(8 * sk.wave(i, n, phase=0.6))})
    return sk.pose(rot, {"hips": hips})


def flutter(i, n, cycles=2, amount=18.0):
    return {"flag": turn(amount * sk.wave(i, n, cycles))}


def idle(i, n, yaw=0.0):
    return sk.merge(sk.pose(flutter(i, n)), sk.prefixed(crew_idle(i, n), C))


def walk(i, n, yaw=0.0):
    """The wheels roll a quarter turn a stride (the spokes repeat), the frame jolts on the
    ground, the crewman walks alongside."""
    roll = swing(-90.0 * i / n)   # negative swing rolls the top of a wheel forward
    rot = {"wheel." + k: roll for k in WHEELS}
    rot.update(flutter(i, n, 1, 26))
    rot["frame"] = lean(0.8 * sk.wave(i, n, 2))
    machine = sk.pose(rot, {"frame": (0, 0, 0.01 * sk.wave(i, n, 2, 1.0))})
    crew = humanoid.walk(i, n, arm_swing=16)
    crew["rot"].update({"upperarm.R": swing(14 + 6 * sk.wave(i, n)) @ raise_("R", 10), "forearm.R": swing(48)})
    return sk.merge(machine, sk.prefixed(crew, C))


def attack(i, n, yaw=0.0):
    """The crewman winds up and knocks out the pin; the arm whips up against the crossbar and the
    stone flies; the engine bucks; the crewman winds the arm back down and reloads."""
    arm_keys = [(0, 0.0), (STRIKE_FRAME, 0.0), (RELEASE, FIRED), (RELEASE + 1, FIRED + 6), (RELEASE + 2, FIRED),
                (8, FIRED + 8), (n - 1, 0.0)]
    a = _ease(i, arm_keys)
    rot = {"arm": swing(a)}
    rot.update(flutter(i, n, 2, 22))
    buck = sk.pulse(i, n, RELEASE, 3)
    rot["frame"] = lean(-3.5 * buck)
    machine = sk.pose(rot, {"root": (0, 0.03 * buck, 0.02 * buck)})
    machine["show"] = {name: i < RELEASE or i >= RELOADED for name in STONE}
    struck = sk.pose(FIT["strike"], {"hips": STRIKE_HIPS})
    crew = keyed(i, [(0, sk.pose(STANDBY)), (1.8, sk.pose(WINDUP)), (STRIKE_FRAME, struck), (RELEASE, struck),
                     (7, sk.pose(dict(STANDBY, **{"head": lean(-10) @ turn(-30)}))), (n - 1, sk.pose(STANDBY))])
    return sk.merge(machine, sk.prefixed(crew, C))


def _ease(i, keys):
    for (f0, a), (f1, b) in zip(keys, keys[1:]):
        if f0 <= i <= f1:
            t = (i - f0) / (f1 - f0)
            return a + (b - a) * t * t * (3 - 2 * t)
    return keys[-1][1]


def hit(i, n, yaw=0.0):
    shake = sk.pulse(i, n, 0.5, 3)
    machine = sk.pose({"frame": lean(-4 * shake) @ raise_("R", 3 * shake), "arm": swing(-8 * shake)}, {"root": (0, 0.05 * shake, 0)})
    recoil = dict(STANDBY, **{"spine": lean(-16) @ turn(-4), "head": lean(-12) @ turn(8),
                              "upperarm.R": swing(-4) @ raise_("R", 26), "forearm.R": swing(28)})
    crew = keyed(i, [(0, sk.pose(STANDBY)), (1, sk.pose(recoil, {"root": (0, 0.07, 0)})), (n, sk.pose(STANDBY))])
    return sk.merge(machine, sk.prefixed(crew, C))


def fall_spin(yaw):
    """Turn (radians) that points the crewman's back along the screen horizontal toward the middle
    of the cell, so falling backward he lands across the screen and inside it, whichever side of
    the engine he stands on in this facing."""
    feet = Quaternion(Z, yaw) @ Vector(CREW_AT)
    target = Quaternion(Z, -yaw) @ Vector((-1.0 if feet.x > 0 else 1.0, 0, 0))
    spin = math.atan2(target.y, target.x) - math.pi / 2
    return math.atan2(math.sin(spin), math.cos(spin))


def death(i, n, yaw):
    """The front right wheel breaks off, the frame slumps onto that corner, the arm drops over the
    side and the crewman falls, ending curled up on his back."""
    wreck = {
        "frame": lean(9) @ raise_("R", 7),
        "wheel.FR": raise_("R", 75) @ swing(40),
        "arm": swing(-40) @ raise_("R", 50),
        "flag": turn(30),
    }
    k = MACHINE_SCALE
    machine = keyed(i, [(0, sk.pose()), (3, sk.pose(dict(wreck, **{"frame": lean(11) @ raise_("R", 9), "arm": swing(-70) @ raise_("R", 20)}),
                                                     {"wheel.FR": (-0.12 * k, 0, -0.06 * k)})),
                        (n - 1, sk.pose(wreck, {"wheel.FR": (-0.2 * k, 0, -0.1 * k), "frame": (0, 0, -0.05 * k)}))])
    machine["show"] = {name: i < 2 for name in STONE}
    spin = fall_spin(yaw)
    back = Quaternion(Z, spin) @ Vector((0, 1, 0))
    twist = math.degrees(spin)
    buckle = dict(STANDBY, **{"root": turn(twist * 0.3), "spine": lean(16) @ turn(-6), "head": lean(18),
                              "thigh.R": swing(32), "shin.R": swing(-62), "thigh.L": swing(22), "shin.L": swing(-55)})
    fall = {"root": turn(twist * 0.8) @ lean(-62), "spine": lean(-6), "head": lean(-14),
            "upperarm.R": swing(50) @ raise_("R", 55), "forearm.R": swing(20),
            "upperarm.L": swing(40) @ raise_("L", 65), "forearm.L": swing(30),
            "thigh.R": swing(40), "shin.R": swing(-35), "thigh.L": swing(30), "shin.L": swing(-25)}
    lie = dict(fall, **{"root": turn(twist) @ lean(-90), "spine": lean(-4), "head": lean(-8) @ turn(20),
                        "upperarm.R": swing(30) @ raise_("R", 30), "forearm.R": swing(70) @ turn(-90),
                        "upperarm.L": swing(35) @ raise_("L", 25), "forearm.L": swing(80),
                        "thigh.R": swing(64) @ raise_("R", 8), "shin.R": swing(-84),
                        "thigh.L": swing(50) @ raise_("L", 10), "shin.L": swing(-70)})
    crew = keyed(i, [(0, sk.pose(STANDBY)), (2, sk.pose(buckle, {"hips": (0, 0, -0.13)})),
                     (4.5, sk.pose(fall, {"root": tuple(-back * 0.45 + Vector((0, 0, 0.04))), "hips": (0, 0, -0.06)})),
                     (n - 1, sk.pose(lie, {"root": tuple(-back * 0.45 + Vector((0, 0, 0.13)))}))])
    return sk.merge(machine, sk.prefixed(crew, C))


ANIMATIONS = {
    "idle": (idle, 12, True),
    "walk": (walk, 8, True),
    "attack": (attack, 12, False, {"release": RELEASE}),
    "hit": (hit, 5, False),
    "death": (death, 8, False),
}

sk.build("catapult", model, ANIMATIONS, cell=CELL, anchor=ANCHOR, base=BASE)
