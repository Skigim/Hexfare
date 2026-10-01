"""The shared pipeline behind every pre-rendered unit sprite (art/<unit>/build_<unit>.py):
toon materials, primitive meshes, bone-parented rigs, posing, ropes, the camera and the six hex
facings, rendering and sheet assembly. Body libraries (humanoid.py, quadruped.py) and gear.py
build on it; a unit script only adds what is unique to that unit and calls build().

Conventions: Z up, actors face -Y with their right side at -X, feet at the origin. Poses are
rotations in armature space (swing/lean/raise_/turn) that apply_pose converts to each bone's local
space, so they read the same whatever the bone rolls are. A pose is {"rot": {bone: Quaternion},
"loc": {bone: Vector}, "show": {object name: bool}}; bones it leaves out stay at rest and
objects registered with toggle() it leaves out show their default (a tool on the belt, then in
the hand).

The scale is fixed for every unit (PX_PER_UNIT), so units drawn side by side match; a unit that
needs more room asks for a bigger cell.
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

ART = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(ART)

PX_PER_UNIT = 160 / 2.6   # world units to sheet pixels, the same for every unit
ELEVATION = 40.0          # the camera looks down at this angle
FPS = 12
COLUMNS = 16
# Hex neighbours in Hex.DIRECTIONS order as screen offsets in pixels (scripts/core/hex.gd:
# pointy-top, 120 px wide, rows 105 px apart). Each facing points at that neighbour's centre.
DIRECTIONS = [("e", 120, 0), ("ne", 60, -105), ("nw", -60, -105),
              ("w", -120, 0), ("sw", -60, 105), ("se", 60, 105)]

X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))


# --------------------------------------------------------------------------- materials

# Colours as picked by eye (sRGB). Units add their own with COLORS.update(...).
COLORS = {
    "skin": (0.96, 0.74, 0.58), "eye": (0.06, 0.05, 0.07),
    "steel": (0.74, 0.78, 0.83), "dark_steel": (0.42, 0.45, 0.5), "gold": (0.96, 0.74, 0.26), "pale_wood": (0.8, 0.63, 0.42), "dust": (0.83, 0.76, 0.62),
    "leather": (0.48, 0.3, 0.17), "dark_leather": (0.26, 0.16, 0.1), "wood": (0.62, 0.42, 0.23),
    "cloth": (0.3, 0.29, 0.35), "linen": (0.86, 0.8, 0.66), "felt": (0.47, 0.34, 0.25),
    "dark_felt": (0.3, 0.21, 0.16),
    "team": (1.0, 1.0, 1.0),
}
# Materials Godot tints with the civ colour (white in the mask). Their colour is multiplied by
# the civ colour, so "team" is the full colour and a grey would be a darker shade of it.
TEAM = {"team"}

_materials = {}


def material(name):
    if name not in _materials:
        _materials[name] = toon_material(name, COLORS[name])
    return _materials[name]


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

def make_mesh(name, build, mat, smooth=False, bevel=0.0, segments=2):
    bm = bmesh.new()
    build(bm)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material(mat))
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


def cylinder(r1, r2, depth, segments=10, caps=True):
    """Along Z, centred; r1 at the bottom."""
    def build(bm):
        bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segments,
                              radius1=r1, radius2=r2, depth=depth)
    return build


def sphere(r, sx=1.0, sy=1.0, sz=1.0, cut_below=None, segments=12):
    def build(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments // 2 + 1, radius=r)
        if cut_below is not None:
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < cut_below - 1e-4], context="VERTS")
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    return build


def shell(r1, r2, depth, keep, segments=16):
    """An open tube along Z (r1 at the bottom) keeping only the vertices where keep(co) is true:
    capes, saddle cloths, anything draped."""
    def build(bm):
        bmesh.ops.create_cone(bm, cap_ends=False, cap_tris=False, segments=segments,
                              radius1=r1, radius2=r2, depth=depth)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v.co)], context="VERTS")
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
    scale = obj.scale.copy()
    obj.matrix_world = Matrix.Translation(origin) @ m.to_4x4()
    obj.scale = scale
    return obj


def between(obj, a, b, roll_x=None):
    """Points a Z-built mesh (cylinder, cone) from a to b, centred between them."""
    a, b = Vector(a), Vector(b)
    z = (b - a).normalized()
    x = Vector(roll_x) if roll_x is not None else (X if abs(z.dot(X)) < 0.9 else Y)
    x = (x - z * x.dot(z)).normalized()
    return place(obj, (a + b) / 2, x_axis=x, z_axis=z)


def at(obj, x, y, z):
    obj.location = (x, y, z)
    return obj


def marker(name, location):
    """An empty, for parenting to a bone and reading back its posed position (rope ends)."""
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = 0.05
    obj.location = location
    bpy.context.scene.collection.objects.link(obj)
    return obj


# --------------------------------------------------------------------------- rigs

class Body:
    """An actor under construction: bones {name: (head, tail, parent)} and the parts that ride
    them [(object, bone)]. Body libraries return one; units add gear with add() and combine
    actors into one rig with moved()/build_rig()."""

    def __init__(self, bones=None):
        self.bones = dict(bones or {})
        self.parts = []

    def add(self, obj, bone):
        self.parts.append((obj, bone))
        return obj

    def moved(self, offset, prefix="", scale=1.0):
        """Scales the whole actor about its feet, shifts it by offset and prefixes its bone names
        (a second actor in a rig)."""
        offset = Vector(offset)
        bpy.context.view_layer.update()   # parts placed with .location: refresh matrix_world
        bones = {}
        for name, (head, tail, parent) in self.bones.items():
            bones[prefix + name] = (tuple(Vector(head) * scale + offset), tuple(Vector(tail) * scale + offset),
                                    prefix + parent if parent else None)
        self.bones = bones
        m = Matrix.Translation(offset) @ Matrix.Scale(scale, 4)
        for obj, _bone in self.parts:
            obj.matrix_world = m @ obj.matrix_world
        self.parts = [(obj, prefix + bone) for obj, bone in self.parts]
        return self

    def merge(self, other):
        self.bones.update(other.bones)
        self.parts += other.parts
        return self


def build_rig(name, body):
    arm_data = bpy.data.armatures.new(name + "_rig")
    rig = bpy.data.objects.new(name, arm_data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone, (head, tail, parent) in body.bones.items():
        eb = arm_data.edit_bones.new(bone)
        eb.head, eb.tail = head, tail
        eb.roll = 0.0
        if parent:
            eb.parent = arm_data.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()
    for obj, bone in body.parts:
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
    """Upright bones: positive leans forward. Forward-pointing bones (a beast's head): positive
    tips down."""
    return quat(X, deg)


def raise_(side, deg):
    """Positive lifts the limb out to its own side ("R" or "L")."""
    return quat(Y, deg if side == "R" else -deg)


def turn(deg):
    """Positive turns toward the actor's left."""
    return quat(Z, deg)


def pose(rot=None, loc=None, show=None):
    return {"rot": dict(rot or {}), "loc": {k: Vector(v) for k, v in (loc or {}).items()},
            "show": dict(show or {})}


def merge(*poses):
    """One pose from several (later ones win per bone): a rig holding more than one actor."""
    out = pose()
    for p in poses:
        out["rot"].update(p["rot"])
        out["loc"].update(p["loc"])
        out["show"].update(p.get("show", {}))
    return out


TOGGLES = {}   # object name -> shown when a pose doesn't say


def toggle(obj, shown=True):
    """Lets poses show or hide this object ("show" in a pose); `shown` is its default."""
    TOGGLES[obj.name] = shown
    return obj


def layer(rot, delta):
    """Adds small armature-space rotations on top of a set of bone rotations (breathing, sway)."""
    out = dict(rot)
    for bone, q in delta.items():
        out[bone] = q @ out.get(bone, Quaternion())
    return out


def prefixed(p, prefix):
    """Puts a pose on a prefixed actor's bones (object names in "show" are left alone)."""
    return {"rot": {prefix + k: v for k, v in p["rot"].items()},
            "loc": {prefix + k: v for k, v in p["loc"].items()},
            "show": dict(p.get("show", {}))}


def chain(rot, bones):
    """The armature-space rotation a part on the last of `bones` gets from them all (root first):
    for orienting a held item so it lands right in a given pose."""
    q = Quaternion()
    for bone in bones:
        q = q @ rot.get(bone, Quaternion())
    return q


def posed_point(bones, p, bone, point):
    """Where a rest-pose point riding `bone` ends up in pose p (armature space), worked out from
    the bone table without touching Blender: for fitting gear to a pose."""
    path = []
    while bone:
        path.append(bone)
        bone = bones[bone][2]
    m = Matrix.Identity(4)
    for name in reversed(path):
        head = Vector(bones[name][0])
        q = p["rot"].get(name, Quaternion())
        offset = p["loc"].get(name, Vector())
        m = m @ Matrix.Translation(head + offset) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head)
    return m @ Vector(point)


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
    return {"rot": rot, "loc": loc, "show": dict((a if t < 0.5 else b).get("show", {}))}


def wave(i, n, cycles=1, phase=0.0):
    """sin over the loop: `cycles` whole periods in n frames, so loops stay seamless."""
    return math.sin(2 * math.pi * cycles * i / n + phase)


def pulse(i, n, start, length):
    """0 -> 1 -> 0 over `length` frames from `start` (wrapping): a twitch, a blink."""
    t = ((i - start) % n) / length
    return math.sin(math.pi * t) ** 2 if t < 1 else 0.0


def apply_pose(rig, p):
    for pb in rig.pose.bones:
        rest = pb.bone.matrix_local.to_quaternion()
        q = p["rot"].get(pb.name, Quaternion())
        pb.rotation_quaternion = rest.inverted() @ q @ rest
        offset = p["loc"].get(pb.name, Vector())
        pb.location = rest.inverted() @ offset
    for name, shown in TOGGLES.items():
        obj = bpy.data.objects[name]
        obj.hide_render = obj.hide_viewport = not p.get("show", {}).get(name, shown)
    for rope in ROPES:
        rope.update()


# --------------------------------------------------------------------------- ropes

ROPES = []


class Rope:
    """A slack rope between two markers (parented to bones), re-hung after every pose."""

    def __init__(self, name, start, end, mat="leather", radius=0.012, slack=0.08, points=12):
        self.start, self.end, self.slack, self.count = start, end, slack, points
        curve = bpy.data.curves.new(name, "CURVE")
        curve.dimensions = "3D"
        curve.bevel_depth = radius
        curve.bevel_resolution = 2
        curve.use_fill_caps = True
        curve.materials.append(material(mat))
        self.spline = curve.splines.new("POLY")
        self.spline.points.add(points - 1)
        self.obj = bpy.data.objects.new(name, curve)
        bpy.context.scene.collection.objects.link(self.obj)
        ROPES.append(self)

    def update(self):
        bpy.context.view_layer.update()
        a = self.start.matrix_world.translation
        b = self.end.matrix_world.translation
        for k, point in enumerate(self.spline.points):
            t = k / (self.count - 1)
            p = a.lerp(b, t)
            p.z = max(0.01, p.z - self.slack * 4 * t * (1 - t))
            point.co = (p.x, p.y, p.z, 1)


# --------------------------------------------------------------------------- camera and render

def facing_yaw(dx, dy):
    """Yaw that makes an actor's forward vector land on screen pointing along (dx, dy)."""
    beta = math.atan2(-dy, dx)                      # screen angle, up positive
    a = math.atan2(math.sin(beta) / math.sin(math.radians(ELEVATION)), math.cos(beta))
    return a + math.pi / 2                          # forward is -Y at yaw 0


def setup_scene(cell, anchor):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = cell
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
    cam_data.sensor_fit = "VERTICAL"     # ortho scale and shift measure the cell height
    cam_data.ortho_scale = cell[1] / PX_PER_UNIT
    cam_data.shift_y = anchor - 0.5
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


def key_animations(rig, animations, yaw):
    """Keys every frame of every animation on one timeline, with a marker at each start (for
    looking at in Blender; the renders pose each direction directly, see render_all). Ropes are
    hung by script, so in the .blend they stay where the first pose left them."""
    scene = bpy.context.scene
    frame = 1
    for name, (func, count, *_rest) in animations.items():
        scene.timeline_markers.new(name, frame=frame)
        for i in range(count):
            apply_pose(rig, func(i, count, yaw))
            for pb in rig.pose.bones:
                pb.keyframe_insert("rotation_quaternion", frame=frame + i)
                pb.keyframe_insert("location", frame=frame + i)
        frame += count + 8
    scene.frame_start, scene.frame_end = 1, frame - 8


def render_all(rig, animations, directions, folder):
    """Renders every frame in every direction. Poses are applied directly rather than played from
    the keyed timeline because some (a death) depend on the facing."""
    scene = bpy.context.scene
    if rig.animation_data:
        rig.animation_data.action = None
    for name, (func, count, *_rest) in animations.items():
        for dname, dx, dy in directions:
            yaw = facing_yaw(dx, dy)
            rig.rotation_euler = (0, 0, yaw)
            for i in range(count):
                apply_pose(rig, func(i, count, yaw))
                scene.render.filepath = os.path.join(folder, "%s_%s_%02d.png" % (name, dname, i))
                bpy.ops.render.render(write_still=True)


def swap_to_mask(mask_on, mask_off):
    saved = {}
    for obj in bpy.data.objects:
        if obj.type not in ("MESH", "CURVE"):
            continue
        saved[obj.name] = [s.material for s in obj.material_slots]
        for slot in obj.material_slots:
            slot.material = mask_on if slot.material.name in TEAM else mask_off
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


def assemble(name, animations, directions, cell, anchor, color_dir, mask_dir, out_dir, base=None):
    cell_w, cell_h = cell
    layout, cells = {}, []
    for anim, (_func, count, loops, *extra) in animations.items():
        layout[anim] = {"first": len(cells), "frames": count, "loop": loops}
        if extra:
            layout[anim]["marks"] = extra[0]   # named frames the game times things by
        for dname, _dx, _dy in directions:
            for i in range(count):
                cells.append("%s_%s_%02d.png" % (anim, dname, i))
    columns = min(COLUMNS, len(cells))
    rows = math.ceil(len(cells) / columns)
    sheet = np.zeros((rows * cell_h, columns * cell_w, 4), dtype=np.float32)
    mask = np.zeros((rows * cell_h, columns * cell_w), dtype=np.float32)
    for index, file in enumerate(cells):
        y, x = (index // columns) * cell_h, (index % columns) * cell_w
        sheet[y:y + cell_h, x:x + cell_w] = load_rgba(os.path.join(color_dir, file))
        mask[y:y + cell_h, x:x + cell_w] = load_rgba(os.path.join(mask_dir, file))[:, :, 0]
    os.makedirs(out_dir, exist_ok=True)
    write_png(os.path.join(out_dir, name + ".png"), sheet)
    write_png(os.path.join(out_dir, name + "_mask.png"), mask)
    write_import(os.path.join(out_dir, name + ".png"), "compress/high_quality=true")
    write_import(os.path.join(out_dir, name + "_mask.png"), "compress/channel_pack=1")
    meta = {
        "sheet": name + ".png", "mask": name + "_mask.png",
        "cell": [cell_w, cell_h], "columns": columns, "fps": FPS,
        "anchor": [cell_w / 2, round(cell_h * anchor, 1)],
        "directions": [d[0] for d in directions],
        "animations": layout,
        "base": list(base) if base else None,
        "note": "Cell index = first + direction * frames + frame. Directions follow Hex.DIRECTIONS.",
    }
    if meta["base"] is None:
        del meta["base"]
    with open(os.path.join(out_dir, name + ".json"), "w") as f:
        json.dump(meta, f, indent=1)


# --------------------------------------------------------------------------- driver

def build(name, model, animations, cell=(128, 160), anchor=0.78, directions=None, out_dir=None, base=None):
    """Builds a unit: model() returns its rig (after build_rig); animations maps a role to
    (pose function (frame, frames, yaw) -> pose, frames, loops[, marks]), marks naming frames the
    game can time events by, e.g. {"strike": 17}. Saves art/<name>/<name>.blend and
    writes the sheet, mask and layout to out_dir (default assets/units/<name>). base = (rx, ry)
    sizes the oval stand the game draws under the unit, in sheet pixels (default: the warrior's).

    Command line (after --): --only=idle,walk renders just those roles and --dirs=se,e just those
    facings, into a temp folder for a quick look; --out=<dir> writes the full sheets there instead
    (and leaves the .blend alone), e.g. to compare a rebuild with the committed sheets.
    """
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = dirs = out = None
    for a in args:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
        elif a.startswith("--dirs="):
            dirs = a.split("=", 1)[1].split(",")
        elif a.startswith("--out="):
            out = os.path.abspath(a.split("=", 1)[1])
    wanted = [d for d in DIRECTIONS if directions is None or d[0] in directions]
    if dirs:
        wanted = [d for d in wanted if d[0] in dirs]
    anims = {k: v for k, v in animations.items() if not only or k in only}
    quick = bool(only or dirs)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0   # no .blend1 backups
    _materials.clear()
    ROPES.clear()
    TOGGLES.clear()
    rig = model()
    se = facing_yaw(60, 105)
    key_animations(rig, animations, se)
    setup_scene(cell, anchor)
    rig.rotation_euler = (0, 0, se)   # saved facing SE
    if not quick and out is None:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ART, name, name + ".blend"))

    tmp = tempfile.mkdtemp(prefix=name + "_")
    color_dir, mask_dir = os.path.join(tmp, "color"), os.path.join(tmp, "mask")
    render_all(rig, anims, wanted, color_dir)
    saved = swap_to_mask(flat_material("mask_on", 1.0), flat_material("mask_off", 0.0))
    render_all(rig, anims, wanted, mask_dir)
    restore_materials(saved)
    target = tmp if quick else (out or out_dir or os.path.join(ROOT, "assets", "units", name))
    assemble(name, anims, wanted, cell, anchor, color_dir, mask_dir, target, base)
    if not quick:
        shutil.rmtree(tmp, ignore_errors=True)
    print("Wrote", target)
    return target
