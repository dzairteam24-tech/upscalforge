"""The Cubeling Ride saddle (art: the saddle model sheet from ChatGPT), modeled for the creatures' 2-wide
cube body: a puffy cream underpad and a brown leather cover draped over the back and down the sides, a
dipped red-orange cushion with a cream piping, a back rest, a U handle in front, a paw badge on each side,
and straps with square gold buckles and gold stirrups.

Units are the creature models' (art/models): the body is 2 wide, the back's top is at z = 0, the sides are
at x = +-1. Front is -Y, like the creatures. The game scales it with the creature.

    python art/blender/saddle.py            renders: art/renders/Saddle.png (front, side, back, 3/4, top)
    python art/blender/saddle.py roblox     also writes art/models/Saddle.glb, one mesh per color role
                                            (Saddle__cushion, Saddle__cream, Saddle__leather, Saddle__dark,
                                            Saddle__gold, Saddle__paw), for Studio's Import 3D

Needs Python with bpy (Blender 4.2+) and pillow.
"""

import math
import os
import sys

import bpy  # noqa: I001 (bmesh only exists once bpy is loaded)
import bmesh
from mathutils import Vector

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.environ.get("OUT", ROOT)

COLORS = {
    "cushion": (0.78, 0.1, 0.02),
    "cream": (0.85, 0.74, 0.6),
    "leather": (0.22, 0.065, 0.025),
    "dark": (0.13, 0.04, 0.015),
    "gold": (1.0, 0.62, 0.08),
    "paw": (0.95, 0.36, 0.08),
}

BODY_HALF = 1.0  # the creature's side, from its middle
LENGTH = 1.5  # the leather cover, front to back
DROP = 0.85  # how far the leather goes down the sides

materials = {}


def material(key):
    if key in materials:
        return materials[key]
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*COLORS[key], 1)
    bsdf.inputs["Roughness"].default_value = 0.25 if key in ("gold", "cushion") else 0.5
    if key == "gold":
        bsdf.inputs["Metallic"].default_value = 0.6
    if key == "cushion":
        bsdf.inputs["Coat Weight"].default_value = 0.4
    materials[key] = mat
    return mat


def finish(obj, key):
    obj.data.materials.clear()
    obj.data.materials.append(material(key))
    obj["role"] = key
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def soft(obj, bevel=0.03, segments=3, subdiv=2):
    """Rounds the edges and smooths the shape, for the puffy toy look of the sheet."""
    if bevel > 0:
        b = obj.modifiers.new("Bevel", "BEVEL")
        b.width = bevel
        b.segments = segments
        b.limit_method = "NONE"
    if subdiv:
        s = obj.modifiers.new("Subdivision", "SUBSURF")
        s.levels = subdiv
        s.render_levels = subdiv
    apply_modifiers(obj)
    return obj


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def arch_path(half, drop, radius, steps=8, top=0.0):
    """An upside-down U in the XZ plane hugging the creature's back: down each side, round over the top."""
    pts = [(-half, -drop)]
    for i in range(steps + 1):
        a = math.pi - (math.pi / 2) * i / steps
        pts.append((-half + radius + radius * math.cos(a), -radius + radius * math.sin(a)))
    for i in range(steps + 1):
        a = math.pi / 2 - (math.pi / 2) * i / steps
        pts.append((half - radius + radius * math.cos(a), -radius + radius * math.sin(a)))
    pts.append((half, -drop))
    return [(x, z + top) for x, z in pts]


def sweep(name, path, length, thickness, y=0.0):
    """A slab following `path` (points in XZ, its inside face on the path) and `length` deep along Y."""
    bm = bmesh.new()
    n = len(path)
    rings = []
    for i, (x, z) in enumerate(path):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, n - 1)]
        tx, tz = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(tx, tz) or 1
        nx, nz = -tz / ln, tx / ln  # outward: away from the creature
        ring = []
        for out in (0.0, thickness):
            for dy in (-length / 2, length / 2):
                ring.append(bm.verts.new((x + nx * out, y + dy, z + nz * out)))
        rings.append(ring)  # [in-front, in-back, out-front, out-back]
    for i in range(n - 1):
        r0, r1 = rings[i], rings[i + 1]
        bm.faces.new((r0[2], r1[2], r1[3], r0[3]))  # outside
        bm.faces.new((r0[1], r1[1], r1[0], r0[0]))  # inside
        bm.faces.new((r0[0], r1[0], r1[2], r0[2]))  # front edge
        bm.faces.new((r0[3], r1[3], r1[1], r0[1]))  # back edge
    for ring in (rings[0], rings[-1]):
        bm.faces.new((ring[0], ring[2], ring[3], ring[1]))
    return new_object(name, bm)


def box(name, size, location):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def tube(name, points, radius, closed=False):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 4
    curve.use_fill_caps = True
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1)
    spline.use_cyclic_u = closed
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj.select_set(False)
    return bpy.context.view_layer.objects.active


def rounded_rect(cx, cy, hw, hh, r, steps=6):
    """Points of a rounded rectangle (half sizes hw, hh) around (cx, cy)."""
    pts = []
    for corner, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        start = corner * math.pi / 2
        ox, oy = cx + sx * (hw - r), cy + sy * (hh - r)
        for i in range(steps + 1):
            a = start + (math.pi / 2) * i / steps
            pts.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    return pts


def disc(name, radius, depth, location, axis="X", verts=32):
    rot = (0, math.pi / 2, 0) if axis == "X" else (0, 0, 0)
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=location, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    return obj


# ---------------------------------------------------------------------------------------------------------
# The saddle


def build():
    parts = []

    # Cream underpad: a puffy roll just peeking out around the leather's edges
    pad = sweep("Underpad", arch_path(BODY_HALF + 0.01, DROP + 0.07, 0.3), LENGTH + 0.1, 0.11)
    parts.append(finish(soft(pad, 0.05), "cream"))

    # Brown leather cover over it
    cover = sweep("Cover", arch_path(BODY_HALF + 0.1, DROP, 0.34, top=0.09), LENGTH, 0.08)
    parts.append(finish(soft(cover, 0.03), "leather"))

    # Cushion: a big puffy square with rounded corners, dipped in the middle and rising at the back
    seat = box("Cushion", (1.5, 1.42, 0.34), (0, 0.04, 0.36))
    b = seat.modifiers.new("Bevel", "BEVEL")
    b.width = 0.16
    b.segments = 4
    b.limit_method = "NONE"
    apply_modifiers(seat)
    sub = seat.modifiers.new("Sub", "SUBSURF")
    sub.levels = 2
    apply_modifiers(seat)
    for v in seat.data.vertices:
        if v.co.z > 0.36:
            t = (v.co.y - 0.04) / 0.71
            v.co.z += -0.08 * (1 - t * t) + 0.1 * max(t, 0) ** 2
    parts.append(finish(seat, "cushion"))

    # Thick cream piping hugging the cushion's base
    ring = [(x, y, 0.21) for x, y in rounded_rect(0, 0.04, 0.78, 0.74, 0.24)]
    parts.append(finish(tube("Piping", ring, 0.085, closed=True), "cream"))

    # Back: a curved leather lip rising behind the cushion, with a cream rim
    lip = [(x, 0.8 + 0.06 * (x / 0.75) ** 2, 0.48 - 0.12 * (x / 0.75) ** 2) for x in [i / 8 * 1.5 - 0.75 for i in range(9)]]
    parts.append(finish(tube("BackRest", lip, 0.13), "leather"))
    parts.append(finish(tube("BackRim", [(x, y, z + 0.11) for x, y, z in lip], 0.06), "cream"))

    # Handle in front: an upside-down U
    handle = [(-0.42, -0.64, 0.2)] + [
        (-0.42 + 0.14 + 0.14 * math.cos(math.pi - (math.pi / 2) * i / 6), -0.64, 0.62 + 0.14 * math.sin(math.pi - (math.pi / 2) * i / 6))
        for i in range(7)
    ] + [
        (0.42 - 0.14 + 0.14 * math.cos(math.pi / 2 - (math.pi / 2) * i / 6), -0.64, 0.62 + 0.14 * math.sin(math.pi / 2 - (math.pi / 2) * i / 6))
        for i in range(7)
    ] + [(0.42, -0.64, 0.2)]
    parts.append(finish(tube("Handle", handle, 0.095), "dark"))

    for side in (-1, 1):
        x = side * (BODY_HALF + 0.2)
        # Paw badge: a leather plate with an orange inset, a gold coin, an orange paw
        plate = box("BadgePlate", (0.06, 0.66, 0.54), (x, 0.0, -0.42))
        parts.append(finish(soft(plate, 0.05, 2, 1), "dark"))
        inset = box("BadgeInset", (0.04, 0.54, 0.42), (x + side * 0.02, 0.0, -0.42))
        parts.append(finish(soft(inset, 0.04, 2, 1), "paw"))
        coin = disc("Coin", 0.2, 0.06, (x + side * 0.05, 0.0, -0.42))
        parts.append(finish(soft(coin, 0.015, 2, 0), "gold"))
        px = x + side * 0.09
        parts.append(finish(disc("Paw", 0.075, 0.03, (px, 0.0, -0.47), verts=16), "paw"))
        for dy, dz in ((-0.08, -0.36), (-0.03, -0.33), (0.03, -0.33), (0.08, -0.36)):
            parts.append(finish(disc("Toe", 0.03, 0.03, (px, dy, dz + 0.02), verts=12), "paw"))

        # Straps down the side, front and back, each with a square gold buckle; a stirrup at the front
        for y in (-0.55, 0.55):
            strap = box("Strap", (0.05, 0.16, DROP + 0.2), (x + side * 0.02, y, -(DROP + 0.2) / 2 + 0.05))
            parts.append(finish(soft(strap, 0.02, 2, 0), "dark"))
            loop = [(x + side * 0.06, y + dy, -0.62 + dz) for dy, dz in rounded_rect(0, 0, 0.13, 0.13, 0.04)]
            parts.append(finish(tube("Buckle", loop, 0.03, closed=True), "gold"))
        # Stirrup: a thick rounded triangle hanging under the front strap
        corners = [(0, 0.16), (-0.16, -0.14), (0.16, -0.14)]
        stirrup = []
        for i, (cy, cz) in enumerate(corners):
            ny, nz = corners[(i + 1) % 3]
            for k in range(6):
                t = k / 6
                stirrup.append((x + side * 0.04, -0.55 + cy + (ny - cy) * t, -1.14 + cz + (nz - cz) * t))
        parts.append(finish(soft(tube("Stirrup", stirrup, 0.05, closed=True), 0, 0, 1), "gold"))
        
    return parts


# ---------------------------------------------------------------------------------------------------------
# Renders and export


def setup_render(resolution=520):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.2, 0.22, 0.26, 1)
    bpy.ops.object.light_add(type="SUN", location=(4, -6, 8))
    sun = bpy.context.active_object
    sun.data.energy = 1.7
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(25))
    bpy.ops.object.light_add(type="AREA", location=(-4, -5, 4))
    fill = bpy.context.active_object
    fill.data.energy = 160
    fill.data.size = 6
    fill.rotation_euler = (math.radians(60), 0, math.radians(-40))
    bpy.ops.object.camera_add()
    camera = bpy.context.active_object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 3.4
    scene.camera = camera
    return camera


def render_views(camera):
    from PIL import Image

    target = Vector((0, 0, -0.25))
    views = [("three_quarter", 35, 0.35), ("front", 0, 0.12), ("side", 90, 0.12), ("back", 180, 0.12), ("top", 0, 3.0)]
    images = []
    for view, angle, up in views:
        rad = math.radians(angle)
        direction = Vector((-math.sin(rad), -math.cos(rad), up)).normalized()
        camera.location = target + direction * 12
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(OUT, f"_saddle_{view}.png")
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        images.append(Image.open(path).copy())
        os.remove(path)
    sheet = Image.new("RGB", (sum(i.width for i in images), images[0].height))
    x = 0
    for image in images:
        sheet.paste(image, (x, 0))
        x += image.width
    out = os.path.join(OUT, "Saddle.png")
    sheet.save(out)
    print("wrote", out)


def export_roblox(parts):
    """One mesh per color role, named Saddle__<role>, so the game can color and place them."""
    bpy.ops.object.select_all(action="DESELECT")
    by_role = {}
    for obj in parts:
        by_role.setdefault(obj["role"], []).append(obj)
    joined = []
    for role, objs in by_role.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        obj.name = f"Saddle__{role}"
        joined.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in joined:
        obj.select_set(True)
    out = os.path.join(ROOT, "models", "Saddle.glb")
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True)
    tris = sum(len(o.data.polygons) for o in joined)
    print("wrote", out, "faces", tris)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = build()
    if "roblox" in sys.argv[1:]:
        export_roblox(parts)
        return
    camera = setup_render()
    render_views(camera)


main()
