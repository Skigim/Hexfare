"""Builds the 2D warrior sprite from scratch in Blender: models a low-poly warrior from
primitives, rigs it, keys its animations and renders every frame in the six hex directions.

    blender -b --factory-startup --python art/warrior/build_warrior.py [-- --only=idle,walk]

(--only renders just those animations into sheets in a temp folder, for a quick look.)

Writes art/warrior/warrior.blend (model, rig and animations, for tweaking by hand) and
assets/units/warrior/: warrior.png (every frame), warrior_mask.png (white where the team colour
goes; Godot tints those pixels per civ) and warrior.json (layout, anchor, frame rate).

Conventions: Z up, the warrior faces -Y with its right side at -X, feet at the origin. Animation
poses are written as rotations in armature space (see swing/lean/raise/turn) and converted to
each bone's local space, so they read the same whatever the bone rolls are.
"""
import json
import math
import os
import shutil
import struct
import sys
import tempfile
import zlib

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "units", "warrior")
BLEND_PATH = os.path.join(HERE, "warrior.blend")
NAME = "warrior"

CELL_W, CELL_H = 128, 160
ORTHO = 2.6           # world units across the cell height
ANCHOR = 0.78         # feet sit this far down the cell
ELEVATION = 40.0      # the camera looks down at this angle
FPS = 12
COLUMNS = 16
# Hex neighbours in Hex.DIRECTIONS order as screen offsets in pixels (scripts/core/hex.gd:
# pointy-top, 120 px wide, rows 105 px apart). Each facing points at that neighbour's centre.
DIRECTIONS = [("e", 120, 0), ("ne", 60, -105), ("nw", -60, -105),
              ("w", -120, 0), ("sw", -60, 105), ("se", 60, 105)]

X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))


# --------------------------------------------------------------------------- materials

PALETTE = {
    "skin": (0.96, 0.74, 0.58), "steel": (0.74, 0.78, 0.83), "dark_steel": (0.42, 0.45, 0.5),
    "leather": (0.48, 0.3, 0.17), "dark_leather": (0.26, 0.16, 0.1), "cloth": (0.3, 0.29, 0.35),
    "gold": (0.96, 0.74, 0.26), "wood": (0.62, 0.42, 0.23), "eye": (0.06, 0.05, 0.07),
    "team": (1.0, 1.0, 1.0),
}
TEAM_MATERIALS = {"team"}


def linear(c):
    """sRGB (as picked by eye) to the linear values shader nodes expect."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def toon_material(name, color):
    """Two-band cel shading: lit colour and a cooler shadow colour, split on the light."""
    mat = bpy.data.materials.new(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    diffuse = nodes.new("ShaderNodeBsdfDiffuse")
    to_rgb = nodes.new("ShaderNodeShaderToRGB")
    ramp = nodes.new("ShaderNodeValToRGB")
    emit = nodes.new("ShaderNodeEmission")
    out = nodes.new("ShaderNodeOutputMaterial")
    r, g, b = color
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (linear(r * 0.66), linear(g * 0.64), linear(b * 0.74), 1)
    ramp.color_ramp.elements[1].position = 0.32
    ramp.color_ramp.elements[1].color = (linear(r), linear(g), linear(b), 1)
    links.new(diffuse.outputs[0], to_rgb.inputs[0])
    links.new(to_rgb.outputs[0], ramp.inputs[0])
    links.new(ramp.outputs[0], emit.inputs[0])
    links.new(emit.outputs[0], out.inputs[0])
    return mat


def flat_material(name, value):
    mat = bpy.data.materials.new(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs[0].default_value = (value, value, value, 1)
    out = nodes.new("ShaderNodeOutputMaterial")
    links.new(emit.outputs[0], out.inputs[0])
    return mat


# --------------------------------------------------------------------------- geometry

def make_mesh(name, build, material, smooth=False, bevel=0.0, segments=2):
    bm = bmesh.new()
    build(bm)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(MATS[material])
    if smooth:
        me.shade_smooth()
        if hasattr(me, "set_sharp_from_angle"):
            me.set_sharp_from_angle(angle=math.radians(50))
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    if bevel:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
    return obj


def box(sx, sy, sz):
    def build(bm):
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    return build


def cylinder(r1, r2, depth, segments=10):
    def build(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                              radius1=r1, radius2=r2, depth=depth)
    return build


def sphere(r, sx=1.0, sy=1.0, sz=1.0, cut_below=None, segments=12):
    def build(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments // 2 + 1, radius=r)
        if cut_below is not None:
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < cut_below - 1e-4], context="VERTS")
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    return build


def place(obj, origin, x_axis=None, y_axis=None, z_axis=None):
    """Sets the object's world transform from an origin and (some of) its axes."""
    if x_axis is None:
        x_axis = Vector(y_axis).cross(Vector(z_axis))
    if y_axis is None:
        y_axis = Vector(z_axis).cross(Vector(x_axis))
    if z_axis is None:
        z_axis = Vector(x_axis).cross(Vector(y_axis))
    m = Matrix((Vector(x_axis).normalized(), Vector(y_axis).normalized(), Vector(z_axis).normalized())).transposed()
    obj.matrix_world = Matrix.Translation(origin) @ m.to_4x4()
    return obj


def at(obj, x, y, z):
    obj.location = (x, y, z)
    return obj


# --------------------------------------------------------------------------- the warrior

BONES = {
    # name: (head, tail, parent)
    "root": ((0, 0, 0), (0, 0, 0.25), None),
    "hips": ((0, 0, 0.5), (0, 0, 0.62), "root"),
    "spine": ((0, 0, 0.62), (0, 0, 1.0), "hips"),
    "head": ((0, 0, 1.0), (0, 0, 1.5), "spine"),
    "upperarm.R": ((-0.25, 0, 0.93), (-0.27, 0, 0.72), "spine"),
    "forearm.R": ((-0.27, 0, 0.72), (-0.28, 0, 0.5), "upperarm.R"),
    "upperarm.L": ((0.25, 0, 0.93), (0.27, 0, 0.72), "spine"),
    "forearm.L": ((0.27, 0, 0.72), (0.28, 0, 0.5), "upperarm.L"),
    "thigh.R": ((-0.11, 0, 0.48), (-0.11, 0, 0.28), "hips"),
    "shin.R": ((-0.11, 0, 0.28), (-0.11, 0, 0.06), "thigh.R"),
    "thigh.L": ((0.11, 0, 0.48), (0.11, 0, 0.28), "hips"),
    "shin.L": ((0.11, 0, 0.28), (0.11, 0, 0.06), "thigh.L"),
}


def build_body():
    """Returns [(object, bone)] for every part, modelled in the rest pose (arms down)."""
    parts = []

    def add(obj, bone):
        parts.append((obj, bone))
        return obj

    for side, sx in (("R", -1), ("L", 1)):
        # Legs: boot, shin, thigh.
        add(at(make_mesh("boot." + side, box(0.15, 0.24, 0.13), "dark_leather", bevel=0.035), sx * 0.11, -0.03, 0.065), "shin." + side)
        add(at(make_mesh("shin." + side, cylinder(0.062, 0.068, 0.2), "cloth", smooth=True), sx * 0.11, 0, 0.2), "shin." + side)
        add(at(make_mesh("thigh." + side, cylinder(0.07, 0.08, 0.22), "cloth", smooth=True), sx * 0.11, 0, 0.38), "thigh." + side)
        # Arms: pauldron, sleeve, bracer, fist.
        add(at(make_mesh("pauldron." + side, sphere(0.11, sz=0.75, cut_below=-0.03), "steel", smooth=True), sx * 0.25, 0, 0.93), "upperarm." + side)
        add(at(make_mesh("sleeve." + side, cylinder(0.058, 0.064, 0.22), "team", smooth=True), sx * 0.26, 0, 0.82), "upperarm." + side)
        add(at(make_mesh("bracer." + side, cylinder(0.06, 0.055, 0.2), "leather", smooth=True), sx * 0.275, 0, 0.62), "forearm." + side)
        add(at(make_mesh("fist." + side, sphere(0.068), "skin", smooth=True), sx * 0.28, 0, 0.5), "forearm." + side)

    # Hips and torso: trousers, tunic skirt, belt, chest.
    add(at(make_mesh("hips", box(0.3, 0.2, 0.14), "cloth", bevel=0.04), 0, 0, 0.5), "hips")
    add(at(make_mesh("skirt", cylinder(0.215, 0.18, 0.2, 8), "team"), 0, 0, 0.5), "hips")
    add(at(make_mesh("belt", cylinder(0.19, 0.19, 0.055, 8), "leather"), 0, 0, 0.615), "hips")
    add(at(make_mesh("buckle", box(0.07, 0.03, 0.05), "gold", bevel=0.01), 0, -0.19, 0.615), "hips")
    chest = make_mesh("chest", cylinder(0.18, 0.215, 0.36, 8), "team")
    chest.scale = (1, 0.82, 1)
    add(at(chest, 0, 0, 0.82), "spine")
    add(at(make_mesh("collar", cylinder(0.12, 0.1, 0.06, 8), "leather"), 0, 0, 1.01), "spine")

    # Head: rounded face, eyes, helmet with nasal guard, crest in the team colour.
    add(at(make_mesh("head", box(0.42, 0.4, 0.4), "skin", smooth=True, bevel=0.13, segments=3), 0, 0, 1.22), "head")
    for side, sx in (("R", -1), ("L", 1)):
        add(at(make_mesh("eye." + side, sphere(0.032, sz=1.4, segments=8), "eye", smooth=True), sx * 0.085, -0.195, 1.2), "head")
    add(at(make_mesh("helmet", sphere(0.255, sy=0.95, cut_below=0.0, segments=16), "steel", smooth=True), 0, 0.01, 1.27), "head")
    add(at(make_mesh("helmet_rim", cylinder(0.262, 0.262, 0.045, 16), "dark_steel"), 0, 0.01, 1.28), "head")
    add(at(make_mesh("nasal", box(0.04, 0.03, 0.15), "steel", bevel=0.01), 0, -0.235, 1.21), "head")
    add(at(make_mesh("crest", box(0.055, 0.34, 0.11), "team", bevel=0.03), 0, 0.03, 1.55), "head")

    # Sword in the right fist: the blade leaves the thumb side of the fist (forward, tilted up)
    # and its edges lie in the swing plane, so a chop leads with the edge.
    fist = Vector((-0.28, 0, 0.5))
    tilt = math.radians(15)
    blade_dir = Vector((0, -math.cos(tilt), math.sin(tilt)))
    edge_dir = Vector((0, math.sin(tilt), math.cos(tilt)))
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
        add(obj, "forearm.R")

    # Round shield on the left fist (centre grip): its face looks along the forearm, so when the
    # forearm comes up in the guard pose the shield stands upright facing forward. It is angled
    # 30 degrees outward so its face still shows when the warrior is seen in profile.
    fist = Vector((0.28, 0, 0.5))
    normal = Vector((math.sin(math.radians(30)), 0, -math.cos(math.radians(30))))
    up = Vector((0, -1, 0))
    for name, build, mat, offset in (
            ("shield_board", cylinder(0.27, 0.27, 0.045, 18), "wood", 0.05),
            ("shield_face", cylinder(0.215, 0.215, 0.012, 18), "team", 0.077),
            ("shield_boss", sphere(0.075, cut_below=0.0), "steel", 0.08)):
        obj = make_mesh(name, build, mat, smooth=name == "shield_boss")
        place(obj, fist + normal * offset, y_axis=up, z_axis=normal)
        add(obj, "forearm.L")
    return parts


def build_rig(parts):
    arm_data = bpy.data.armatures.new(NAME + "_rig")
    rig = bpy.data.objects.new(NAME, arm_data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (head, tail, parent) in BONES.items():
        eb = arm_data.edit_bones.new(name)
        eb.head, eb.tail = head, tail
        eb.roll = 0.0
        if parent:
            eb.parent = arm_data.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()
    for obj, bone in parts:
        world = obj.matrix_world.copy()
        obj.parent = rig
        obj.parent_type = "BONE"
        obj.parent_bone = bone
        bpy.context.view_layer.update()
        obj.matrix_world = world
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return rig


# --------------------------------------------------------------------------- posing

def quat(axis, deg):
    return Quaternion(axis, math.radians(deg))


def swing(deg):
    """Hanging limbs: positive swings forward (toward -Y)."""
    return quat(X, -deg)


def lean(deg):
    """Upright bones: positive leans forward."""
    return quat(X, deg)


def raise_(side, deg):
    """Positive lifts the limb out to its own side."""
    return quat(Y, deg if side == "R" else -deg)


def turn(deg):
    """Positive turns toward the warrior's left."""
    return quat(Z, deg)


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
    return {"rot": rot, "loc": {k.replace("__", "."): Vector(v) for k, v in locs.items()}}


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
    p = 2 * math.pi * i / n
    s = math.sin(p)
    rot = {
        "hips": turn(6 * s),
        "spine": lean(8) @ turn(-10 - 8 * s),
        "head": lean(-4) @ turn(9 + 2 * s),
        "upperarm.R": swing(12 - 22 * s) @ raise_("R", 12),
        "forearm.R": swing(50 + 6 * s),
        "upperarm.L": swing(34 + 5 * s) @ raise_("L", 16),
    }
    for side, phase in (("R", p), ("L", p + math.pi)):
        rot["thigh." + side] = swing(26 * math.sin(phase))
        rot["shin." + side] = swing(-45 * max(0.0, math.cos(phase)) ** 1.5 - 4)
    return pose(rot, hips=(0, 0, 0.022 * math.cos(2 * p) - 0.012))


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


def keyed(i, keys):
    """Interpolates between (frame, pose) keys with ease-in-out."""
    for (f0, a), (f1, b) in zip(keys, keys[1:]):
        if f0 <= i <= f1:
            t = (i - f0) / (f1 - f0) if f1 > f0 else 1.0
            return blend(a, b, t * t * (3 - 2 * t))
    return keys[-1][1]


def blend(a, b, t):
    rot = {}
    for bone in set(a["rot"]) | set(b["rot"]):
        rot[bone] = a["rot"].get(bone, Quaternion()).slerp(b["rot"].get(bone, Quaternion()), t)
    loc = {}
    for bone in set(a["loc"]) | set(b["loc"]):
        loc[bone] = a["loc"].get(bone, Vector()).lerp(b["loc"].get(bone, Vector()), t)
    return {"rot": rot, "loc": loc}


# name: (pose function, frames, loops)
ANIMATIONS = {
    "idle": (idle, 12, True),
    "walk": (walk, 8, True),
    "attack": (attack, 9, False),
    "hit": (hit, 5, False),
    "death": (death, 8, False),
}


def apply_pose(rig, p):
    for pb in rig.pose.bones:
        rest = pb.bone.matrix_local.to_quaternion()
        q = p["rot"].get(pb.name, Quaternion())
        pb.rotation_quaternion = rest.inverted() @ q @ rest
        offset = p["loc"].get(pb.name, Vector())
        pb.location = rest.inverted() @ offset


def key_animations(rig, yaw):
    """Keys every frame of every animation on one timeline, with a marker at each start (for
    looking at in Blender; the renders pose each direction directly, see render_all)."""
    scene = bpy.context.scene
    starts = {}
    frame = 1
    for name, (func, count, _loops) in ANIMATIONS.items():
        starts[name] = frame
        scene.timeline_markers.new(name, frame=frame)
        for i in range(count):
            apply_pose(rig, func(i, count, yaw))
            for pb in rig.pose.bones:
                pb.keyframe_insert("rotation_quaternion", frame=frame + i)
                pb.keyframe_insert("location", frame=frame + i)
        frame += count + 8
    scene.frame_start, scene.frame_end = 1, frame - 8
    return starts


# --------------------------------------------------------------------------- camera and render

def facing_yaw(dx, dy):
    """Yaw that makes the warrior's forward vector land on screen pointing along (dx, dy)."""
    beta = math.atan2(-dy, dx)                      # screen angle, up positive
    a = math.atan2(math.sin(beta) / math.sin(math.radians(ELEVATION)), math.cos(beta))
    return a + math.pi / 2                          # forward is -Y at yaw 0


def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = CELL_W, CELL_H
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.fps = FPS
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.eevee.taa_render_samples = 16

    cam_data = bpy.data.cameras.new("camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ORTHO
    cam_data.shift_y = ANCHOR - 0.5
    cam = bpy.data.objects.new("camera", cam_data)
    scene.collection.objects.link(cam)
    el = math.radians(ELEVATION)
    forward = Vector((0, math.cos(el), -math.sin(el)))
    cam.location = -forward * 12
    cam.rotation_euler = (math.pi / 2 - el, 0, 0)
    scene.camera = cam

    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.0
    sun_data.use_shadow = False
    sun = bpy.data.objects.new("sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), math.radians(-25), math.radians(-35))

    world = bpy.data.worlds.new("world")
    bg = world.node_tree.nodes.get("Background") if world.node_tree else None
    if bg is not None:
        bg.inputs[0].default_value = (1, 1, 1, 1)
        bg.inputs[1].default_value = 0.15
    scene.world = world


def render_all(rig, folder, only):
    """Renders every frame in every direction. Poses are applied directly rather than played from
    the keyed timeline because some (death) depend on the facing."""
    scene = bpy.context.scene
    if rig.animation_data:
        rig.animation_data.action = None
    for name, (func, count, _loops) in ANIMATIONS.items():
        if only and name not in only:
            continue
        for dname, dx, dy in DIRECTIONS:
            yaw = facing_yaw(dx, dy)
            rig.rotation_euler = (0, 0, yaw)
            for i in range(count):
                apply_pose(rig, func(i, count, yaw))
                scene.render.filepath = os.path.join(folder, "%s_%s_%02d.png" % (name, dname, i))
                bpy.ops.render.render(write_still=True)


def swap_to_mask(mask_on, mask_off):
    saved = {}
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        saved[obj.name] = [s.material for s in obj.material_slots]
        for slot in obj.material_slots:
            slot.material = mask_on if slot.material.name in TEAM_MATERIALS else mask_off
    return saved


def restore_materials(saved):
    for name, mats in saved.items():
        for slot, mat in zip(bpy.data.objects[name].material_slots, mats):
            slot.material = mat


# --------------------------------------------------------------------------- sheets

def load_rgba(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return np.flipud(px.reshape(h, w, 4))


def write_png(path, array):
    """Writes an 8-bit PNG (H x W gray or H x W x 4 RGBA, floats 0..1) without colour management."""
    data = (np.clip(array, 0, 1) * 255 + 0.5).astype(np.uint8)
    h, w = data.shape[:2]
    color_type = 0 if data.ndim == 2 else 6
    raw = b"".join(b"\x00" + data[y].tobytes() for y in range(h))

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def write_import(png, extra):
    """Asks Godot to VRAM-compress a sheet (BC7 colour, BC4 mask: about a quarter of the memory).
    Only written when missing; Godot fills in the rest and keeps these settings on rebuilds."""
    path = png + ".import"
    if os.path.exists(path):
        return
    lines = ["[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "", "[params]", "",
             "compress/mode=2", extra, "mipmaps/generate=true"]
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def assemble(color_dir, mask_dir, out_dir, only=None):
    layout, cells = {}, []
    for name, (_func, count, loops) in ANIMATIONS.items():
        if only and name not in only:
            continue
        layout[name] = {"first": len(cells), "frames": count, "loop": loops}
        for dname, _dx, _dy in DIRECTIONS:
            for i in range(count):
                cells.append("%s_%s_%02d.png" % (name, dname, i))
    rows = math.ceil(len(cells) / COLUMNS)
    sheet = np.zeros((rows * CELL_H, COLUMNS * CELL_W, 4), dtype=np.float32)
    mask = np.zeros((rows * CELL_H, COLUMNS * CELL_W), dtype=np.float32)
    for index, file in enumerate(cells):
        y, x = (index // COLUMNS) * CELL_H, (index % COLUMNS) * CELL_W
        sheet[y:y + CELL_H, x:x + CELL_W] = load_rgba(os.path.join(color_dir, file))
        mask[y:y + CELL_H, x:x + CELL_W] = load_rgba(os.path.join(mask_dir, file))[:, :, 0]
    os.makedirs(out_dir, exist_ok=True)
    write_png(os.path.join(out_dir, NAME + ".png"), sheet)
    write_png(os.path.join(out_dir, NAME + "_mask.png"), mask)
    write_import(os.path.join(out_dir, NAME + ".png"), "compress/high_quality=true")
    write_import(os.path.join(out_dir, NAME + "_mask.png"), "compress/channel_pack=1")
    meta = {
        "sheet": NAME + ".png", "mask": NAME + "_mask.png",
        "cell": [CELL_W, CELL_H], "columns": COLUMNS, "fps": FPS,
        "anchor": [CELL_W / 2, round(CELL_H * ANCHOR, 1)],
        "directions": [d[0] for d in DIRECTIONS],
        "animations": layout,
        "note": "Cell index = first + direction * frames + frame. Directions follow Hex.DIRECTIONS.",
    }
    with open(os.path.join(out_dir, NAME + ".json"), "w") as f:
        json.dump(meta, f, indent=1)


# --------------------------------------------------------------------------- main

def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    for a in args:
        if a.startswith("--only="):
            only = set(a.split("=", 1)[1].split(","))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0   # no warrior.blend1 backups
    global MATS
    MATS = {name: toon_material(name, color) for name, color in PALETTE.items()}
    rig = build_rig(build_body())
    se = facing_yaw(60, 105)
    key_animations(rig, se)
    setup_scene()
    rig.rotation_euler = (0, 0, se)   # saved facing SE
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

    tmp = tempfile.mkdtemp(prefix="warrior_")
    color_dir, mask_dir = os.path.join(tmp, "color"), os.path.join(tmp, "mask")
    render_all(rig, color_dir, only)
    saved = swap_to_mask(flat_material("mask_on", 1.0), flat_material("mask_off", 0.0))
    render_all(rig, mask_dir, only)
    restore_materials(saved)
    if only:   # a quick look: sheets for just these animations, left in the temp folder
        assemble(color_dir, mask_dir, tmp, only)
        print("Partial sheets in", tmp)
        return
    assemble(color_dir, mask_dir, OUT_DIR)
    shutil.rmtree(tmp, ignore_errors=True)
    print("Wrote", OUT_DIR)


MATS = {}
main()
