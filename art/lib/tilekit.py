"""The shared pipeline behind pre-rendered terrain tiles (art/tiles/build_<terrain>.py): the hex
silhouette, a straight-down orthographic camera, flat colour materials, flat polygon and stroke
meshes, rendering and PNG output. Unit sprites have their own kit (spritekit.py); this one reuses
its scale and PNG helpers so a tile and a unit drawn side by side match.

A tile script calls build(name, make_tile, variants, ...). make_tile(variant, i, n) draws frame i
of n of one variant (pixel coordinates, origin at the tile's top-left, y down) and tiles are
written to assets/terrain/<name>_<variant>.png. With n == 1 that is the whole story. With n > 1 the
file is a horizontal strip of n tiles plus <name>_<variant>.json with {"frames", "fps"}, ready for
the game to step through (no game code does yet). Make frame i depend on t = i / n through sin/cos
of whole cycles and the loop is seamless; frame 0 is always the still tile.

Conventions: the tile is TILE_W x TILE_H pixels like the Kenney tiles, a pointy-top hex whose side
edges touch the image edges, so neighbouring tiles abut exactly (see Hex in scripts/core/hex.gd).
Everything is flat emission colour: tiles are lit by their own colours, not by the scene.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spritekit as sk  # noqa: E402

TILE_W, TILE_H = 120, 140
FPS = 8
# Corners in tile pixels, clockwise from the top. The sides are vertical from y 35 to 105.
HEX = [(60, 0), (120, 35), (120, 105), (60, 140), (0, 105), (0, 35)]
PPU = sk.PX_PER_UNIT   # pixels per Blender unit, the same as units
BLEED = 1.04           # the render is a little larger than the hex, then cut to it (no seams)

_materials = {}


# --------------------------------------------------------------------------- shapes in pixels

def hex_inset(margin):
    """The hex shrunk by margin pixels on every side, for keeping marks off the edges."""
    cx, cy = TILE_W / 2, TILE_H / 2
    out = []
    for x, y in HEX:
        d = math.hypot(x - cx, y - cy)
        k = (d - margin / math.cos(math.radians(30))) / d   # corner to inset corner
        out.append((cx + (x - cx) * k, cy + (y - cy) * k))
    return out


def inside(poly, x, y):
    """True when (x, y) is inside the convex clockwise (y down) polygon."""
    for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1]):
        if (x2 - x1) * (y - y1) - (y2 - y1) * (x - x1) < 0:
            return False
    return True


def hex_mask():
    """H x W bool array, true for pixels whose centre is inside the hex."""
    ys, xs = np.mgrid[0:TILE_H, 0:TILE_W]
    xs, ys = xs + 0.5, ys + 0.5
    mask = np.ones((TILE_H, TILE_W), dtype=bool)
    for (x1, y1), (x2, y2) in zip(HEX, HEX[1:] + HEX[:1]):
        mask &= (x2 - x1) * (ys - y1) - (y2 - y1) * (xs - x1) >= 0
    return mask


# --------------------------------------------------------------------------- drawing

def flat_material(srgb):
    """Emission-only colour (sRGB as picked by eye), cached."""
    key = tuple(srgb)
    if key not in _materials:
        mat = bpy.data.materials.new("flat%s" % (len(_materials),))
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        nodes.clear()
        emit = nodes.new("ShaderNodeEmission")
        emit.inputs[0].default_value = tuple(sk.linear(c) for c in srgb) + (1,)
        out = nodes.new("ShaderNodeOutputMaterial")
        links.new(emit.outputs[0], out.inputs[0])
        _materials[key] = mat
    return _materials[key]


def _world(x, y):
    return ((x - TILE_W / 2) / PPU, (TILE_H / 2 - y) / PPU)


def _mesh(name, verts, faces, srgb, z):
    me = bpy.data.meshes.new(name)
    me.from_pydata([(*_world(x, y), z) for x, y in verts], [], faces)
    me.materials.append(flat_material(srgb))
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def polygon(pts, srgb, layer=0):
    """A flat convex polygon (pixels, clockwise); layer stacks later shapes over earlier ones."""
    return _mesh("poly", pts, [list(range(len(pts)))[::-1]], srgb, layer * 0.01)


def stroke(centre, width, srgb, layer=1, taper=0.8):
    """A line along the points of `centre` (pixels), `width` px at its thickest and tapering
    to a point at both ends (taper 0 is a constant width)."""
    n = len(centre)
    left, right = [], []
    for i, (x, y) in enumerate(centre):
        ax, ay = centre[max(i - 1, 0)]
        bx, by = centre[min(i + 1, n - 1)]
        length = math.hypot(bx - ax, by - ay) or 1.0
        nx, ny = -(by - ay) / length, (bx - ax) / length
        s = i / (n - 1)
        half = width / 2 * (1 - taper + taper * math.sin(math.pi * s) ** 0.6)
        left.append((x + nx * half, y + ny * half))
        right.append((x - nx * half, y - ny * half))
    verts = left + right
    faces = [[i, i + 1, n + i + 1, n + i] for i in range(n - 1)]
    return _mesh("stroke", verts, faces, srgb, layer * 0.01)


def arc(cx, cy, length, bend, angle=0.0, points=9):
    """Centre line of a shallow arc `length` px long that bulges up by `bend` px (down if
    negative), tilted by `angle` degrees. Pass it to stroke()."""
    a = math.radians(angle)
    pts = []
    for i in range(points):
        s = i / (points - 1) * 2 - 1
        px, py = s * length / 2, -bend * (1 - s * s)
        pts.append((cx + px * math.cos(a) - py * math.sin(a), cy + px * math.sin(a) + py * math.cos(a)))
    return pts


# --------------------------------------------------------------------------- scene and output

def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = TILE_W, TILE_H
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.eevee.taa_render_samples = 32

    cam_data = bpy.data.cameras.new("camera")
    cam_data.type = "ORTHO"
    cam_data.sensor_fit = "VERTICAL"
    cam_data.ortho_scale = TILE_H / PPU
    cam_data.clip_start, cam_data.clip_end = 1, 30
    cam = bpy.data.objects.new("camera", cam_data)
    cam.location = (0, 0, 10)   # straight down, +Y up the image
    bpy.context.scene.collection.objects.link(cam)
    scene.camera = cam


def clear_shapes():
    for obj in list(bpy.data.objects):
        if obj.type == "MESH":
            bpy.data.objects.remove(obj)


def render_frame(path):
    """Renders the current shapes and returns the H x W x 4 array cut to the hex."""
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    px = sk.load_rgba(path)
    px[..., 3] = hex_mask()
    px[..., :3] *= px[..., 3:4]   # transparent pixels carry no stray colour
    return px


def base(srgb):
    """The tile's ground: the hex, a little oversize so the cut edge is solid colour."""
    cx, cy = TILE_W / 2, TILE_H / 2
    return polygon([(cx + (x - cx) * BLEED, cy + (y - cy) * BLEED) for x, y in HEX], srgb, 0)


def build(name, make_tile, variants, frames=1, out_dir=None):
    """Renders `variants` tiles of `name` with make_tile(variant, i, n) (which draws with base(),
    polygon() and stroke()) into out_dir (default assets/terrain).

    Command line (after --): --frames=N renders an N-frame strip per variant; --out=<dir> writes
    elsewhere, e.g. to compare a rebuild with the committed tiles.
    """
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = out_dir or os.path.join(sk.ROOT, "assets", "terrain")
    for a in args:
        if a.startswith("--frames="):
            frames = int(a.split("=", 1)[1])
        elif a.startswith("--out="):
            out = os.path.abspath(a.split("=", 1)[1])
    os.makedirs(out, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    _materials.clear()
    setup_scene()
    scratch = os.path.join(out, "_render.png")
    for v in range(variants):
        strip = np.zeros((TILE_H, TILE_W * frames, 4), dtype=np.float32)
        for i in range(frames):
            clear_shapes()
            make_tile(v, i, frames)
            strip[:, i * TILE_W:(i + 1) * TILE_W] = render_frame(scratch)
        png = os.path.join(out, "%s_%d.png" % (name, v))
        sk.write_png(png, strip)
        if frames > 1:
            with open(png[:-4] + ".json", "w") as f:
                f.write('{"frames": %d, "fps": %d}\n' % (frames, FPS))
    os.remove(scratch)
    print("Wrote %d %s tiles to %s" % (variants, name, out))
