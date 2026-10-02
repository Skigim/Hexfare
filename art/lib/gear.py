"""Gear for humanoid bodies: headwear, held items, clothing over the base body. Each function
models the piece in the rest pose, adds it to the body on the right bone and returns it.

Held items take the hand ("R" or "L"). Items that must end up at a set angle in a particular pose
(a staff upright while walking) take that pose's bone rotations and are counter-rotated so they
land there.
"""
import math

import bmesh
from mathutils import Vector

import humanoid
from spritekit import X, Y, Z, at, between, box, cylinder, make_mesh, marker, place, posed_point, quat, shell, sphere


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


# --------------------------------------------------------------------------- swordsman kit

def great_helm(b, mat="steel", visor="dark_steel", band="gold"):
    """Flat-topped bucket helmet that hides the face, with a dark eye slit and a brow band."""
    c = humanoid.HEAD_CENTER
    b.add(at(make_mesh("great_helm", cylinder(0.255, 0.245, 0.4, 16), mat, smooth=True), c.x, c.y + 0.01, c.z + 0.02), "head")
    b.add(at(make_mesh("great_helm_top", sphere(0.245, sz=0.32, cut_below=0.0, segments=16), mat, smooth=True), c.x, c.y + 0.01, c.z + 0.22), "head")
    b.add(at(make_mesh("great_helm_band", cylinder(0.262, 0.262, 0.045, 16), band), c.x, c.y + 0.01, c.z + 0.1), "head")
    b.add(at(make_mesh("great_helm_slit", box(0.36, 0.06, 0.04), visor, bevel=0.01), c.x, c.y - 0.225, c.z + 0.0), "head")
    b.add(at(make_mesh("great_helm_ridge", box(0.035, 0.05, 0.3), visor, bevel=0.01), c.x, c.y - 0.24, c.z - 0.08), "head")


GREATSWORD_GRIP = 0.15   # fist to where the second hand holds the grip


def greatsword(b, side="R"):
    """Two-handed sword, built like `sword` (the blade leaves the thumb side of the fist, edges in
    the swing plane) but longer, with a grip long enough for both hands. Returns {"axis": rest-pose
    blade direction, "second_hand": rest-pose point for the other fist, "tip"}."""
    fist = humanoid.HAND[side]
    tilt = math.radians(15)
    blade_dir = Vector((0, -math.cos(tilt), math.sin(tilt)))
    for name, build, mat, offset in (
            ("grip", cylinder(0.027, 0.027, 0.3), "dark_leather", -0.07),
            ("pommel", sphere(0.046), "gold", -0.235),
            ("crossguard", box(0.036, 0.036, 0.36), "gold", 0.1),
            ("blade", box(0.022, 0.84, 0.1), "steel", 0.54),
            ("fuller", box(0.026, 0.62, 0.025), "dark_steel", 0.47),
            ("tip", cylinder(0.072, 0.0, 0.12, 4), "steel", 1.02)):
        obj = make_mesh("greatsword_" + name, build, mat, smooth=name == "pommel", bevel=0.008 if name == "crossguard" else 0.0)
        if name in ("grip", "tip"):
            place(obj, fist + blade_dir * offset, x_axis=X * -1, z_axis=blade_dir)
            if name == "tip":
                obj.scale = (0.3, 1, 1)
        else:
            place(obj, fist + blade_dir * offset, x_axis=X * -1, y_axis=blade_dir)
        b.add(obj, "forearm." + side)
    return {"axis": blade_dir, "second_hand": fist - blade_dir * GREATSWORD_GRIP, "tip": fist + blade_dir * 1.08}


# --------------------------------------------------------------------------- spearman kit

def pointed_helmet(b, mat="steel", rim="dark_steel"):
    """Tall pointed cap with a rim, nasal guard and a spike on top: reads differently from the
    warrior's round crested helmet."""
    b.add(at(make_mesh("helmet", sphere(0.258, sy=0.95, sz=1.32, cut_below=0.0, segments=16), mat, smooth=True), 0, 0.01, 1.27), "head")
    b.add(at(make_mesh("helmet_rim", cylinder(0.265, 0.265, 0.05, 16), rim), 0, 0.01, 1.28), "head")
    b.add(at(make_mesh("helmet_spike", cylinder(0.04, 0.0, 0.12, 8), rim), 0, 0.01, 1.64), "head")
    b.add(at(make_mesh("nasal", box(0.04, 0.03, 0.15), mat, bevel=0.01), 0, -0.235, 1.21), "head")


def held_axis(b, held, side, direction):
    """The rest-pose direction riding that forearm which points along `direction` (armature
    space) in the pose `held`: for modelling a held pole so it lands at an angle in a pose."""
    return humanoid.arm_rotation(held["rot"], side).inverted() @ Vector(direction).normalized()


def spear(b, held, side="R", length=1.85, tilt=(4, 6), mat="wood"):
    """A long spear with a broad leaf head, its butt planted on the ground in the pose `held` and
    its shaft leaning `tilt` degrees (forward, outward). Returns {"axis": rest-pose shaft
    direction (butt to head), "grip": hand to butt distance, "foot", "tip": rest-pose points}."""
    rest_hand = humanoid.HAND[side]
    hand = posed_point(b.bones, held, "forearm." + side, rest_hand)
    fwd, out = tilt
    up = quat(X, fwd) @ quat(Y, out if side == "L" else -out) @ Z
    grip = (hand.z - 0.01) / up.z
    axis = held_axis(b, held, side, up)
    lo, hi = rest_hand - axis * grip, rest_hand + axis * (length - grip)
    bone = "forearm." + side
    b.add(between(make_mesh("spear_shaft", cylinder(0.032, 0.028, length, 8), mat, smooth=True), lo, hi), bone)
    b.add(between(make_mesh("spear_butt", cylinder(0.0, 0.036, 0.08, 8), "dark_steel"), lo - axis * 0.01, lo + axis * 0.06), bone)
    b.add(between(make_mesh("spear_socket", cylinder(0.042, 0.034, 0.1, 8), "dark_steel"), hi - axis * 0.05, hi + axis * 0.04), bone)
    head = make_mesh("spear_head", sphere(1.0, sx=0.095, sy=0.035, sz=0.19, segments=12), "steel", smooth=True)
    between(head, hi + axis * 0.02, hi + axis * 0.36)
    b.add(head, bone)
    return {"axis": axis, "grip": grip, "foot": lo, "tip": hi + axis * 0.36, "length": length}


def tall_shield(b, side="L", face="team", size=(0.5, 0.8)):
    """Oval body shield with a steel rib and boss, held like round_shield (face along the forearm,
    angled outward) so it stands upright when the forearm comes up in a guard."""
    fist = humanoid.HAND[side]
    out = 1 if side == "L" else -1
    normal = Vector((out * math.sin(math.radians(30)), 0, -math.cos(math.radians(30))))
    up = Vector((0, -1, 0))
    w, h = size
    for name, build, mat, offset, scale in (
            ("shield_board", cylinder(0.5, 0.5, 0.045, 24), "wood", 0.05, (w, h, 1)),
            ("shield_face", cylinder(0.5, 0.5, 0.012, 24), face, 0.077, (w - 0.07, h - 0.07, 1)),
            ("shield_rib", box(0.05, h - 0.1, 0.02), "steel", 0.085, (1, 1, 1)),
            ("shield_boss", sphere(0.08, cut_below=0.0), "steel", 0.08, (1, 1, 1))):
        obj = make_mesh(name, build, mat, smooth=name == "shield_boss", bevel=0.008 if name == "shield_rib" else 0.0)
        place(obj, fist + normal * offset, y_axis=up, z_axis=normal)
        obj.scale = scale
        b.add(obj, "forearm." + side)


# --------------------------------------------------------------------------- archer kit

def cowl(b, mat="team", tail=True):
    """A hood up over the head, open at the face, with a pointed tail hanging down the back."""
    def build(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.275)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < -0.12 and v.co.z < 0.15], context="VERTS")
    c = humanoid.HEAD_CENTER
    obj = make_mesh("cowl", build, mat, smooth=True)
    obj.scale = (1, 1.04, 1.02)
    b.add(at(obj, c.x, c.y + 0.02, c.z + 0.02), "head")
    if tail:
        b.add(between(make_mesh("cowl_tail", cylinder(0.075, 0.0, 0.28, 10), mat, smooth=True),
                      Vector((0, 0.2, c.z + 0.1)), Vector((0, 0.36, c.z - 0.14))), "head")


def quiver(b, mat="leather", fletching="team", arrows=4):
    """A quiver on the back, its mouth by the right shoulder with arrow fletchings showing, and a
    strap across the chest."""
    lo, hi = Vector((0.1, 0.22, 0.6)), Vector((-0.14, 0.2, 1.06))
    along = (hi - lo).normalized()
    b.add(between(make_mesh("quiver", cylinder(0.072, 0.085, (hi - lo).length, 10), mat, smooth=True), lo, hi), "spine")
    b.add(between(make_mesh("quiver_rim", cylinder(0.09, 0.09, 0.04, 10), "dark_leather"), hi - along * 0.03, hi + along * 0.01), "spine")
    for k in range(arrows):
        a = 2 * math.pi * k / arrows
        base = hi + Vector((math.cos(a) * 0.035, math.sin(a) * 0.035, 0))
        b.add(between(make_mesh("quiver_arrow_%d" % k, cylinder(0.012, 0.012, 0.1, 6), "wood"), base, base + along * 0.1), "spine")
        vane = make_mesh("quiver_fletch_%d" % k, box(0.02, 0.07, 0.11), fletching, bevel=0.008)
        place(vane, base + along * 0.15, x_axis=Vector((math.cos(a), math.sin(a), 0)), z_axis=along)
        b.add(vane, "spine")
    strap = make_mesh("quiver_strap", box(0.05, 0.03, 0.5), "dark_leather")
    place(strap, Vector((0.0, -0.172, 0.82)), x_axis=Vector((1, 0, 0.75)).normalized(), y_axis=Y)
    b.add(strap, "spine")


def bow(b, held, side="L", aim=(0, -1, 0), height=1.2, depth=0.2, mat="wood"):
    """A longbow held at its grip in that fist, standing upright with its back toward `aim` in the
    pose `held` (the full draw). Returns {"top", "bottom": markers on the tips for a Cord string,
    "up", "forward": the rest-pose axes, "tips": rest-pose tip points}."""
    rot = humanoid.arm_rotation(held["rot"], side).inverted()
    up, fwd = rot @ Z, rot @ Vector(aim).normalized()
    fist = humanoid.HAND[side]
    count = 10
    pts = []
    for k in range(count + 1):
        t = 2 * k / count - 1
        pts.append(fist + up * (t * height / 2) - fwd * (depth * t * t) + fwd * 0.02)
    bone = "forearm." + side
    for k in range(count):
        t = abs(2 * (k + 0.5) / count - 1)
        r = 0.03 - 0.016 * t
        b.add(between(make_mesh("bow_%d" % k, cylinder(r, r, (pts[k + 1] - pts[k]).length + 0.012, 8), mat, smooth=True), pts[k], pts[k + 1]), bone)
    b.add(between(make_mesh("bow_grip", cylinder(0.038, 0.038, 0.13, 8), "dark_leather", smooth=True), fist - up * 0.065, fist + up * 0.065), bone)
    for name, p in (("bow_tip_top", pts[-1]), ("bow_tip_bottom", pts[0])):
        b.add(at(make_mesh(name, sphere(0.022, segments=8), "dark_leather", smooth=True), *p), bone)
    top = b.add(marker("bow_string_top", pts[-1]), bone)
    bottom = b.add(marker("bow_string_bottom", pts[0]), bone)
    return {"top": top, "bottom": bottom, "up": up, "forward": fwd, "tips": (pts[0], pts[-1])}


def arrow(b, held, side="R", aim=(0, -1, 0), length=0.78, fletching="team", name="arrow"):
    """An arrow nocked in that fist, pointing along `aim` in the pose `held`. Returns its parts,
    to show or hide with sk.toggle."""
    d = held_axis(b, held, side, aim)
    nock = humanoid.HAND[side] + d * 0.02
    tip = nock + d * length
    bone = "forearm." + side
    side_axis = d.cross(Z) if abs(d.dot(Z)) < 0.9 else d.cross(X)
    parts = [
        between(make_mesh(name + "_shaft", cylinder(0.013, 0.013, length, 6), "pale_wood"), nock, tip),
        between(make_mesh(name + "_head", cylinder(0.032, 0.0, 0.09, 4), "steel"), tip - d * 0.01, tip + d * 0.08),
    ]
    for k, x in enumerate((side_axis, side_axis.cross(d))):
        vane = make_mesh("%s_fletch_%d" % (name, k), box(0.008, 0.11, 0.045), fletching)
        place(vane, nock + d * 0.08, x_axis=x.normalized(), y_axis=d)
        parts.append(vane)
    for obj in parts:
        b.add(obj, bone)
    return parts


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
