"""Builds Cubelings creatures in Blender from a small spec, renders a view sheet and exports 3D models.

Run (Blender's Python, no window needed):
    python art/blender/cubelings.py Kitty "Ice Fox"   one or more creatures by name
    python art/blender/cubelings.py zone 3            the 4 creatures of a zone, plus renders/zone3_lineup.png
    python art/blender/cubelings.py legendary         the 10 Legendaries, plus renders/legendaries_lineup.png
    python art/blender/cubelings.py roblox            the file the game uses (see export_roblox)
    FAST=1 python art/blender/cubelings.py ...        only the 3/4 view (quick previews)

Outputs per creature (name / zone / legendary modes):
    art/renders/<Name>.png     4 views side by side: front / side / back / 3-4 (only 3-4 with FAST=1),
                               to compare with art/concepts/<Name>.png
    art/models/<Name>.glb      one mesh, colors come from a small palette texture (embedded)
    art/models/<Name>.fbx      same model as FBX (scratch output, not committed)
    art/models/<Name>_palette.png / _palette.json   the palette and which part role each cell is

The `roblox` mode writes art/models/Cubelings_Roblox.glb (all 50 creatures, split in parts) and
game/shared/Config/CreatureLooks.luau. That is what the game imports.

Units: the body is 2 x 2 x 1.9 (Blender units = studs once imported at scale 1). Front faces -Y.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def hex_color(value: str):
    value = value.lstrip("#")
    r, g, b = (int(value[i : i + 2], 16) / 255 for i in (0, 2, 4))
    # Blender works in linear color
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in (r, g, b))


# ---------------------------------------------------------------------------------------------------------------
# Species specs. Positions are relative to the body: x right, z up from the body center, front face at y = -1.

SPECIES = {
    # Zone 1 starter: a plain blue cube with a curl of hair, big eyes and a small smile
    "Cubby": {
        "colors": {
            "body": "#5BB8F5",
            "belly": "#D9F1FF",
            "legs": "#3C8ACB",
            "tuft": "#3C8ACB",
            "eye": "#16263A",
            "shine": "#FFFFFF",
            "mouth": "#16263A",
            "blush": "#FF9EB5",
        },
        "ears": "none",
        "tuft": True,
        "eyes": 1.12,
        "nose": None,
        "mouth": "smile",
        "tail": "none",
    },
    "Kitty": {
        "colors": {
            "body": "#F5A65B",
            "belly": "#FFE2C2",
            "ear_inner": "#FF9EB5",
            "legs": "#A0622D",
            "eye": "#2B1610",
            "shine": "#FFFFFF",
            "nose": "#FF9EB5",
            "mouth": "#5A2A14",
            "blush": "#FF9E9E",
        },
        "ears": "cat",
        "nose": "triangle",
        "mouth": "cat",
        "tail": "stub",
    },
    # Long ears, buck teeth, a pompom tail
    "Bunny": {
        "colors": {
            "body": "#F4F3F8",
            "belly": "#FFE6EE",
            "ear_inner": "#FFB3C6",
            "legs": "#DCDAE6",
            "eye": "#2A1E28",
            "shine": "#FFFFFF",
            "nose": "#FF8FAB",
            "mouth": "#6B4A55",
            "teeth": "#FFFFFF",
            "blush": "#FFB3C6",
            "tail": "#FFFFFF",
        },
        "ears": "bunny",
        "nose": "oval",
        "mouth": "cat",
        "teeth": True,
        "tail": "puff",
    },
    # Round ears and a muzzle with a big dark nose
    "Bear": {
        "colors": {
            "body": "#A8754F",
            "belly": "#E9C9A0",
            "ear_inner": "#E9C9A0",
            "legs": "#7A5236",
            "muzzle": "#E9C9A0",
            "eye": "#24150D",
            "shine": "#FFFFFF",
            "nose": "#3A2418",
            "mouth": "#3A2418",
            "blush": "#E8907A",
            "tail": "#A8754F",
        },
        "ears": "round",
        "eyes": 0.9,
        "muzzle": True,
        "nose": "bear",
        "mouth": "smile",
        "tail": "nub",
    },
}

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from species_zoo import LEGENDARIES, SPECIES as _MORE_SPECIES, ZONES  # noqa: E402

SPECIES.update(_MORE_SPECIES)

FAST = os.environ.get("FAST") == "1"  # only the 3/4 view (quick previews)

BODY_W, BODY_D, BODY_H = 2.0, 2.0, 1.9
BEVEL = 0.3
LEG_H = 0.24  # visible leg height under the body
BODY_Z = LEG_H + BODY_H / 2
FRONT_Y = -BODY_D / 2


# ---------------------------------------------------------------------------------------------------------------
# Helpers

materials = {}


def material(name: str, color, roughness=0.55, gloss=False):
    if name in materials:
        return materials[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = 0.15 if gloss else roughness
    if name.startswith("glow"):
        # Glowing parts (Neon in the game)
        bsdf.inputs["Emission Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Strength"].default_value = 2.2
    elif name == "jelly":
        # See-through jelly (Glass in the game)
        bsdf.inputs["Transmission Weight"].default_value = 0.85
        bsdf.inputs["Roughness"].default_value = 0.06
        bsdf.inputs["IOR"].default_value = 1.25
        bsdf.inputs["Coat Weight"].default_value = 0.6
    mat["palette_color"] = color
    mat["key"] = name
    materials[name] = mat
    return mat


def finish(obj, mat, smooth=True, angle=40):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if smooth:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
    obj.select_set(False)
    return obj


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def rounded_box(name, size, location, radius, segments=4, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel = obj.modifiers.new("Bevel", "BEVEL")
    bevel.width = radius
    bevel.segments = segments
    bevel.limit_method = "NONE"
    apply_modifiers(obj)
    return obj


def ellipsoid(name, radii, location, segments=16, rings=10, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = radii
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def tube(name, points, radius, radii=None):
    """A round tube along a list of 3D points (mouth lines, horns, tails...). `radii` tapers it: one
    scale per point, multiplied with `radius`."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    curve.use_fill_caps = True
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for i, (point, co) in enumerate(zip(spline.points, points)):
        point.co = (*co, 1)
        if radii:
            point.radius = radii[i]
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj.select_set(False)
    return bpy.context.view_layer.objects.active


def triangle_prism(name, half_width, height, depth, tip_shift=0.0):
    """A flat triangle (base on the bottom, tip up) given some thickness along y. Origin at the base."""
    import bmesh

    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    front, back = [], []
    for y, out in ((-depth / 2, front), (depth / 2, back)):
        out.append(bm.verts.new((-half_width, y, 0)))
        out.append(bm.verts.new((half_width, y, 0)))
        out.append(bm.verts.new((tip_shift, y, height)))
    bm.faces.new(front[::-1])
    bm.faces.new(back)
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def soft(obj, bevel_width, segments=3, subdiv=1):
    """Rounds every edge (bevel) and smooths the shape (subdivision)."""
    if bevel_width > 0:
        bevel = obj.modifiers.new("Bevel", "BEVEL")
        bevel.width = bevel_width
        bevel.segments = segments
        bevel.limit_method = "NONE"
    if subdiv:
        sub = obj.modifiers.new("Subdivision", "SUBSURF")
        sub.levels = subdiv
        sub.render_levels = subdiv
    apply_modifiers(obj)


def place(obj, location, lean, tilt=-6):
    """Moves a part to `location`, leaning sideways by `lean` (radians) and back by `tilt` degrees."""
    obj.location = location
    obj.rotation_euler = (math.radians(tilt), lean, 0)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def face_point(x, z, out=0.0):
    """A point on the front face. x and z are relative to the body center."""
    return (x, FRONT_Y - out, BODY_Z + z)


# ---------------------------------------------------------------------------------------------------------------
# Parts library: everything a species can add on top of the basic cube (ears, horns, wings, tails...).
# Each builder takes the build context `c` (c.spec, c.mat, c.parts, c.top) and appends finished parts.

DEFAULT_COLORS = {
    "horn": "#F3E6C8",
    "stripe": "#2B2433",
    "spot": "#FFFFFF",
    "wing": "#F4FBFF",
    "wing_spot": "#FFFFFF",
    "beak": "#F7A93B",
    "feet": "#F7A93B",
    "dark": "#2B2433",
    "white": "#FFFFFF",
    "gold": "#F5C542",
    "gem": "#E5534B",
    "gem2": "#5B9DF5",
    "leaf": "#6CCB5F",
    "flower": "#FF8FB1",
    "flower_center": "#FFD84D",
    "scarf": "#E5534B",
    "patch": "#FFFFFF",
    "glow": "#FFF27A",
    "pot": "#C8693E",
    "rock": "#8A847E",
    "screen": "#1A2230",
    "metal": "#7D8794",
    "crystal": "#BFF1FF",
    "cape": "#C9303E",
    "fur": "#FFFFFF",
    "fin": "#5E8CC0",
    "tongue": "#FF7A8A",
    "tail": "#FFFFFF",
    "tail_tip": "#FFFFFF",
}


class Mats(dict):
    """Materials by color key. Keys a species doesn't define fall back to DEFAULT_COLORS (or the body)."""

    def __init__(self, spec):
        super().__init__()
        self.spec = spec

    def __missing__(self, key):
        colors = self.spec["colors"]
        value = colors.get(key) or DEFAULT_COLORS.get(key) or colors["body"]
        made = material(key, hex_color(value), gloss=key in ("eye", "shine", "nose", "gem", "gem2", "crystal", "screen") or key.startswith("glow"))
        self[key] = made
        return made


def tag(parts, start, anim):
    """Marks the parts added since `start` as one moving piece for the game (legs, wings, tail, mouth)."""
    for obj in parts[start:]:
        obj["anim"] = anim


class Ctx:
    def __init__(self, spec, mat, parts):
        self.spec = spec
        self.mat = mat
        self.parts = parts
        self.top = BODY_Z + BODY_H / 2

    def add(self, obj, key, angle=40):
        self.parts.append(finish(obj, self.mat[key], angle=angle))
        return obj


def cone(name, r1, r2, depth, location, rotation=(0, 0, 0), verts=16):
    """A cone standing on its base at `location` (tip up before rotation)."""
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = name
    obj.data.transform(Matrix.Translation((0, 0, depth / 2)))
    obj.location = location
    obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def tapered(name, points, base, tip=0.15):
    """A tube that narrows from `base` radius to base*tip along the points (horns, tails, tentacles)."""
    n = len(points)
    return tube(name, points, base, radii=[1 - (1 - tip) * i / (n - 1) for i in range(n)])


def curve_points(a, b, c, count=12):
    """Quadratic curve from a through control b to c."""
    out = []
    for i in range(count):
        t = i / (count - 1)
        out.append(tuple((1 - t) ** 2 * a[k] + 2 * (1 - t) * t * b[k] + t * t * c[k] for k in range(3)))
    return out


def shell_of_body(name, inflate, cutter):
    """A copy of the body a little bigger, cut by `cutter` (bands, patches and caps that hug the body)."""
    obj = rounded_box(name, (BODY_W + inflate, BODY_D + inflate, BODY_H + inflate), (0, 0, BODY_Z), BEVEL + inflate / 2, segments=5)
    boolean = obj.modifiers.new("Cut", "BOOLEAN")
    boolean.operation = "INTERSECT"
    boolean.object = cutter
    apply_modifiers(obj)
    bpy.data.objects.remove(cutter)
    return obj


def slab(z0, z1, front_cut=None):
    """A box between two heights (in body space), optionally stopping before the front face."""
    y0 = -2.0 if front_cut is None else front_cut
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, (y0 + 2.0) / 2, BODY_Z + (z0 + z1) / 2))
    obj = bpy.context.active_object
    obj.scale = (4, 2.0 - y0, z1 - z0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def sym(fn):
    for side in (-1, 1):
        fn(side)


# ----- Head pieces ------------------------------------------------------------------------------------------------

def ears_antenna(c):
    def one(side):
        pts = curve_points((0.35 * side, -0.25, c.top - 0.05), (0.4 * side, -0.35, c.top + 0.45), (0.62 * side, -0.5, c.top + 0.7), 10)
        c.add(tube("Antenna", pts, 0.045), "dark")
        c.add(ellipsoid("AntennaTip", (0.13, 0.13, 0.13), pts[-1], segments=16, rings=10), "antenna_tip")
    sym(one)


def ears_unihorn(c):
    base = (0, -0.45, c.top - 0.08)
    pts = curve_points(base, (0, -0.55, c.top + 0.45), (0, -0.62, c.top + 0.95), 12)
    c.add(tapered("Horn", pts, 0.2, 0.08), "horn")
    # A spiral line wrapped around the horn
    spiral = []
    for i in range(40):
        t = i / 39
        p = pts[min(len(pts) - 1, int(t * (len(pts) - 1)))]
        r = 0.2 * (1 - 0.92 * t) + 0.012
        a = t * math.pi * 7
        spiral.append((p[0] + math.cos(a) * r, p[1] + math.sin(a) * r, p[2]))
    c.add(tube("HornSpiral", spiral, 0.02), "horn_line")
    # Mane: soft puffs along the top and back
    for i, (x, y, z, r) in enumerate([(0, -0.1, 0.06, 0.32), (0.05, 0.35, 0.02, 0.3), (-0.05, 0.75, -0.08, 0.28), (0, 1.0, -0.4, 0.26), (0.02, 1.05, -0.75, 0.22)]):
        c.add(ellipsoid("Mane", (r, r, r * 0.85), (x, y, c.top + z), segments=16, rings=10), "mane" if i % 2 == 0 else "mane2")


def ears_horns(c):
    def one(side):
        pts = curve_points((0.55 * side, -0.25, c.top - 0.08), (1.0 * side, -0.3, c.top + 0.25), (0.82 * side, -0.4, c.top + 0.72), 12)
        c.add(tapered("Horn", pts, 0.17, 0.1), "horn")
    sym(one)


def ears_antlers(c):
    def one(side):
        main = curve_points((0.45 * side, -0.05, c.top - 0.05), (0.6 * side, -0.05, c.top + 0.5), (0.95 * side, 0.0, c.top + 0.85), 10)
        c.add(tapered("Antler", main, 0.085, 0.5), "horn")
        branch = curve_points(main[4], (0.45 * side, -0.1, c.top + 0.65), (0.42 * side, -0.12, c.top + 0.9), 8)
        c.add(tapered("Antler", branch, 0.065, 0.5), "horn")
        branch2 = curve_points(main[7], (0.95 * side, 0.05, c.top + 0.62), (1.15 * side, 0.05, c.top + 0.62), 6)
        c.add(tapered("Antler", branch2, 0.06, 0.5), "horn")
        # Little round ears under the antlers
        c.add(ellipsoid("Ear", (0.26, 0.12, 0.17), (0.9 * side, -0.2, c.top - 0.08), segments=16, rings=8), "body")
        c.add(ellipsoid("EarInner", (0.16, 0.05, 0.1), (0.9 * side, -0.31, c.top - 0.08), segments=12, rings=6), "ear_inner")
    sym(one)


def ears_leaf(c):
    stem = curve_points((0, -0.1, c.top - 0.05), (0.0, -0.1, c.top + 0.3), (0.05, -0.1, c.top + 0.45), 6)
    c.add(tube("Stem", stem, 0.05), "stem")
    for side, angle in ((-1, 35), (1, -35)):
        leaf = ellipsoid("Leaf", (0.38, 0.07, 0.17), (0, 0, 0), segments=18, rings=8)
        leaf.data.transform(Matrix.Translation((0.36, 0, 0)))
        leaf.location = (0.05, -0.1, c.top + 0.42)
        leaf.rotation_euler = (0, math.radians(angle if side > 0 else 180 + angle), math.radians(15 * side))
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        c.add(leaf, "leaf")


def ears_cap(c):
    # Mushroom cap: a wide dome over the top, cut flat underneath, with white spots
    dome = ellipsoid("Cap", (1.45, 1.45, 0.95), (0, 0, c.top - 0.2), segments=40, rings=20)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, c.top - 0.2 + 1.5))
    cutter = bpy.context.active_object
    cutter.scale = (4, 4, 3)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    boolean = dome.modifiers.new("Cut", "BOOLEAN")
    boolean.operation = "INTERSECT"
    boolean.object = cutter
    apply_modifiers(dome)
    bpy.data.objects.remove(cutter)
    c.add(dome, "cap")
    for theta, phi, r in [(0, 30, 0.26), (70, 55, 0.2), (145, 35, 0.24), (215, 55, 0.2), (290, 35, 0.23), (0, 80, 0.2), (180, 75, 0.17), (110, 12, 0.16), (250, 12, 0.16), (330, 65, 0.15)]:
        t, p = math.radians(theta), math.radians(phi)
        nx, ny, nz = math.cos(p) * math.sin(t), -math.cos(p) * math.cos(t), math.sin(p)
        pos = Vector((1.45 * nx, 1.45 * ny, c.top - 0.2 + 0.95 * nz))
        spot = ellipsoid("Spot", (r, r, 0.04), (0, 0, 0), segments=14, rings=6)
        normal = Vector((nx / 1.45, ny / 1.45, nz / 0.95)).normalized()
        spot.rotation_euler = normal.to_track_quat("Z", "Y").to_euler()
        spot.location = pos
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        c.add(spot, "spot")


def ears_hat(c):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.8, depth=0.08, location=(0.05, 0, c.top + 0.04))
    c.add(bpy.context.active_object, "dark")
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.52, depth=0.8, location=(0.05, 0, c.top + 0.48))
    hat = bpy.context.active_object
    soft(hat, 0.04, segments=2, subdiv=0)
    c.add(hat, "dark")
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.535, depth=0.16, location=(0.05, 0, c.top + 0.2))
    c.add(bpy.context.active_object, "scarf")


def ears_crown(c):
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.62, depth=0.3, location=(0, 0, c.top + 0.12))
    band = bpy.context.active_object
    soft(band, 0.03, segments=2, subdiv=0)
    c.add(band, "gold")
    for i in range(5):
        a = math.radians(90 + i * 72)
        x, y = math.cos(a) * 0.56, -math.sin(a) * 0.56
        c.add(cone("CrownPoint", 0.17, 0.02, 0.38, (x, y, c.top + 0.25), verts=12), "gold")
        c.add(ellipsoid("CrownBall", (0.07, 0.07, 0.07), (x * 1.0, y * 1.0, c.top + 0.65), segments=10, rings=6), "gold")
    c.add(ellipsoid("Gem", (0.12, 0.06, 0.12), (0, -0.62, c.top + 0.13), segments=12, rings=8), "gem")
    sym(lambda s: c.add(ellipsoid("Gem", (0.08, 0.05, 0.08), (0.44 * s, -0.44, c.top + 0.13), segments=10, rings=6), "gem2"))


def ears_flame(c):
    for i, (x, y, h, lean) in enumerate([(0, -0.3, 1.0, -20), (-0.3, 0.0, 0.8, -35), (0.3, 0.0, 0.8, -35), (0, 0.3, 0.65, -55)]):
        pts = curve_points((x, y, c.top - 0.05), (x, y - 0.05, c.top + h * 0.6), (x * 1.3, y + math.sin(math.radians(-lean)) * 0.5, c.top + h), 10)
        c.add(tapered("Flame", pts, 0.2, 0.05), "flame" if i % 2 == 0 else "flame2")


def ears_tufts(c):
    def one(side):
        ear = triangle_prism("Tuft", half_width=0.22, height=0.55, depth=0.2, tip_shift=0.12 * side)
        soft(ear, 0.07, segments=2, subdiv=1)
        place(ear, Vector((0.68 * side, -0.25, c.top - 0.15)), math.radians(-22 * side))
        c.add(ear, "tuft" if "tuft" in c.spec["colors"] else "body", angle=180)
    sym(one)


def ears_bat(c):
    # Big pointed ears
    def one(side):
        ear = triangle_prism("Ear", half_width=0.42, height=1.0, depth=0.3, tip_shift=0.18 * side)
        soft(ear, 0.1, segments=3, subdiv=1)
        place(ear, Vector((0.58 * side, -0.25, c.top - 0.22)), math.radians(-20 * side))
        c.add(ear, "body", angle=180)
        inner = triangle_prism("EarInner", half_width=0.22, height=0.58, depth=0.06, tip_shift=0.12 * side)
        soft(inner, 0.03, segments=2, subdiv=1)
        place(inner, Vector((0.58 * side, -0.25, c.top - 0.22)) + Vector((0.07 * side, -0.15, 0.2)), math.radians(-20 * side))
        c.add(inner, "ear_inner", angle=180)
    sym(one)


EARS = {
    "antenna": ears_antenna,
    "unihorn": ears_unihorn,
    "horns": ears_horns,
    "antlers": ears_antlers,
    "leaf": ears_leaf,
    "cap": ears_cap,
    "hat": ears_hat,
    "crown": ears_crown,
    "flame": ears_flame,
    "tufts": ears_tufts,
    "bat": ears_bat,
}


# ----- Body features ----------------------------------------------------------------------------------------------

def feat_stripes(c):
    # Dark bands around the back two thirds of the body (the face stays clean)
    for z0, z1 in c.spec.get("stripes", [(-0.75, -0.48), (-0.25, 0.0), (0.3, 0.55)]):
        c.add(shell_of_body("Stripe", 0.025, slab(z0, z1, front_cut=-0.55)), "stripe")


def feat_spots(c):
    # Round spots on the top, the back and the sides
    spots = c.spec.get("spot_list") or [
        (0, 0.0, 1.0, 0.0, 0.0, 0.28), (0.45, 0.45, 1.0, 0, 0, 0.2), (-0.5, 0.35, 1.0, 0, 0, 0.18),
        (1.0, 0.1, 0.2, 1, 0, 0.22), (-1.0, -0.2, -0.1, 1, 0, 0.2), (1.0, 0.45, -0.45, 1, 0, 0.15), (-1.0, 0.5, 0.4, 1, 0, 0.16),
        (0.3, 1.0, 0.1, 2, 0, 0.24), (-0.4, 1.0, -0.4, 2, 0, 0.18),
    ]
    for x, y, z, face, _, r in spots:
        if face == 0:  # top
            loc, rot = (x, y, c.top + 0.012), (0, 0, 0)
        elif face == 1:  # side
            loc, rot = (math.copysign(BODY_W / 2 + 0.012, x), y, BODY_Z + z), (0, math.radians(90), 0)
        else:  # back
            loc, rot = (x, BODY_D / 2 + 0.012, BODY_Z + z), (math.radians(90), 0, 0)
        c.add(ellipsoid("Spot", (r, r, 0.03), loc, segments=16, rings=6, rotation=rot), "spot")


def feat_wings_bee(c):
    # Two pairs of see-through-looking wings standing up from the back, leaning out and back
    def one(side):
        for lean, back, size in ((28, 22, 1.0), (55, 38, 0.72)):
            wing = ellipsoid("Wing", (0.28 * size, 0.035, 0.5 * size), (0, 0, 0), segments=18, rings=8)
            wing.data.transform(Matrix.Translation((0, 0, 0.45 * size)))
            wing.location = (0.28 * side, 0.45, c.top - 0.05)
            wing.rotation_euler = (math.radians(back), math.radians(lean * side), 0)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            c.add(wing, "wing")
    sym(one)


def feat_wings_butterfly(c):
    # Big wings behind the body, spreading out to both sides (upper pair up, lower pair down)
    def one(side):
        for w, h, z, lean in ((0.9, 0.62, 0.35, 28), (0.62, 0.45, -0.3, -24)):
            for key, scale, dy, shift in (("wing", 1.0, 0.0, 0.85), ("wing_spot", 0.38, -0.05, 1.05)):
                wing = ellipsoid("Wing", (w * scale, 0.05, h * scale), (0, 0, 0), segments=24, rings=10)
                wing.data.transform(Matrix.Translation((w * shift * side, dy, 0)))
                wing.location = (0.3 * side, 1.08, BODY_Z + z)
                wing.rotation_euler = (0, -math.radians(lean) * side, 0)
                bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
                c.add(wing, key)
    sym(one)


def extruded(name, outline, depth, y=0.0):
    """A flat shape from a 2D outline [(x, z), ...] given some thickness along y."""
    import bmesh

    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    front = [bm.verts.new((x, y - depth / 2, z)) for x, z in outline]
    back = [bm.verts.new((x, y + depth / 2, z)) for x, z in outline]
    bm.faces.new(front[::-1])
    bm.faces.new(back)
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


# A bat wing seen from behind: top edge going up and out, scalloped bottom edge
BAT_WING = [(0, 0.3), (0.55, 0.62), (1.2, 0.78), (1.12, 0.22), (0.9, 0.36), (0.72, 0.0), (0.48, 0.2), (0.24, -0.1), (0, 0.0)]


def membrane_wing(c, side, scale, key, bone_key, height):
    outline = [(x * scale * side, z * scale) for x, z in BAT_WING]
    if side < 0:
        outline = outline[::-1]
    wing = extruded("Wing", outline, 0.07)
    soft(wing, 0.025, segments=2, subdiv=0)
    wing.location = (0.62 * side, 0.85, BODY_Z + height)
    wing.rotation_euler = (0, 0, math.radians(-22 * side))
    bpy.context.view_layer.objects.active = wing
    wing.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True)
    wing.select_set(False)
    c.add(wing, key, angle=30)
    # The arm bone along the top edge
    a = math.radians(-22 * side)
    def world(x, z):
        return (0.62 * side + x * scale * side * math.cos(a), 0.85 + x * scale * side * math.sin(a), BODY_Z + height + z * scale)
    c.add(tube("Bone", [world(0, 0.3), world(0.55, 0.62), world(1.2, 0.78)], 0.045 * scale), bone_key)


def feat_wings_bat(c):
    sym(lambda s_: membrane_wing(c, s_, 1.0, "wing", "dark", 0.2))


def feat_wings_bird(c):
    def one(side):
        wing = ellipsoid("Wing", (0.12, 0.62, 0.55), (0, 0, 0), segments=20, rings=12)
        wing.data.transform(Matrix.Translation((0, 0.15, -0.25)))
        wing.location = (1.02 * side, 0.05, BODY_Z + 0.25)
        wing.rotation_euler = (math.radians(-20), math.radians(-12 * side), 0)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        c.add(wing, "wing")
        for i in range(3):
            tip = ellipsoid("Feather", (0.08, 0.16, 0.3), (1.06 * side, 0.45 + i * 0.16, BODY_Z - 0.38 - i * 0.04), segments=12, rings=8, rotation=(math.radians(-35), 0, 0))
            c.add(tip, "wing_tip" if "wing_tip" in c.spec["colors"] else "wing")
    sym(one)


def feat_wings_dragon(c):
    sym(lambda s_: membrane_wing(c, s_, 1.45, "wing", "spike", 0.35))


def feat_claws(c):
    def one(side):
        arm = curve_points((0.85 * side, -0.55, BODY_Z - 0.3), (1.35 * side, -0.85, BODY_Z - 0.25), (1.35 * side, -1.15, BODY_Z - 0.05), 8)
        c.add(tapered("Arm", arm, 0.13, 0.75), "claw")
        tip = Vector(arm[-1])
        upper = ellipsoid("Pincer", (0.2, 0.36, 0.14), tip + Vector((0, -0.2, 0.12)), segments=18, rings=10, rotation=(math.radians(-20), 0, 0))
        lower = ellipsoid("Pincer", (0.17, 0.3, 0.11), tip + Vector((0, -0.18, -0.1)), segments=18, rings=10, rotation=(math.radians(25), 0, 0))
        c.add(upper, "claw")
        c.add(lower, "claw")
    sym(one)


def feat_shell(c):
    dome = ellipsoid("Shell", (1.18, 1.18, 0.7), (0, 0.05, c.top - 0.15), segments=36, rings=18)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, c.top - 0.15 + 1.5))
    cutter = bpy.context.active_object
    cutter.scale = (4, 4, 3)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    boolean = dome.modifiers.new("Cut", "BOOLEAN")
    boolean.operation = "INTERSECT"
    boolean.object = cutter
    apply_modifiers(dome)
    bpy.data.objects.remove(cutter)
    c.add(dome, "shell")
    for x, y, r in [(0, 0.05, 0.3), (0.55, 0.0, 0.22), (-0.55, 0.0, 0.22), (0, 0.6, 0.22), (0, -0.5, 0.22), (0.45, 0.55, 0.17), (-0.45, 0.55, 0.17), (0.45, -0.45, 0.17), (-0.45, -0.45, 0.17)]:
        k = 1 - (x / 1.18) ** 2 - ((y - 0.05) / 1.18) ** 2
        z = c.top - 0.15 + 0.7 * math.sqrt(max(k, 0))
        plate = ellipsoid("Plate", (r, r, 0.05), (x, y, z - 0.01), segments=6, rings=4)
        normal = Vector((x / 1.18 ** 2, (y - 0.05) / 1.18 ** 2, (z - (c.top - 0.15)) / 0.7 ** 2)).normalized()
        plate.rotation_euler = normal.to_track_quat("Z", "Y").to_euler()
        c.add(plate, "plate")
    # Rim
    bpy.ops.mesh.primitive_torus_add(major_radius=1.12, minor_radius=0.08, location=(0, 0.05, c.top - 0.13))
    rim = bpy.context.active_object
    rim.scale = (1.0, 1.0, 1.0)
    c.add(rim, "plate")


def feat_dorsal_fin(c):
    fin = triangle_prism("Fin", half_width=0.4, height=0.7, depth=0.14, tip_shift=0.32)
    soft(fin, 0.06, segments=2, subdiv=1)
    fin.rotation_euler = (0, 0, math.radians(90))
    fin.location = (0, 0.15, c.top - 0.12)
    bpy.context.view_layer.objects.active = fin
    fin.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True)
    fin.select_set(False)
    c.add(fin, "fin", angle=180)


def feat_flippers(c):
    def one(side):
        flip = ellipsoid("Flipper", (0.1, 0.32, 0.42), (0, 0, 0), segments=18, rings=10)
        flip.data.transform(Matrix.Translation((0, 0, -0.32)))
        flip.location = (1.03 * side, -0.15, BODY_Z - 0.05)
        flip.rotation_euler = (math.radians(15), math.radians(-28 * side), 0)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        c.add(flip, "fin")
    sym(one)


def feat_whiskers(c):
    def one(side):
        for i, dz in enumerate((0.05, -0.05, -0.15)):
            a = face_point(0.55 * side, -0.12 + dz * 0.3, 0.02)
            b = face_point(1.05 * side, -0.05 + dz * 1.3, 0.12)
            c.add(tube("Whisker", [a, b], 0.014), "dark")
    sym(one)


def feat_tusk(c):
    pts = curve_points(face_point(0, 0.55, 0.0), face_point(0, 0.95, 0.35), face_point(0, 1.35, 0.6), 12)
    c.add(tapered("Tusk", pts, 0.13, 0.08), "horn")
    spiral = []
    for i in range(36):
        t = i / 35
        p = Vector(pts[min(len(pts) - 1, int(t * (len(pts) - 1)))])
        r = 0.13 * (1 - 0.9 * t) + 0.01
        a = t * math.pi * 8
        spiral.append((p.x + math.cos(a) * r, p.y + math.sin(a) * r * 0.6, p.z + math.sin(a) * r * 0.6))
    c.add(tube("TuskLine", spiral, 0.015), "horn_line")


def feat_scarf(c):
    c.add(shell_of_body("Scarf", 0.07, slab(-0.3, -0.05)), "scarf")
    end = rounded_box("ScarfEnd", (0.28, 0.08, 0.6), (0.55, FRONT_Y - 0.07, BODY_Z - 0.45), 0.05, segments=2, rotation=(0, math.radians(-10), 0))
    c.add(end, "scarf")
    for i in range(3):
        c.add(ellipsoid("Fringe", (0.04, 0.04, 0.08), (0.48 + i * 0.07, FRONT_Y - 0.07, BODY_Z - 0.8), segments=8, rings=6), "scarf")


def feat_buttons(c):
    for z in (-0.35, -0.6):
        c.add(ellipsoid("Button", (0.07, 0.04, 0.07), face_point(0, z, 0.0), segments=12, rings=8), "dark")


def feat_spines(c):
    import random

    rng = random.Random(7)
    for _ in range(26):
        face = rng.choice(["top", "side", "side", "back", "front"])
        if face == "top":
            loc, rot = (rng.uniform(-0.75, 0.75), rng.uniform(-0.5, 0.75), c.top), (0, 0, 0)
        elif face == "side":
            side = rng.choice([-1, 1])
            loc, rot = (side * BODY_W / 2, rng.uniform(-0.7, 0.7), BODY_Z + rng.uniform(-0.6, 0.7)), (0, math.radians(90 * side), 0)
        elif face == "back":
            loc, rot = (rng.uniform(-0.7, 0.7), BODY_D / 2, BODY_Z + rng.uniform(-0.6, 0.7)), (math.radians(-90), 0, 0)
        else:
            x = rng.choice([-0.85, 0.85])
            loc, rot = (x, FRONT_Y, BODY_Z + rng.uniform(-0.6, 0.75)), (math.radians(90), 0, 0)
        c.add(cone("Spine", 0.035, 0.0, 0.16, loc, rotation=rot, verts=6), "spine")


def feat_flower(c):
    center = Vector((0.3, -0.15, c.top + 0.08))
    for i in range(6):
        a = math.radians(i * 60)
        petal = ellipsoid("Petal", (0.27, 0.16, 0.07), center + Vector((math.cos(a) * 0.26, math.sin(a) * 0.26, 0.03)), segments=14, rings=6, rotation=(math.radians(-12), 0, a))
        c.add(petal, "flower")
    c.add(ellipsoid("FlowerCenter", (0.15, 0.15, 0.1), center + Vector((0, 0, 0.09)), segments=14, rings=8), "flower_center")


def feat_nemes(c):
    # Sphinx headdress: striped cloth on top falling down both sides, and a gold collar
    c.add(shell_of_body("Nemes", 0.06, slab(0.55, 1.1)), "cloth")
    for i, (z0, z1) in enumerate([(0.62, 0.72), (0.82, 0.92)]):
        c.add(shell_of_body("NemesStripe", 0.075, slab(z0, z1)), "cloth2")
    def one(side):
        for i in range(4):
            key = "cloth" if i % 2 == 0 else "cloth2"
            flap = rounded_box("Flap", (0.12, 0.6, 0.22), (side * (BODY_W / 2 + 0.06), -0.2, BODY_Z + 0.45 - i * 0.22), 0.04, segments=2)
            c.add(flap, key)
    sym(one)
    c.add(shell_of_body("Collar", 0.05, slab(-0.62, -0.5)), "gold")


def feat_rocks(c):
    import random

    rng = random.Random(3)
    for x, y, z, s in [(-0.6, 0.1, 1.0, 0.4), (0.55, 0.4, 1.0, 0.34), (0.1, 0.7, 1.0, 0.28), (1.0, 0.3, 0.55, 0.32), (-1.0, -0.2, 0.3, 0.3), (0.3, 1.0, 0.2, 0.36), (-0.5, 1.0, -0.4, 0.28)]:
        loc = (x, y, BODY_Z + z * BODY_H / 2 if z < 1 else c.top)
        rock = rounded_box("Rock", (s, s * 0.9, s * 0.8), loc, 0.06, segments=2, rotation=(rng.uniform(0, 1), rng.uniform(0, 1), rng.uniform(0, 1)))
        c.add(rock, "rock")
    # Glowing cracks on the front
    for pts in ([(-0.85, 0.65), (-0.6, 0.45), (-0.65, 0.25)], [(0.8, -0.55), (0.6, -0.4), (0.68, -0.2)]):
        c.add(tube("Crack", [face_point(x, z, 0.005) for x, z in pts], 0.03), "glow")


def feat_screen(c):
    panel = rounded_box("Screen", (1.45, 0.06, 0.95), face_point(0, 0.0, -0.018), 0.12, segments=3)
    c.add(panel, "screen")


def feat_bolts(c):
    def one(side):
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.17, depth=0.16, location=(side * (BODY_W / 2 + 0.05), 0, BODY_Z + 0.05), rotation=(0, math.radians(90), 0))
        c.add(bpy.context.active_object, "metal")
    sym(one)


def feat_voxels(c):
    for x, y, z, s, key in [(0.75, -0.6, 1.0, 0.3, "accent"), (-0.6, 0.6, 1.0, 0.26, "accent2"), (1.0, 0.5, 0.4, 0.28, "accent"), (-1.0, -0.3, -0.35, 0.24, "accent2"),
                            (0.5, 1.0, 0.5, 0.26, "accent2"), (-0.85, -1.0, 0.75, 0.2, "accent"), (0.45, 0.2, 1.42, 0.18, "accent"), (-0.1, -0.2, 1.65, 0.14, "accent2")]:
        loc = (x * (BODY_W / 2), y * (BODY_D / 2), BODY_Z + z * BODY_H / 2)
        c.add(rounded_box("Voxel", (s, s, s), loc, 0.025, segments=1), key)


def feat_cursor(c):
    # A mouse-pointer arrow floating above the head (white with a dark outline)
    import bmesh

    outline = [(0, 0), (0, -1.0), (0.24, -0.78), (0.42, -1.12), (0.56, -1.05), (0.39, -0.71), (0.7, -0.68)]

    def arrow(name, scale, depth, y, key):
        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        front = [bm.verts.new((x * scale, y - depth / 2, z * scale)) for x, z in outline]
        back = [bm.verts.new((x * scale, y + depth / 2, z * scale)) for x, z in outline]
        bm.faces.new(front[::-1])
        bm.faces.new(back)
        for i in range(len(outline)):
            j = (i + 1) % len(outline)
            bm.faces.new((front[i], front[j], back[j], back[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.location = (-0.32 * scale / 0.8, 0, c.top + 1.25)
        obj.rotation_euler = (0, math.radians(-15), 0)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True)
        obj.select_set(False)
        soft(obj, 0.015, segments=1, subdiv=0)
        c.add(obj, key, angle=30)

    arrow("Cursor", 0.8, 0.12, 0.0, "white")
    arrow("CursorOutline", 0.88, 0.08, 0.05, "dark")


def feat_cape(c):
    cape = rounded_box("Cape", (2.1, 0.08, 1.75), (0, BODY_D / 2 + 0.08, BODY_Z - 0.05), 0.04, segments=2)
    c.add(cape, "cape")
    for i in range(9):
        x = -0.95 + i * 0.2375
        c.add(ellipsoid("Fur", (0.13, 0.13, 0.13), (x, -0.55 + abs(x) * 0.3 if abs(x) < 0.0 else 0.95, c.top - 0.02), segments=12, rings=8), "white")
    sym(lambda s: [c.add(ellipsoid("Fur", (0.13, 0.13, 0.13), (s * 1.0, y, c.top - 0.02), segments=12, rings=8), "white") for y in (0.55, 0.15, -0.25)])


def feat_fur(c):
    for x, y, h in [(-0.45, -0.3, 0.45), (0.0, -0.4, 0.55), (0.45, -0.3, 0.45), (-0.25, 0.2, 0.4), (0.25, 0.2, 0.4)]:
        c.add(cone("Fur", 0.22, 0.02, h, (x, y, c.top - 0.06), rotation=(math.radians(-15), math.radians(-x * 30), 0), verts=10), "fur")
    sym(lambda s: [c.add(cone("Fur", 0.16, 0.02, 0.3, (s * 1.0, y, BODY_Z + z), rotation=(0, math.radians(70 * s), 0), verts=8), "fur") for y, z in ((-0.3, 0.3), (0.3, -0.1), (0.0, -0.5))])


def feat_face_patch(c):
    patch = ellipsoid("Patch", (0.92, 0.04, 0.62), face_point(0, -0.05, -0.02), segments=28, rings=10)
    c.add(patch, "patch")


def feat_eye_rings(c):
    sym(lambda s: c.add(ellipsoid("EyeRing", (0.36, 0.04, 0.36), face_point(0.47 * s, 0.1, -0.015), segments=24, rings=8), "patch"))


def feat_glow_dots(c):
    for side in (-1, 1):
        for y, z in ((-0.45, 0.2), (0.1, -0.3), (0.55, 0.35)):
            c.add(ellipsoid("Glow", (0.03, 0.15, 0.15), (side * (BODY_W / 2 + 0.01), y, BODY_Z + z), segments=12, rings=8), "glow")


def feat_crystals(c):
    for x, y, h, lean in c.spec.get("crystal_list", [(0.0, -0.35, 0.55, 0), (-0.35, 0.0, 0.4, -18), (0.35, 0.05, 0.42, 18), (0.0, 0.45, 0.35, 0)]):
        c.add(cone("Crystal", 0.16, 0.0, h, (x, y, c.top - 0.08), rotation=(0, math.radians(lean), 0), verts=5), "crystal")


def feat_back_spikes(c):
    for i, (y, z, h) in enumerate([(-0.45, 0, 0.35), (0.05, 0, 0.42), (0.55, 0, 0.36), (BODY_D / 2, -0.3, 0.3), (BODY_D / 2, -0.75, 0.25)]):
        if z == 0:
            c.add(cone("Spike", 0.16, 0.02, h, (0, y, c.top - 0.05), verts=8), "spike")
        else:
            c.add(cone("Spike", 0.14, 0.02, h, (0, y - 0.03, BODY_Z + z + BODY_H / 2 - 0.2), rotation=(math.radians(-90), 0, 0), verts=8), "spike")


def feat_hump(c):
    for y, r in c.spec.get("humps", [(-0.15, 0.55), (0.55, 0.45)]):
        c.add(ellipsoid("Hump", (r, r, r * 0.8), (0, y, c.top - 0.12), segments=24, rings=12), "body")


FEATURES = {
    "stripes": feat_stripes,
    "spots": feat_spots,
    "wings_bee": feat_wings_bee,
    "wings_butterfly": feat_wings_butterfly,
    "wings_bat": feat_wings_bat,
    "wings_bird": feat_wings_bird,
    "wings_dragon": feat_wings_dragon,
    "claws": feat_claws,
    "shell": feat_shell,
    "dorsal_fin": feat_dorsal_fin,
    "flippers": feat_flippers,
    "whiskers": feat_whiskers,
    "tusk": feat_tusk,
    "scarf": feat_scarf,
    "buttons": feat_buttons,
    "spines": feat_spines,
    "flower": feat_flower,
    "nemes": feat_nemes,
    "rocks": feat_rocks,
    "screen": feat_screen,
    "bolts": feat_bolts,
    "voxels": feat_voxels,
    "cursor": feat_cursor,
    "cape": feat_cape,
    "fur": feat_fur,
    "face_patch": feat_face_patch,
    "eye_rings": feat_eye_rings,
    "glow_dots": feat_glow_dots,
    "crystals": feat_crystals,
    "back_spikes": feat_back_spikes,
    "hump": feat_hump,
}


# ----- Tails --------------------------------------------------------------------------------------------------

def tail_fox(c):
    pts = curve_points((0, BODY_D / 2 - 0.05, BODY_Z - 0.45), (0, BODY_D / 2 + 0.75, BODY_Z - 0.3), (0.15, BODY_D / 2 + 0.75, BODY_Z + 0.55), 12)
    n = len(pts)
    radii = [0.55 + 0.45 * math.sin(math.pi * (i / (n - 1)) * 0.85) for i in range(n)]
    c.add(tube("Tail", pts[:9], 0.32, radii=radii[:9]), "body")
    tip = tube("TailTip", pts[8:], 0.32, radii=[radii[8 + i] * (1 - 0.7 * i / (n - 9)) for i in range(n - 8)])
    c.add(tip, "tail_tip")


def tail_stinger(c):
    # A segmented tail that curls up over the back with the stinger pointing forward
    pts = curve_points((0, BODY_D / 2 - 0.15, BODY_Z - 0.35), (0, BODY_D / 2 + 1.25, BODY_Z + 0.5), (0, BODY_D / 2 - 0.35, c.top + 0.85), 14)
    c.add(tapered("Tail", pts, 0.2, 0.55), "body")
    for i in range(1, len(pts) - 1, 2):
        r = 0.2 * (1 - 0.45 * i / (len(pts) - 1)) * 1.18
        c.add(ellipsoid("Segment", (r, r, r), pts[i], segments=16, rings=10), "segment")
    end = Vector(pts[-1])
    bulb = ellipsoid("Bulb", (0.16, 0.2, 0.16), tuple(end + Vector((0, -0.05, 0.0))), segments=16, rings=10)
    c.add(bulb, "segment")
    c.add(cone("Stinger", 0.09, 0.0, 0.32, tuple(end + Vector((0, -0.18, -0.02))), rotation=(math.radians(105), 0, 0), verts=12), "stinger")


def tail_devil(c):
    pts = curve_points((0, BODY_D / 2 - 0.05, BODY_Z - 0.5), (0, BODY_D / 2 + 1.0, BODY_Z - 0.6), (0.2, BODY_D / 2 + 0.85, BODY_Z + 0.35), 12)
    c.add(tube("Tail", pts, 0.06), "body")
    spade = triangle_prism("Spade", half_width=0.2, height=0.35, depth=0.06)
    soft(spade, 0.03, segments=2, subdiv=1)
    spade.location = pts[-1]
    spade.rotation_euler = (math.radians(-20), 0, 0)
    bpy.context.view_layer.objects.active = spade
    spade.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True)
    spade.select_set(False)
    c.add(spade, "body", angle=180)


def tail_lizard(c):
    pts = curve_points((0, BODY_D / 2 - 0.1, BODY_Z - 0.5), (0, BODY_D / 2 + 0.9, BODY_Z - 0.75), (0.75, BODY_D / 2 + 1.0, BODY_Z - 0.55), 14)
    c.add(tapered("Tail", pts, 0.28, 0.1), "body")


def tail_dragon(c):
    pts = curve_points((0, BODY_D / 2 - 0.1, BODY_Z - 0.45), (0, BODY_D / 2 + 1.0, BODY_Z - 0.75), (0.7, BODY_D / 2 + 1.1, BODY_Z - 0.3), 14)
    c.add(tapered("Tail", pts, 0.3, 0.1), "body")
    for i in (3, 6, 9):
        p = Vector(pts[i])
        c.add(cone("TailSpike", 0.1, 0.0, 0.25, tuple(p + Vector((0, 0, 0.22 - i * 0.012))), verts=6), "spike")
    tip = triangle_prism("TailTip", half_width=0.2, height=0.32, depth=0.06)
    soft(tip, 0.03, segments=2, subdiv=1)
    tip.location = pts[-1]
    tip.rotation_euler = (0, math.radians(-90), math.radians(30))
    bpy.context.view_layer.objects.active = tip
    tip.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True)
    tip.select_set(False)
    c.add(tip, "spike", angle=180)


def tail_fluke(c):
    pts = curve_points((0, BODY_D / 2 - 0.1, BODY_Z - 0.3), (0, BODY_D / 2 + 0.55, BODY_Z - 0.35), (0, BODY_D / 2 + 0.8, BODY_Z + 0.0), 8)
    c.add(tapered("Tail", pts, 0.3, 0.4), "body")
    end = Vector(pts[-1])
    sym(lambda s: c.add(ellipsoid("Fluke", (0.38, 0.2, 0.06), tuple(end + Vector((0.28 * s, 0.1, 0.05))), segments=16, rings=8, rotation=(math.radians(-25), 0, math.radians(-25 * s))), "fin"))


def tail_flame(c):
    for i, (x, h) in enumerate([(-0.3, 0.9), (0.0, 1.15), (0.3, 0.9)]):
        pts = curve_points((x * 0.5, BODY_D / 2 - 0.1, BODY_Z - 0.35), (x, BODY_D / 2 + 0.6, BODY_Z - 0.3), (x * 1.4, BODY_D / 2 + 0.75, BODY_Z - 0.3 + h), 10)
        c.add(tapered("TailFeather", pts, 0.2, 0.05), "flame" if i != 1 else "flame2")


TAILS = {
    "fox": tail_fox,
    "stinger": tail_stinger,
    "devil": tail_devil,
    "lizard": tail_lizard,
    "dragon": tail_dragon,
    "fluke": tail_fluke,
    "flame": tail_flame,
}


# ----- Legs -------------------------------------------------------------------------------------------------------

def legs_feet(c):
    sym(lambda s: c.add(ellipsoid("Foot", (0.3, 0.42, 0.13), (0.52 * s, -0.55, 0.13), segments=18, rings=8), "feet"))


def legs_pot(c):
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=1.12, radius2=1.42, depth=0.85, location=(0, 0, 0.42), rotation=(0, 0, math.radians(45)))
    pot = bpy.context.active_object
    soft(pot, 0.08, segments=3, subdiv=0)
    c.add(pot, "pot")
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.9))
    rim = bpy.context.active_object
    rim.scale = (2.16, 2.16, 0.16)
    bpy.ops.object.transform_apply(scale=True)
    soft(rim, 0.06, segments=2, subdiv=0)
    c.add(rim, "pot_rim")


def legs_crab(c):
    def one(side):
        for i, y in enumerate((-0.45, 0.05, 0.55)):
            pts = curve_points((0.9 * side, y, 0.55), (1.35 * side, y, 0.6), (1.45 * side, y + 0.05, 0.0), 8)
            c.add(tapered("Leg", pts, 0.08, 0.5), "legs")
    sym(one)


def legs_tentacles(c):
    for i in range(6):
        a = math.radians(30 + i * 60)
        x, y = math.cos(a), math.sin(a)
        base = (x * 0.72, y * 0.72, 0.55)
        mid = (x * 1.15, y * 1.15, 0.12)
        end = (x * 1.55 + y * 0.25 * (1 if i % 2 else -1), y * 1.55 - x * 0.25 * (1 if i % 2 else -1), 0.32)
        c.add(tapered("Tentacle", curve_points(base, mid, end, 12), 0.2, 0.25), "body")


def legs_wisp(c):
    for x, y in ((-0.55, -0.55), (0.55, -0.55), (-0.55, 0.55), (0.55, 0.55), (0, 0)):
        c.add(cone("Wisp", 0.32, 0.02, 0.55, (x, y, 0.62), rotation=(math.radians(180), 0, 0), verts=12), "body")


LEGS = {"feet": legs_feet, "pot": legs_pot, "crab": legs_crab, "tentacles": legs_tentacles, "wisp": legs_wisp}


# ----- Faces: extra eye and mouth styles ---------------------------------------------------------------------------

def eye_arc(c, side, down):
    """Closed eyes: an arc ^ (down=False) or a sleepy ‿ curve (down=True)."""
    pts = []
    for i in range(11):
        a = math.pi * i / 10
        x = 0.47 * side + math.cos(a) * 0.17
        z = 0.08 + (-1 if down else 1) * math.sin(a) * 0.09
        pts.append(face_point(x, z, 0.015))
    c.add(tube("EyeArc", pts, 0.035), "eye")


def eyes_square(c, scale):
    def one(side):
        c.add(rounded_box("Eye", (0.32 * scale, 0.07, 0.36 * scale), face_point(0.45 * side, 0.08, 0.0), 0.06, segments=2), "eye")
        c.add(rounded_box("Shine", (0.08, 0.04, 0.08), face_point(0.45 * side + 0.06, 0.18, 0.04), 0.02, segments=1), "shine")
    sym(one)


def eyes_shades(c):
    def one(side):
        c.add(rounded_box("Lens", (0.62, 0.08, 0.36), face_point(0.43 * side, 0.12, 0.02), 0.12, segments=3), "shades")
        c.add(rounded_box("Glint", (0.18, 0.03, 0.05), face_point(0.43 * side + 0.08, 0.2, 0.065), 0.02, segments=1, rotation=(0, math.radians(-25), 0)), "shine")
    sym(one)
    c.add(rounded_box("Bridge", (0.3, 0.06, 0.07), face_point(0, 0.17, 0.02), 0.02, segments=1), "shades")


def eyes_stalk(c, scale):
    def one(side):
        base = (0.45 * side, -0.55, c.top - 0.05)
        top = (0.55 * side, -0.62, c.top + 0.55)
        c.add(tube("Stalk", curve_points(base, (0.45 * side, -0.6, c.top + 0.3), top, 6), 0.07), "body")
        c.add(ellipsoid("EyeBall", (0.2, 0.2, 0.2), top, segments=18, rings=10), "white")
        c.add(ellipsoid("Eye", (0.12 * scale, 0.07, 0.14 * scale), (top[0], top[1] - 0.15, top[2]), segments=14, rings=8), "eye")
        c.add(ellipsoid("Shine", (0.04, 0.03, 0.04), (top[0] + 0.04, top[1] - 0.22, top[2] + 0.05), segments=8, rings=6), "shine")
    sym(one)


def brows(c, angry=True):
    def one(side):
        a = face_point(0.25 * side, 0.36 if angry else 0.42, 0.02)
        b = face_point(0.7 * side, 0.46 if angry else 0.42, 0.02)
        c.add(tube("Brow", [a, b], 0.045), "brow" if "brow" in c.spec["colors"] else "mouth")
    sym(one)



# ----- Legendary parts -----------------------------------------------------------------------------------------

def feat_core(c):
    # A darker heart inside the jelly body
    c.add(rounded_box("Core", (1.15, 1.15, 1.05), (0, 0.05, BODY_Z - 0.05), 0.35, segments=4), "core")


def feat_bubbles(c):
    for x, y, z, r in [(-0.55, -0.45, 0.45, 0.13), (0.6, 0.3, -0.35, 0.1), (-0.3, 0.5, -0.55, 0.09), (0.45, -0.5, 0.62, 0.07), (0.7, -0.2, 0.2, 0.06), (-0.7, 0.1, -0.1, 0.08)]:
        c.add(ellipsoid("Bubble", (r, r, r), (x, y, BODY_Z + z), segments=14, rings=8), "bubble")


def feat_drips(c):
    # Jelly running down the sides into a puddle
    for x, y, h in [(-0.65, -1.0, 0.45), (0.2, -1.0, 0.3), (1.0, 0.3, 0.5), (-1.0, -0.2, 0.38), (0.55, 1.0, 0.42), (-0.4, 1.0, 0.3)]:
        c.add(ellipsoid("Drip", (0.14, 0.14, h), (x, y, LEG_H + h * 0.5), segments=14, rings=10), "jelly")
        c.add(ellipsoid("DripEnd", (0.17, 0.17, 0.17), (x, y, LEG_H + 0.05), segments=14, rings=10), "jelly")
    puddle = ellipsoid("Puddle", (1.45, 1.4, 0.2), (0, 0, 0.12), segments=36, rings=12)
    c.add(puddle, "jelly")


def feat_halo(c):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.62, minor_radius=0.07, location=(0, 0.1, c.top + c.spec.get("halo_height", 0.85)), rotation=(math.radians(-12), 0, 0))
    c.add(bpy.context.active_object, "glow")


def feat_orbs(c):
    for x, y, z, r in c.spec.get("orb_list", [(-1.35, -0.3, 0.75, 0.13), (1.4, 0.2, 0.95, 0.11), (1.25, -0.6, -0.2, 0.09), (-1.3, 0.5, -0.1, 0.1), (0.2, -0.9, 1.65, 0.08)]):
        c.add(ellipsoid("Orb", (r, r, r), (x, y, BODY_Z + z), segments=14, rings=8), "glow2")


def feat_flower_crown(c):
    for i in range(10):
        a = math.radians(i * 36)
        x, y = math.cos(a) * 0.82, math.sin(a) * 0.82
        key = "flower" if i % 2 == 0 else "flower2"
        for j in range(5):
            b = math.radians(j * 72)
            c.add(ellipsoid("Petal", (0.11, 0.08, 0.04), (x + math.cos(b) * 0.1, y + math.sin(b) * 0.1, c.top + 0.06), segments=10, rings=6, rotation=(0, 0, b)), key)
        c.add(ellipsoid("FlowerCenter", (0.06, 0.06, 0.05), (x, y, c.top + 0.1), segments=10, rings=6), "flower_center")


def feat_wings_fairy(c):
    # Four see-through petal wings that glow at the edges
    def one(side):
        for w, h, z, lean in ((0.75, 0.42, 0.45, 32), (0.55, 0.32, -0.15, -18)):
            for key, scale, dy in (("glow2", 1.06, 0.03), ("wing", 1.0, 0.0)):
                wing = ellipsoid("Wing", (w * scale, 0.04, h * scale), (0, 0, 0), segments=24, rings=10)
                wing.data.transform(Matrix.Translation((w * 0.85 * side, dy, 0)))
                wing.location = (0.3 * side, 1.08, BODY_Z + z)
                wing.rotation_euler = (0, -math.radians(lean) * side, 0)
                bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
                c.add(wing, key)
    sym(one)


def feat_bark(c):
    # Vertical grooves on the sides and back
    for side in (-1, 1):
        for y in (-0.5, 0.0, 0.5):
            c.add(rounded_box("Groove", (0.05, 0.1, 1.25), (side * (BODY_W / 2 + 0.01), y + 0.05 * side, BODY_Z + 0.05), 0.02, segments=1), "bark")
    for x in (-0.55, 0.0, 0.55):
        c.add(rounded_box("Groove", (0.1, 0.05, 1.2), (x, BODY_D / 2 + 0.01, BODY_Z), 0.02, segments=1), "bark")


def ears_branches(c):
    def one(side):
        main = curve_points((0.45 * side, 0.0, c.top - 0.05), (0.7 * side, 0.0, c.top + 0.55), (1.15 * side, 0.1, c.top + 0.95), 10)
        c.add(tapered("Branch", main, 0.14, 0.4), "bark")
        twig = curve_points(main[4], (0.45 * side, -0.05, c.top + 0.8), (0.4 * side, -0.05, c.top + 1.1), 8)
        c.add(tapered("Twig", twig, 0.08, 0.5), "bark")
        for p, r in ((main[-1], 0.32), (twig[-1], 0.26), (main[6], 0.2)):
            c.add(ellipsoid("Leaves", (r, r, r * 0.85), p, segments=16, rings=10), "leaf")
    sym(one)


def feat_moss(c):
    for x, y, r in [(-0.4, -0.2, 0.42), (0.35, 0.35, 0.35), (0.0, 0.6, 0.3)]:
        c.add(ellipsoid("Moss", (r, r, 0.1), (x, y, c.top + 0.02), segments=18, rings=8), "moss")
    sym(lambda s_: c.add(ellipsoid("Moss", (0.06, 0.4, 0.28), (s_ * (BODY_W / 2 + 0.02), 0.2, BODY_Z + 0.6), segments=14, rings=8), "moss"))


def feat_side_mushrooms(c):
    for x, y, z, r in [(1.0, -0.35, -0.3, 0.2), (1.0, -0.1, -0.5, 0.14), (-1.0, 0.4, 0.1, 0.17)]:
        side = 1 if x > 0 else -1
        stem = rounded_box("Stem", (0.14, 0.08, 0.08), (x + side * 0.06, y, BODY_Z + z), 0.03, segments=1)
        c.add(stem, "mushroom_stem")
        cap = ellipsoid("MushCap", (r * 0.6, r, r), (x + side * (0.12 + r * 0.25), y, BODY_Z + z), segments=14, rings=8)
        c.add(cap, "glow2")


def feat_coral_crown(c):
    for i, (x, y, h, lean) in enumerate([(0, -0.3, 0.75, 0), (-0.45, -0.1, 0.55, -25), (0.45, -0.1, 0.55, 25), (-0.25, 0.35, 0.5, -15), (0.25, 0.35, 0.5, 15)]):
        base = (x, y, c.top - 0.05)
        end = (x + math.sin(math.radians(lean)) * h, y, c.top + h)
        pts = curve_points(base, (x, y, c.top + h * 0.5), end, 8)
        key = "coral" if i % 2 == 0 else "coral2"
        c.add(tapered("Coral", pts, 0.09, 0.6), key)
        c.add(ellipsoid("CoralTip", (0.07, 0.07, 0.07), end, segments=10, rings=6), key)
        if h > 0.52:
            side_end = (end[0] + 0.18, y, c.top + h * 0.7)
            c.add(tapered("Coral", curve_points(pts[4], (side_end[0], y, pts[4][2] + 0.1), side_end, 6), 0.06, 0.6), key)


def feat_pearl(c):
    c.add(ellipsoid("Pearl", (0.14, 0.14, 0.14), face_point(0, 0.62, 0.06), segments=16, rings=10), "glow")


def feat_suckers(c):
    for i in range(6):
        a = math.radians(30 + i * 60)
        x, y = math.cos(a), math.sin(a)
        for t in (0.35, 0.6, 0.82):
            px = x * (0.72 + 0.83 * t)
            py = y * (0.72 + 0.83 * t)
            pz = 0.55 - 0.45 * t + 0.1 * t * t
            c.add(ellipsoid("Sucker", (0.06, 0.06, 0.03), (px, py, max(0.05, pz - 0.14)), segments=10, rings=6), "sucker")


def ears_wizard(c):
    # A tall bent wizard hat that is also a mushroom cap, with glowing spots
    pts = curve_points((0, 0.05, c.top - 0.25), (0, 0.15, c.top + 1.0), (0.45, 0.45, c.top + 1.3), 14)
    c.add(tapered("Hat", pts, 1.05, 0.04), "cap")
    for i, t in enumerate((0.25, 0.45, 0.62)):
        p = Vector(pts[int(t * (len(pts) - 1))])
        r = 1.05 * (1 - 0.96 * t)
        c.add(ellipsoid("Spot", (0.13, 0.13, 0.13), (p.x + r * 0.7, p.y - r * 0.7, p.z), segments=12, rings=8), "glow")
        c.add(ellipsoid("Spot", (0.1, 0.1, 0.1), (p.x - r * 0.75, p.y - r * 0.5, p.z + 0.05), segments=12, rings=8), "glow")
    bpy.ops.mesh.primitive_torus_add(major_radius=1.05, minor_radius=0.09, location=(0, 0.05, c.top - 0.12))
    c.add(bpy.context.active_object, "cap_rim")


def feat_beard(c):
    for x, z, r in [(0, -0.42, 0.26), (-0.22, -0.32, 0.2), (0.22, -0.32, 0.2), (-0.1, -0.62, 0.18), (0.1, -0.62, 0.18), (0, -0.8, 0.14)]:
        c.add(ellipsoid("Beard", (r, r * 0.8, r), face_point(x, z, 0.08), segments=14, rings=8), "beard")


def feat_spores(c):
    for x, y, z, r in [(-1.3, -0.4, 0.4, 0.07), (1.35, -0.2, 0.7, 0.06), (1.2, 0.5, 1.3, 0.08), (-1.2, 0.3, 1.2, 0.06), (-0.6, -1.1, 1.5, 0.05), (0.8, -1.0, 0.1, 0.05), (0.2, -1.2, 1.0, 0.06)]:
        c.add(ellipsoid("Spore", (r, r, r), (x, y, BODY_Z + z), segments=10, rings=6), "glow2")


def feat_scarab_shell(c):
    # Two shiny shell halves on top with a seam
    for side in (-1, 1):
        half = ellipsoid("Shell", (0.47, 0.92, 0.36), (side * 0.49, 0.08, c.top - 0.06), segments=28, rings=14)
        c.add(half, "shell")
        c.add(ellipsoid("ShellShine", (0.1, 0.42, 0.04), (side * 0.52, -0.05, c.top + 0.27), segments=12, rings=6, rotation=(0, math.radians(-12 * side), 0)), "glow2")
    for side in (-1, 1):
        for y in (-0.4, 0.15, 0.6):
            c.add(rounded_box("Lapis", (0.1, 0.18, 0.5), (side * (BODY_W / 2 + 0.03), y, BODY_Z + 0.15), 0.04, segments=1), "lapis")


def feat_sun_disk(c):
    # A sun disk standing behind the head, ringed in gold
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.62, depth=0.1, location=(0, 0.75, c.top + 0.85), rotation=(math.radians(90), 0, 0))
    c.add(bpy.context.active_object, "glow")
    bpy.ops.mesh.primitive_torus_add(major_radius=0.68, minor_radius=0.08, location=(0, 0.75, c.top + 0.85), rotation=(math.radians(90), 0, 0))
    c.add(bpy.context.active_object, "gold")
    for i in range(12):
        a = math.radians(i * 30)
        c.add(cone("Ray", 0.06, 0.0, 0.28, (math.cos(a) * 0.74, 0.75, c.top + 0.85 + math.sin(a) * 0.74), rotation=(0, math.radians(90) - a, 0), verts=6), "gold")


def feat_mane(c):
    # A fluffy collar all around the neck line
    for i in range(16):
        a = math.radians(i * 22.5)
        x, y = math.cos(a) * 1.02, math.sin(a) * 1.02
        if y < -0.7 and abs(x) < 0.6:
            continue  # keep the face free
        c.add(ellipsoid("Mane", (0.24, 0.24, 0.2), (x * 0.93, y * 0.93, c.top - 0.12), segments=14, rings=8), "mane" if i % 2 else "mane2")


def feat_aurora(c):
    for i, (z0, z1) in enumerate([(0.55, 0.68), (0.78, 0.86)]):
        c.add(shell_of_body("Aurora", 0.03 + i * 0.005, slab(z0, z1, front_cut=-0.55)), "glow" if i == 0 else "glow2")


def feat_lava_cracks(c):
    paths = [
        [(-0.85, 0.7), (-0.6, 0.5), (-0.7, 0.25), (-0.45, 0.05)],
        [(0.85, -0.6), (0.6, -0.45), (0.7, -0.2)],
        [(-0.3, -0.85), (-0.15, -0.65), (-0.3, -0.5)],
    ]
    for pts in paths:
        c.add(tube("Crack", [face_point(x, z, 0.005) for x, z in pts], 0.035), "glow")
    for side in (-1, 1):
        for pts in ([(-0.7, 0.6), (-0.3, 0.3), (-0.45, -0.1), (0.1, -0.4)], [(0.2, 0.75), (0.5, 0.4), (0.4, 0.1)]):
            c.add(tube("Crack", [(side * (BODY_W / 2 + 0.005), y, BODY_Z + z) for y, z in pts], 0.035), "glow")
    for pts in ([(-0.6, 0.6), (-0.2, 0.2), (0.3, 0.4), (0.6, -0.2)], [(-0.4, -0.3), (0.0, -0.6)]):
        c.add(tube("Crack", [(x, BODY_D / 2 + 0.005, BODY_Z + z) for x, z in pts], 0.035), "glow")
    for pts in ([(-0.6, -0.5), (-0.1, -0.1), (0.4, 0.2), (0.7, 0.6)],):
        c.add(tube("Crack", [(x, y, c.top + 0.005) for x, y in pts], 0.035), "glow")


def feat_ice_crown(c):
    for x, y, h, lean in [(0, -0.3, 0.75, 0), (-0.35, -0.2, 0.5, -20), (0.35, -0.2, 0.5, 20), (-0.6, 0.1, 0.35, -30), (0.6, 0.1, 0.35, 30), (0, 0.25, 0.45, 0)]:
        c.add(cone("Crystal", 0.16, 0.0, h, (x, y, c.top - 0.08), rotation=(0, math.radians(lean), 0), verts=5), "glow")


def feat_float_ring(c):
    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.06, location=(0, 0, 0.05))
    c.add(bpy.context.active_object, "glow2")


def feat_glitch(c):
    import random

    rng = random.Random(11)
    keys = ["glow", "glow2", "glow3"]
    for i in range(18):
        face = rng.choice(["top", "side", "side", "front", "back", "float"])
        s_ = rng.uniform(0.12, 0.3)
        if face == "top":
            loc = (rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8), c.top + s_ * 0.2)
        elif face == "side":
            loc = (rng.choice([-1, 1]) * (BODY_W / 2 + s_ * 0.2), rng.uniform(-0.8, 0.8), BODY_Z + rng.uniform(-0.8, 0.8))
        elif face == "front":
            loc = (rng.choice([-0.85, 0.85]), FRONT_Y - s_ * 0.2, BODY_Z + rng.uniform(-0.8, 0.8))
        elif face == "back":
            loc = (rng.uniform(-0.8, 0.8), BODY_D / 2 + s_ * 0.2, BODY_Z + rng.uniform(-0.8, 0.8))
        else:
            loc = (rng.uniform(-1.6, 1.6), rng.uniform(-1.0, 1.0), BODY_Z + rng.uniform(0.6, 1.6))
            if abs(loc[0]) < 1.2:
                loc = (math.copysign(1.35, loc[0]), loc[1], loc[2])
        c.add(rounded_box("GlitchBit", (s_, s_, s_), loc, 0.015, segments=1), keys[i % 3])
    # RGB split edges: thin glowing outlines offset on the front
    c.add(rounded_box("Split", (0.06, 0.05, 1.5), (-1.02, FRONT_Y - 0.02, BODY_Z), 0.02, segments=1), "glow")
    c.add(rounded_box("Split", (0.06, 0.05, 1.5), (1.02, FRONT_Y - 0.02, BODY_Z), 0.02, segments=1), "glow2")


def tail_flame_tip(c):
    tail_dragon(c)
    pts = curve_points((0, BODY_D / 2 - 0.1, BODY_Z - 0.45), (0, BODY_D / 2 + 1.0, BODY_Z - 0.75), (0.7, BODY_D / 2 + 1.1, BODY_Z - 0.3), 14)
    end = Vector(pts[-1])
    for i, (h, key) in enumerate(((0.6, "glow"), (0.42, "glow2"))):
        c.add(cone("TailFlame", 0.2 - i * 0.06, 0.0, h, tuple(end + Vector((0.05, 0.05, 0.05))), rotation=(math.radians(-15), math.radians(25), 0), verts=10), key)


LEGEND_FEATURES = {
    "core": feat_core,
    "bubbles": feat_bubbles,
    "drips": feat_drips,
    "halo": feat_halo,
    "orbs": feat_orbs,
    "flower_crown": feat_flower_crown,
    "wings_fairy": feat_wings_fairy,
    "bark": feat_bark,
    "moss": feat_moss,
    "side_mushrooms": feat_side_mushrooms,
    "coral_crown": feat_coral_crown,
    "pearl": feat_pearl,
    "suckers": feat_suckers,
    "beard": feat_beard,
    "spores": feat_spores,
    "scarab_shell": feat_scarab_shell,
    "sun_disk": feat_sun_disk,
    "mane": feat_mane,
    "aurora": feat_aurora,
    "lava_cracks": feat_lava_cracks,
    "ice_crown": feat_ice_crown,
    "float_ring": feat_float_ring,
    "glitch": feat_glitch,
}
FEATURES.update(LEGEND_FEATURES)
EARS.update({"branches": ears_branches, "wizard": ears_wizard})
TAILS["flame_tip"] = tail_flame_tip


# ---------------------------------------------------------------------------------------------------------------
# Building


def build(spec):
    colors = {key: hex_color(value) for key, value in spec["colors"].items()}
    mat = Mats(spec)
    for key, value in colors.items():
        mat[key] = material(key, value, gloss=key in ("eye", "shine", "nose"))
    parts = []
    c = Ctx(spec, mat, parts)

    # Body: one rounded cube
    body = rounded_box("Body", (BODY_W, BODY_D, BODY_H), (0, 0, BODY_Z), BEVEL, segments=5)
    parts.append(finish(body, mat[spec.get("body_key", "body")]))

    # Belly: a shell of the body (slightly bigger) cut by an ellipse at the front, so it wraps the bevel
    if "belly" in spec["colors"]:
        build_belly(spec, mat, parts)

    legs_kind = spec.get("legs", "normal")
    start = len(parts)
    if legs_kind in LEGS:
        LEGS[legs_kind](c)
    elif legs_kind == "normal":
        build_legs(mat, parts)
    tag(parts, start, "leg")

    build_head(spec, mat, parts, c)
    return parts


def build_belly(spec, mat, parts):
    belly = rounded_box("Belly", (BODY_W + 0.03, BODY_D + 0.03, BODY_H + 0.03), (0, 0, BODY_Z), BEVEL + 0.015, segments=5)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=1, depth=1.2, location=(0, FRONT_Y + 0.25, LEG_H), rotation=(math.radians(90), 0, 0))
    cutter = bpy.context.active_object
    cutter.scale = (0.74, 0.62, 1)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    boolean = belly.modifiers.new("Cut", "BOOLEAN")
    boolean.operation = "INTERSECT"
    boolean.object = cutter
    apply_modifiers(belly)
    bpy.data.objects.remove(cutter)
    parts.append(finish(belly, mat["belly"]))


def build_legs(mat, parts):
    # Legs: four short rounded blocks at the corners
    for x in (-0.62, 0.62):
        for y in (-0.62, 0.62):
            leg = rounded_box("Leg", (0.46, 0.46, LEG_H + 0.3), (x, y, (LEG_H + 0.3) / 2), 0.1, segments=3)
            parts.append(finish(leg, mat["legs"]))


def build_head(spec, mat, parts, c):
    # Ears: thick rounded triangles on the top corners, leaning out a little, with a soft pink triangle
    # set into the front. Bevel + one level of subdivision keeps every edge soft (no sharp cone tips).
    if spec["ears"] == "cat":
        top = BODY_Z + BODY_H / 2

        for side in (-1, 1):
            lean = math.radians(-11 * side)
            base = Vector((0.56 * side, -0.32, top - 0.22))
            ear = triangle_prism("Ear", half_width=0.4, height=0.82, depth=0.36, tip_shift=0.05 * side)
            soft(ear, 0.12, segments=3, subdiv=1)
            place(ear, base, lean)
            parts.append(finish(ear, mat["body"], angle=180))
            inner = triangle_prism("EarInner", half_width=0.22, height=0.46, depth=0.08, tip_shift=0.04 * side)
            soft(inner, 0.035, segments=2, subdiv=1)
            place(inner, base + Vector((0, -0.17, 0.2)), lean)
            parts.append(finish(inner, mat["ear_inner"], angle=180))

    top = BODY_Z + BODY_H / 2

    # Bunny ears: long soft paddles standing up, pink inside, leaning apart
    if spec["ears"] == "bunny":
        for side in (-1, 1):
            lean = math.radians(-9 * side)
            base = Vector((0.46 * side, -0.05, top - 0.25))
            # Built standing on the origin so `place` puts the ear's base on the head
            ear = rounded_box("Ear", (0.44, 0.26, 1.3), (0, 0, 0), 0.13, segments=3)
            ear.data.transform(Matrix.Translation((0, 0, 0.65)))
            soft(ear, 0.0, segments=1, subdiv=1)
            place(ear, base, lean, tilt=-8)
            parts.append(finish(ear, mat["body"], angle=180))
            inner = rounded_box("EarInner", (0.25, 0.06, 0.9), (0, 0, 0), 0.03, segments=2)
            inner.data.transform(Matrix.Translation((0, -0.12, 0.72)))
            soft(inner, 0.0, segments=1, subdiv=1)
            place(inner, base, lean, tilt=-8)
            parts.append(finish(inner, mat["ear_inner"], angle=180))

    # Round ears: half balls on the top corners with a lighter inside
    if spec["ears"] == "round":
        for side in (-1, 1):
            ear = ellipsoid("Ear", (0.34, 0.22, 0.32), (0.66 * side, -0.15, top + 0.06), segments=20, rings=12)
            parts.append(finish(ear, mat["body"]))
            inner = ellipsoid("EarInner", (0.2, 0.06, 0.19), (0.66 * side, -0.33, top + 0.06), segments=16, rings=8)
            parts.append(finish(inner, mat["ear_inner"]))

    if spec["ears"] in EARS:
        EARS[spec["ears"]](c)

    # Tuft: a little curl of hair on top
    if spec.get("tuft"):
        # A curl that rises from the head, loops forward and ends in a little hook
        curl = []
        for i in range(24):
            t = i / 23
            angle = math.pi * 1.7 * t
            radius = 0.32 * (1 - 0.55 * t)
            curl.append((0.0 + math.sin(angle) * radius, -0.1, top - 0.08 + 0.32 + (1 - math.cos(angle)) * radius * 0.85 - 0.3 * (1 - t) ** 3))
        hair = tube("Tuft", curl, 0.11)
        parts.append(finish(hair, mat["tuft"]))

    for feature in spec.get("features", []):
        if feature in ("face_patch", "eye_rings", "screen"):
            FEATURES[feature](c)

    # Eyes with a white shine
    eye_scale = spec.get("eyes", 1.0)
    eye_style = spec.get("eye_style", "oval")
    if eye_style in ("oval", "sparkle"):
        for side in (-1, 1):
            eye = ellipsoid("Eye", (0.19 * eye_scale, 0.07, 0.24 * eye_scale), face_point(0.47 * side, 0.1, 0.0))
            parts.append(finish(eye, mat["eye"]))
            shine = ellipsoid("Shine", (0.055 * eye_scale, 0.03, 0.055 * eye_scale), face_point(0.47 * side + 0.06 * eye_scale, 0.1 + 0.09 * eye_scale, 0.06), segments=10, rings=6)
            parts.append(finish(shine, mat["shine"]))
            if eye_style == "sparkle":
                small = ellipsoid("Shine", (0.032 * eye_scale, 0.03, 0.032 * eye_scale), face_point(0.47 * side - 0.07 * eye_scale, 0.1 - 0.1 * eye_scale, 0.06), segments=8, rings=6)
                parts.append(finish(small, mat["shine"]))
    elif eye_style == "closed":
        sym(lambda s_: eye_arc(c, s_, down=False))
    elif eye_style == "sleepy":
        sym(lambda s_: eye_arc(c, s_, down=True))
    elif eye_style == "square":
        eyes_square(c, eye_scale)
    elif eye_style == "shades":
        eyes_shades(c)
    elif eye_style == "stalk":
        eyes_stalk(c, eye_scale)
    if spec.get("brows"):
        brows(c, angry=spec["brows"] == "angry")

    # Muzzle: a soft lighter bump on the lower face that the nose and mouth sit on
    muzzle_out = 0.0
    muzzle = None
    if spec.get("muzzle"):
        muzzle = {"rx": 0.4, "ry": 0.2, "rz": 0.28, "z": -0.2}
        bump = ellipsoid("Muzzle", (muzzle["rx"], muzzle["ry"], muzzle["rz"]), face_point(0, muzzle["z"], -0.04), segments=24, rings=12)
        parts.append(finish(bump, mat["muzzle"]))
        muzzle_out = muzzle["ry"] - 0.04

    def on_face(x, z, lift):
        """A point on the face, or on the muzzle's surface when there is one."""
        out = lift
        if muzzle:
            k = 1 - (x / muzzle["rx"]) ** 2 - ((z - muzzle["z"]) / muzzle["rz"]) ** 2
            if k > 0:
                out += muzzle["ry"] * math.sqrt(k) - 0.04
        return face_point(x, z, out)

    # Nose
    nose_kind = spec.get("nose")
    if nose_kind == "triangle":
        bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=0.12, radius2=0.0, depth=0.08, location=face_point(0, -0.03, 0.03), rotation=(math.radians(90), 0, math.radians(180)))
        nose = bpy.context.active_object
        nose.name = "Nose"
        bevel = nose.modifiers.new("Bevel", "BEVEL")
        bevel.width = 0.04
        bevel.segments = 4
        apply_modifiers(nose)
        parts.append(finish(nose, mat["nose"]))
    elif nose_kind == "oval":
        nose = ellipsoid("Nose", (0.09, 0.05, 0.065), face_point(0, -0.03, 0.02), segments=14, rings=8)
        parts.append(finish(nose, mat["nose"]))
    elif nose_kind == "bear":
        nose = ellipsoid("Nose", (0.15, 0.08, 0.1), on_face(0, -0.08, 0.02), segments=16, rings=10)
        parts.append(finish(nose, mat["nose"]))
    elif nose_kind == "beak":
        beak = cone("Beak", 0.17, 0.0, 0.32, face_point(0, -0.05, -0.02), rotation=(math.radians(100), 0, 0), verts=12)
        beak.scale = (1, 1, 1)
        c.add(beak, "beak")
    elif nose_kind == "carrot":
        c.add(cone("Carrot", 0.12, 0.0, 0.6, face_point(0, -0.02, -0.02), rotation=(math.radians(95), 0, 0), verts=12), "carrot")

    # Mouth: a cat "w" or a simple smile. "_mouths" picks what gets built:
    #   "default" the species' own mouth, "open" only the D mouth, "both" (the game) closed + open, tagged
    mouths = spec.get("_mouths", "default")
    mouth_kind = spec.get("mouth", "cat")
    if mouths == "open" and mouth_kind != "none":
        mouth_kind = "d"
    elif mouths == "both" and mouth_kind == "open":
        mouth_kind = "smile"  # the closed look of a creature that is drawn with its mouth open
    mouth_start = len(parts)
    points = []
    if mouth_kind in ("open", "d", "frown", "line", "fangs", "none", "dots"):
        build_mouth(c, mouth_kind, on_face)
    elif mouth_kind == "cat":
        radius = 0.09
        for center in (-radius, radius):
            for i in range(9):
                angle = math.pi + math.pi * i / 8
                if center > 0 and i == 0:
                    continue
                points.append(on_face(center + radius * math.cos(angle), -0.14 + radius * math.sin(angle), 0.015))
    else:
        radius, z0 = (0.12, -0.2) if muzzle else (0.14, -0.08)
        for i in range(13):
            angle = math.pi * 1.15 + math.pi * 0.7 * i / 12
            points.append(on_face(radius * math.cos(angle), z0 + radius * math.sin(angle), 0.015))
    if points:
        mouth = tube("Mouth", points, 0.026)
        parts.append(finish(mouth, mat["mouth"]))
    if mouths == "both" and spec.get("mouth", "cat") != "none":
        tag(parts, mouth_start, "mouthC")
        open_start = len(parts)
        build_mouth(c, "d", on_face)
        tag(parts, open_start, "mouthO")

    # Buck teeth under the mouth
    if spec.get("teeth"):
        # A dark backing so white teeth still read on a white face
        backing = rounded_box("TeethBack", (0.2, 0.03, 0.15), face_point(0, -0.285, 0.0), 0.03, segments=2)
        parts.append(finish(backing, mat["mouth"]))
        for side in (-1, 1):
            tooth = rounded_box("Tooth", (0.075, 0.04, 0.11), face_point(0.043 * side, -0.29, 0.025), 0.018, segments=2)
            parts.append(finish(tooth, mat["teeth"]))

    for feature in spec.get("features", []):
        if feature not in ("face_patch", "eye_rings", "screen"):
            start = len(parts)
            FEATURES[feature](c)
            if feature.startswith("wings"):
                tag(parts, start, "wing")

    # Blush
    for side in (-1, 1) if spec.get("blush", True) else ():
        blush = ellipsoid("Blush", (0.13, 0.02, 0.09), face_point(0.76 * side, -0.07, 0.0), segments=14, rings=6)
        parts.append(finish(blush, mat["blush"]))

    # Tail
    tail_start = len(parts)
    build_tail(spec, mat, parts, c)
    tag(parts, tail_start, "tail")


def build_tail(spec, mat, parts, c):
    if spec["tail"] == "stub":
        tail = rounded_box("Tail", (0.34, 0.75, 0.32), (0, BODY_D / 2 + 0.28, BODY_Z - 0.36), 0.1, segments=3, rotation=(math.radians(-18), 0, 0))
        parts.append(finish(tail, mat["legs"]))
    elif spec["tail"] == "puff":
        tail = ellipsoid("Tail", (0.3, 0.26, 0.3), (0, BODY_D / 2 + 0.08, BODY_Z - 0.35), segments=20, rings=12)
        parts.append(finish(tail, mat["tail"]))
    elif spec["tail"] == "nub":
        tail = ellipsoid("Tail", (0.18, 0.16, 0.18), (0, BODY_D / 2 + 0.04, BODY_Z - 0.4), segments=16, rings=10)
        parts.append(finish(tail, mat["tail"]))
    elif spec["tail"] in TAILS:
        TAILS[spec["tail"]](c)


def build_mouth(c, kind, on_face):
    if kind in ("open", "d"):
        # The open mouth: a "D" turned on its side (flat top, round bottom), set into the face, with a tongue
        w, h = 0.25, 0.23
        top = -0.1
        outline = [(-w + 0.03, top), (w - 0.03, top)]
        for i in range(1, 16):
            a = math.pi * i / 16
            outline.append((w * math.cos(a), top - h * math.sin(a)))
        center = on_face(0, top - h * 0.5, 0.0)
        y = center[1] + 0.012
        mouth = extruded("MouthD", [(x, BODY_Z + z) for x, z in outline], 0.03, y=y)
        soft(mouth, 0.008, segments=2, subdiv=0)
        c.add(mouth, "mouth")
        # Tongue: follows the bottom of the D, with a soft dome on top
        tongue_outline = []
        tw = 0.15
        for i in range(13):
            x = tw - 2 * tw * i / 12
            tongue_outline.append((x, top - h * math.sqrt(max(0.0, 1 - (x / w) ** 2)) + 0.018))
        for i in range(1, 12):
            x = -tw + 2 * tw * i / 12
            tongue_outline.append((x, top - h * 0.5 - 0.05 * (x / tw) ** 2))
        tongue = extruded("Tongue", [(x, BODY_Z + z) for x, z in tongue_outline], 0.03, y=y - 0.012)
        soft(tongue, 0.008, segments=2, subdiv=0)
        c.add(tongue, "tongue")
        return
    if kind in ("frown", "line", "fangs", "dots"):
        if kind == "dots":
            for x, z in ((-0.2, -0.18), (-0.1, -0.24), (0.0, -0.26), (0.1, -0.24), (0.2, -0.18)):
                c.add(ellipsoid("Coal", (0.045, 0.03, 0.045), on_face(x, z, 0.0), segments=8, rings=6), "dark")
            return
        pts = []
        for i in range(11):
            t = i / 10
            x = -0.13 + 0.26 * t
            if kind == "frown":
                z = -0.2 + math.sin(math.pi * t) * 0.06
            elif kind == "line":
                z = -0.17
            else:
                z = -0.13 - math.sin(math.pi * t) * 0.07
            pts.append(on_face(x, z, 0.015))
        c.add(tube("Mouth", pts, 0.026), "mouth")
        if kind == "fangs":
            sym(lambda s_: c.add(cone("Fang", 0.04, 0.0, 0.1, on_face(0.07 * s_, -0.18, 0.02), rotation=(math.radians(180), 0, 0), verts=8), "white"))


# ---------------------------------------------------------------------------------------------------------------
# Scene, renders and export


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials.clear()


def setup_render(resolution=640):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (*hex_color(os.environ.get("BG", "#B9B9B9")), 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0

    bpy.ops.object.light_add(type="SUN", location=(4, -6, 8))
    sun = bpy.context.active_object
    sun.data.energy = 2.2
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(25))
    bpy.ops.object.light_add(type="AREA", location=(-4, -5, 4))
    fill = bpy.context.active_object
    fill.data.energy = 250
    fill.data.size = 6
    fill.rotation_euler = (math.radians(60), 0, math.radians(-40))

    bpy.ops.object.camera_add()
    camera = bpy.context.active_object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 4.3
    scene.camera = camera
    return camera


def render_views(name, camera):
    target = Vector((0, 0, 1.6))
    views = [("three_quarter", 35)] if FAST else [("front", 0), ("side", 90), ("back", 180), ("three_quarter", 35)]
    name = name.replace(" ", "")
    paths = []
    for view, angle in views:
        rad = math.radians(angle)
        # Side view looks at the creature's right side, like the concept sheet
        direction = Vector((-math.sin(rad), -math.cos(rad), 0.08)).normalized()
        camera.location = target + direction * 12
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(ROOT, "renders", f"_{name}_{view}.png")
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        paths.append(path)

    from PIL import Image

    images = [Image.open(p) for p in paths]
    sheet = Image.new("RGB", (sum(i.width for i in images), images[0].height))
    x = 0
    for image in images:
        sheet.paste(image, (x, 0))
        x += image.width
    sheet.save(os.path.join(ROOT, "renders", f"{name}.png"))
    for p in paths:
        os.remove(p)


def export(name, parts):
    """Joins everything into one mesh. Each color becomes a cell of a small palette texture and the
    faces' UVs point at their cell, so Roblox needs one MeshPart and one texture."""
    from PIL import Image

    palette = []
    for part in parts:
        color = tuple(part.data.materials[0]["palette_color"])
        if color not in palette:
            palette.append(color)
    cells = len(palette)
    cell = 16
    image = Image.new("RGB", (cell * cells, cell))
    for i, color in enumerate(palette):
        srgb = tuple(int(round(255 * (c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055))) for c in color)
        image.paste(srgb, (i * cell, 0, (i + 1) * cell, cell))
    name = name.replace(" ", "")
    palette_path = os.path.join(ROOT, "models", f"{name}_palette.png")
    image.save(palette_path)
    # Which part of the creature each palette cell is (viewers and variant shaders use it)
    import json

    roles = []
    for color in palette:
        names = [key for key, mat_ in materials.items() if tuple(mat_["palette_color"]) == color]
        roles.append(names)
    with open(os.path.join(ROOT, "models", f"{name}_palette.json"), "w") as f:
        json.dump({"cells": len(palette), "roles": roles}, f, indent=1)

    for part in parts:
        index = palette.index(tuple(part.data.materials[0]["palette_color"]))
        u = (index + 0.5) / cells
        if not part.data.uv_layers:
            part.data.uv_layers.new(name="UVMap")
        for loop in part.data.uv_layers.active.data:
            loop.uv = (u, 0.5)

    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    model = bpy.context.active_object
    model.name = name

    mat = bpy.data.materials.new(name + "Palette")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(palette_path)
    tex.interpolation = "Closest"
    mat.node_tree.links.new(tex.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])
    nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.55
    model.data.materials.clear()
    model.data.materials.append(mat)

    triangles = sum(len(poly.vertices) - 2 for poly in model.data.polygons)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(ROOT, "models", f"{name}.fbx"),
        use_selection=True,
        path_mode="COPY",
        embed_textures=True,
        apply_scale_options="FBX_SCALE_UNITS",
        axis_forward="-Z",
        axis_up="Y",
    )
    bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "models", f"{name}.glb"), use_selection=True)
    return triangles


def color_hex(spec, key):
    colors = spec["colors"]
    return colors.get(key) or DEFAULT_COLORS.get(key) or colors["body"]


def anim_name(obj):
    """Which moving piece a part belongs to in the game: legFL/legFR/legBL/legBR, wingL/wingR, tail,
    mouthC (closed) or mouthO (open), or "" for parts that only follow the body. Front is -Y, left is -X."""
    anim = obj.get("anim", "")
    if anim in ("leg", "wing"):
        corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
        center = sum(corners, Vector()) / 8
        side = "L" if center.x < 0 else "R"
        if anim == "wing":
            return "wing" + side
        return "leg" + ("F" if center.y < 0 else "B") + side
    return anim


def export_roblox():
    """All 50 creatures (40 zone creatures + 10 Legendaries) in one .glb for Roblox Studio's 3D importer.
    Each creature is a group named after the species; inside, one mesh per part role ("Kitty__body",
    "Kitty__eye"...), so the game can recolor every role for the variants. Also writes game/shared/Config/CreatureLooks.luau with each role's normal color."""
    reset()
    order = [name for zone in ZONES for name in zone] + LEGENDARIES
    looks = {}
    for index, name in enumerate(order):
        materials.clear()
        spec = dict(SPECIES[name])
        spec["_mouths"] = "both"  # closed and open mouths; the game shows one at a time
        parts = build(spec)
        groups = {}
        for part in parts:
            groups.setdefault((part.data.materials[0]["key"], anim_name(part)), []).append(part)
        root = bpy.data.objects.new(name, None)
        bpy.context.collection.objects.link(root)
        row, col = divmod(index, 8)
        root.location = (col * 5.0, row * 5.0, 0)
        looks[name] = {}
        for (key, anim), group in groups.items():
            bpy.ops.object.select_all(action="DESELECT")
            for part in group:
                part.select_set(True)
            bpy.context.view_layer.objects.active = group[0]
            if len(group) > 1:
                bpy.ops.object.join()
            obj = bpy.context.active_object
            # "Kitty__legs__legFL": role, then the moving piece it belongs to (see game/shared/PetModel.luau)
            obj.name = f"{name}__{key}" + (f"__{anim}" if anim else "")
            obj.data.name = obj.name
            obj.parent = root
            looks[name][key] = color_hex(spec, key)
        print(f"[cubelings] {name}: {len(groups)} parts")
    bpy.ops.object.select_all(action="SELECT")
    out = os.path.join(ROOT, "models", "Cubelings_Roblox.glb")
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True)
    print("wrote", out)

    lines = [
        "--!strict",
        "-- Generated by art/blender/cubelings.py (`python cubelings.py roblox`). Do not edit by hand.",
        "-- The normal color of every part of every creature's 3D model (species -> part role -> color).",
        "",
        "local looks: { [string]: { [string]: Color3 } } = {",
    ]
    for name in order:
        lines.append(f'\t["{name}"] = {{')
        for key, value in sorted(looks[name].items()):
            v = value.lstrip("#")
            r, g, b = (int(v[i : i + 2], 16) for i in (0, 2, 4))
            lines.append(f"\t\t{key} = Color3.fromRGB({r}, {g}, {b}),")
        lines.append("\t},")
    lines += ["}", "", "return looks", ""]
    config = os.path.join(os.path.dirname(ROOT), "game", "shared", "Config", "CreatureLooks.luau")
    with open(config, "w") as f:
        f.write("\n".join(lines))
    print("wrote", config)


def main():
    args = sys.argv[1:] or ["Kitty"]
    if args[0] == "roblox":
        export_roblox()
        return
    lineup_name = "lineup"
    if args[0] == "legendary":
        args = LEGENDARIES
        lineup_name = "legendaries_lineup"
    elif args[0] == "zone":
        index = int(args[1])
        args = ZONES[index - 1]
        lineup_name = f"zone{index}_lineup"
    for name in args:
        reset()
        parts = build(SPECIES[name])
        camera = setup_render()
        render_views(name, camera)
        triangles = export(name, parts)
        print(f"[cubelings] {name}: {triangles} triangles")
    if len(args) > 1:
        # Lineup: the 3/4 view of each creature side by side
        from PIL import Image

        views = []
        for name in args:
            sheet = Image.open(os.path.join(ROOT, "renders", f"{name.replace(' ', '')}.png"))
            w = sheet.width if FAST else sheet.width // 4
            views.append(sheet.crop((sheet.width - w, 0, sheet.width, sheet.height)))
        lineup = Image.new("RGB", (sum(v.width for v in views), views[0].height))
        x = 0
        for view in views:
            lineup.paste(view, (x, 0))
            x += view.width
        lineup.save(os.path.join(ROOT, "renders", f"{lineup_name}.png"))


if __name__ == "__main__":
    main()
