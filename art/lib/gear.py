"""Gear for humanoid bodies: headwear, held items, clothing over the base body. Each function
models the piece in the rest pose, adds it to the body on the right bone and returns it.

Held items take the hand ("R" or "L"). Items that must end up at a set angle in a particular pose
(a staff upright while walking) take that pose's bone rotations and are counter-rotated so they
land there.
"""
import math

from mathutils import Vector

import humanoid
from spritekit import X, Y, Z, at, between, box, cylinder, make_mesh, place, posed_point, quat, shell, sphere


# --------------------------------------------------------------------------- warrior kit

def pauldron(b, side, mat="steel"):
    sx = -1 if side == "R" else 1
    return b.add(at(make_mesh("pauldron." + side, sphere(0.11, sz=0.75, cut_below=-0.03), mat, smooth=True), sx * 0.25, 0, 0.93), "upperarm." + side)


def helmet(b, crest="team"):
    """Rounded steel cap with a nasal guard and a crest."""
    b.add(at(make_mesh("helmet", sphere(0.255, sy=0.95, cut_below=0.0, segments=16), "steel", smooth=True), 0, 0.01, 1.27), "head")
    b.add(at(make_mesh("helmet_rim", cylinder(0.262, 0.262, 0.045, 16), "dark_steel"), 0, 0.01, 1.28), "head")
    b.add(at(make_mesh("nasal", box(0.04, 0.03, 0.15), "steel", bevel=0.01), 0, -0.235, 1.21), "head")
    if crest:
        b.add(at(make_mesh("crest", box(0.055, 0.34, 0.11), crest, bevel=0.03), 0, 0.03, 1.55), "head")


def sword(b, side="R"):
    """Arming sword: the blade leaves the thumb side of the fist (forward, tilted up) and its
    edges lie in the swing plane, so a chop leads with the edge."""
    fist = humanoid.HAND[side]
    tilt = math.radians(15)
    blade_dir = Vector((0, -math.cos(tilt), math.sin(tilt)))
    for name, build, mat, offset in (
            ("grip", cylinder(0.024, 0.024, 0.13), "dark_leather", 0.0),
            ("pommel", sphere(0.036), "gold", -0.085),
            ("crossguard", box(0.03, 0.03, 0.24), "gold", 0.075),
            ("blade", box(0.018, 0.6, 0.075), "steel", 0.39),
            ("tip", cylinder(0.054, 0.0, 0.09, 4), "steel", 0.735)):
        obj = make_mesh("sword_" + name, build, mat, smooth=name == "pommel", bevel=0.006 if name == "crossguard" else 0.0)
        if name in ("grip", "tip"):
            # Cones are built along Z: point Z down the blade.
            place(obj, fist + blade_dir * offset, x_axis=X * -1, z_axis=blade_dir)
            if name == "tip":
                obj.scale = (0.33, 1, 1)
        else:
            place(obj, fist + blade_dir * offset, x_axis=X * -1, y_axis=blade_dir)
        b.add(obj, "forearm." + side)


def round_shield(b, side="L", face="team"):
    """Centre-grip round shield: its face looks along the forearm, so when the forearm comes up
    in a guard the shield stands upright facing forward. Angled 30 degrees outward so its face
    still shows when the figure is seen in profile."""
    fist = humanoid.HAND[side]
    out = 1 if side == "L" else -1
    normal = Vector((out * math.sin(math.radians(30)), 0, -math.cos(math.radians(30))))
    up = Vector((0, -1, 0))
    for name, build, mat, offset in (
            ("shield_board", cylinder(0.27, 0.27, 0.045, 18), "wood", 0.05),
            ("shield_face", cylinder(0.215, 0.215, 0.012, 18), face, 0.077),
            ("shield_boss", sphere(0.075, cut_below=0.0), "steel", 0.08)):
        obj = make_mesh(name, build, mat, smooth=name == "shield_boss")
        place(obj, fist + normal * offset, y_axis=up, z_axis=normal)
        b.add(obj, "forearm." + side)


# --------------------------------------------------------------------------- travelling clothes

def brimmed_hat(b, felt="felt", brim_mat="dark_felt", band="team", brim=0.3):
    """Wide-brimmed traveller's hat: a tall crown with a band, the brim tipped up at the back."""
    top = humanoid.HEAD_TOP
    tip = Vector((0, 0.18, 1)).normalized()   # brim tilts: front down, back up
    for name, build, mat, z in (
            ("hat_brim", cylinder(brim, brim, 0.024, 20), brim_mat, top - 0.04),
            ("hat_band", cylinder(0.182, 0.18, 0.05, 16), band, top - 0.005),
            ("hat_crown", cylinder(0.175, 0.14, 0.17, 16), felt, top + 0.06),
            ("hat_top", sphere(0.14, sz=0.3, cut_below=0.0, segments=16), felt, top + 0.145)):
        obj = make_mesh(name, build, mat, smooth=name != "hat_brim")
        place(obj, Vector((0, 0.01, top - 0.04)) + tip * (z - top + 0.04), x_axis=X, z_axis=tip)
        b.add(obj, "head")


def hood(b, mat="team"):
    """A hood down around the neck and shoulders."""
    b.add(at(make_mesh("hood", cylinder(0.2, 0.15, 0.1, 12), mat, smooth=True, bevel=0.03), 0, 0.02, 1.0), "spine")


def cloak(b, mat="team", length=0.62):
    """A cape hanging from the shoulders down the back, flaring toward the hem."""
    top, bottom = 1.0, 1.0 - length
    obj = make_mesh("cloak", shell(0.3, 0.2, length, keep=lambda co: co.y > -0.06, segments=18), mat, smooth=True)
    obj.scale = (1, 0.85, 1)
    at(obj, 0, 0.05, (top + bottom) / 2)
    b.add(obj, "spine")
    hood(b, mat)


def pouch(b, side="L", mat="leather"):
    sx = -1 if side == "R" else 1
    return b.add(at(make_mesh("pouch." + side, box(0.09, 0.07, 0.11), mat, bevel=0.025), sx * 0.19, -0.04, 0.55), "hips")


def staff(b, held, side="L", length=1.6, mat="wood", tilt=(5, 4)):
    """A walking staff planted on the ground in the pose `held`, its top leaning `tilt` degrees
    (forward, outward). Returns the rest-pose position of its foot."""
    rest_hand = humanoid.HAND[side]
    hand = posed_point(b.bones, held, "forearm." + side, rest_hand)
    fwd, out = tilt
    up = quat(X, fwd) @ quat(Y, out if side == "L" else -out) @ Z
    grip = (hand.z - 0.01) / up.z           # hand to the foot of the staff
    up = humanoid.arm_rotation(held["rot"], side).inverted() @ up
    lo, hi = rest_hand - up * grip, rest_hand + up * (length - grip)
    b.add(between(make_mesh("staff", cylinder(0.022, 0.026, length, 8), mat, smooth=True), lo, hi), "forearm." + side)
    b.add(at(make_mesh("staff_knob", sphere(0.04, segments=8), mat, smooth=True), *hi), "forearm." + side)
    return lo   # rest-pose foot of the staff


# --------------------------------------------------------------------------- tools

MALLET_REACH = 0.5    # grip end to the centre of the head

def mallet(b, side="R", on_belt=False):
    """Wooden mallet. In the fist the handle leaves the thumb side (like the sword) and the head
    lies across its end with the striking faces in the swing plane; on the belt it hangs head-up
    at that hip. Returns the parts, to show or hide with sk.toggle."""
    sx = -1 if side == "R" else 1
    if on_belt:
        along = Vector((sx * 0.12, 0.1, -1)).normalized()       # head up, handle down
        across = Vector((0, 1, 0))
        grip = Vector((sx * 0.27, 0.03, 0.7)) - along * MALLET_REACH
        bone, tag = "hips", "belt"
    else:
        tilt = math.radians(15)
        along = Vector((0, -math.cos(tilt), math.sin(tilt)))
        across = Vector((0, math.sin(tilt), math.cos(tilt)))
        grip = humanoid.HAND[side] - along * 0.06
        bone, tag = "forearm." + side, "hand"
    end = grip + along * MALLET_REACH
    parts = [
        between(make_mesh("mallet_handle_" + tag, cylinder(0.024, 0.028, MALLET_REACH, 6), "wood", smooth=True), grip, end),
        between(make_mesh("mallet_head_" + tag, cylinder(0.088, 0.088, 0.24, 12), "pale_wood", smooth=True), end - across * 0.12, end + across * 0.12),
    ]
    for k in (-1, 1):
        ring = end + across * (k * 0.092)
        parts.append(between(make_mesh("mallet_band_%s_%d" % (tag, k), cylinder(0.093, 0.093, 0.026, 12), "dark_steel"), ring - across * 0.013, ring + across * 0.013))
    for obj in parts:
        b.add(obj, bone)
    return parts


def mallet_head(side="R"):
    """Rest-pose centre of the head of the mallet in that hand (for fitting a strike to the ground)."""
    tilt = math.radians(15)
    return humanoid.HAND[side] + Vector((0, -math.cos(tilt), math.sin(tilt))) * (MALLET_REACH - 0.06)


def dust_puff(b, at_point, name, radius=0.09, size=0.05, rise=0.0, bone="root"):
    """A ring of dust clouds on the ground around a point (an impact), the back ones raised by
    `rise`. Returns them."""
    parts = []
    for k in range(7):
        a = 2 * math.pi * k / 7 + 0.3
        p = Vector(at_point) + Vector((math.cos(a) * radius, math.sin(a) * radius * 0.8, size * 0.5 + rise * (k % 2)))
        puff = make_mesh("%s_%d" % (name, k), sphere(size * (1.15 if k % 2 else 1.0), sz=0.7, segments=10), "dust", smooth=True)
        parts.append(b.add(at(puff, *p), bone))
    return parts
