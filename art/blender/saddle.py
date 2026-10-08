"""The Cubeling Ride saddle (art: the Cubeling saddle spec), made around the pony's rounded cube body: a soft
orange seat with cream piping on a low leather base, a raised front pommel with a small round handle, a
raised rear cantle, two big leather side panels that follow the body's rounded top down its sides (over a
cream pad peeking out), a wide girth strap around the body under them with gold buckles, a paw emblem on
each panel and two small stirrups where the rider's feet rest.

Units are the pony's (art/blender/pony.py): the body is 2 wide (sides at x = +-1, top corners rounded by
about 0.5) and 1.65 tall, the top of the back is z = 0, front is -Y. The game scales it with the body.

    python art/blender/saddle.py            renders: art/renders/Saddle.png (3/4, front, side, back, top,
                                            bottom) and art/renders/Saddle_exploded.png
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

BODY_HALF = 0.8  # the body's side, from its middle
BODY_HEIGHT = 1.7  # the body, top of the back to the belly
BODY_RADIUS = 0.55  # the body's rounded edges
LENGTH = 1.15  # the side panels, front to back (about half the body's 2.2)
DROP = 1.05  # how far the side panels go down the sides (about 60%)
SEAT_W = 1.0  # the seat: as wide as the rider's hips, about 60% of the body's width
SEAT_L = 0.9  # the seat, front to back
DROOP = 0.07  # how much the seat and its frame curve down at the sides, following the back
FIT = 0.03  # how far the leather stands off the body: it hugs it
STIRRUP = (-0.36, -0.58)  # where the rider's feet rest (y, z), from the rider's pose in the game
HANDLE = (-0.45, 0.39)  # where the rider's hands hold the handle (y, z), from the same pose

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


def arch_path(half, drop, radius, steps=6, top=0.0):
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


def strap_sweep(name, path, length, thickness, corner=0.0, closed=False, y=0.0):
    """A slab following `path` (points in XZ, its inside face on the path), `length` deep along Y. With
    `corner`, its two ends get rounded corners that big; `closed` joins the end to the start (a loop)."""
    bm = bmesh.new()
    n = len(path)
    dist = [0.0]
    for i in range(1, n):
        dist.append(dist[-1] + math.hypot(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]))
    rings = []
    for i, (x, z) in enumerate(path):
        a = path[(i - 1) % n] if closed else path[max(i - 1, 0)]
        b = path[(i + 1) % n] if closed else path[min(i + 1, n - 1)]
        tx, tz = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(tx, tz) or 1
        nx, nz = -tz / ln, tx / ln  # outward: away from the body
        half = length / 2
        if corner > 0 and not closed:
            m = min(dist[i], dist[-1] - dist[i])
            if m < corner:
                half = length / 2 - corner + math.sqrt(max(corner * corner - (corner - m) ** 2, 0))
        ring = []
        for out in (0.0, thickness):
            for dy in (-half, half):
                ring.append(bm.verts.new((x + nx * out, y + dy, z + nz * out)))
        rings.append(ring)  # [in-front, in-back, out-front, out-back]
    count = n if closed else n - 1
    for i in range(count):
        r0, r1 = rings[i], rings[(i + 1) % n]
        bm.faces.new((r0[2], r1[2], r1[3], r0[3]))
        bm.faces.new((r0[1], r1[1], r1[0], r0[0]))
        bm.faces.new((r0[0], r1[0], r1[2], r0[2]))
        bm.faces.new((r0[3], r1[3], r1[1], r0[1]))
    if not closed:
        for ring in (rings[0], rings[-1]):
            bm.faces.new((ring[0], ring[2], ring[3], ring[1]))
    return new_object(name, bm)


def body_loop(half, radius, steps=8):
    """The body's cross-section (XZ) as a loop: up the left side, over the back, down the right, under."""
    pts = []
    centers = ((-half + radius, -radius), (half - radius, -radius), (half - radius, -BODY_HEIGHT + radius), (-half + radius, -BODY_HEIGHT + radius))
    starts = (math.pi, math.pi / 2, 0.0, -math.pi / 2)
    for (cx, cz), start in zip(centers, starts):
        for i in range(steps + 1):
            a = start - (math.pi / 2) * i / steps
            pts.append((cx + radius * math.cos(a), cz + radius * math.sin(a)))
    return pts


def rounded_box(name, size, location, bevel, subdiv=1):
    return soft(box(name, size, location), bevel, 3, subdiv)


def tag(obj, role, group, side=0):
    finish(obj, role)
    obj["group"] = group
    obj["side"] = side
    return obj


def drape(obj, half=SEAT_W / 2 + 0.05):
    """Curves a flat piece down at the sides by DROOP, so it follows the rounded back."""
    for v in obj.data.vertices:
        x = v.co.x + obj.location.x
        v.co.z -= DROOP * min((x / half) ** 2, 1.6)
    return obj


def build():
    parts = []
    front, rear = -LENGTH / 2, LENGTH / 2

    # Cream pad peeking out around the side panels, and the panels: one piece of leather over the back and
    # down each side, hugging the body's rounded top, with rounded bottom corners
    pad = strap_sweep("Pad", arch_path(BODY_HALF + 0.005, DROP + 0.16, BODY_RADIUS + 0.005), LENGTH + 0.1, 0.045, 0.26)
    parts.append(tag(soft(pad, 0.018, 2, 1), "cream", "pad"))
    panels = strap_sweep("Panels", arch_path(BODY_HALF + FIT + 0.01, DROP, BODY_RADIUS + FIT), LENGTH, 0.06, 0.24)
    parts.append(tag(soft(panels, 0.025, 2, 1), "leather", "panels"))
    top = FIT + 0.07  # the panels' top surface on the back

    # Low leather base sunk into the panels, the soft seat on it (dipped in the middle) and its piping
    parts.append(tag(drape(rounded_box("Base", (SEAT_W + 0.2, SEAT_L + 0.2, 0.08), (0, 0.0, top + 0.02), 0.04)), "dark", "frame"))
    # Small straps holding the seat to the frame at its corners
    for sx in (-1, 1):
        for sy2 in (-1, 1):
            tab = rounded_box("Tab", (0.1, 0.13, 0.12), (sx * (SEAT_W / 2 + 0.05), sy2 * (SEAT_L / 2 - 0.08), top + 0.06), 0.03, 0)
            parts.append(tag(drape(tab), "leather", "frame"))
    seat_z = top + 0.07
    seat = box("Seat", (SEAT_W, SEAT_L, 0.14), (0, 0.02, seat_z))
    soft(seat, 0.08, 4, 2)
    for v in seat.data.vertices:
        if v.co.z > seat_z:
            t = (v.co.y - 0.02) / (SEAT_L / 2)
            v.co.z -= 0.05 * max(1 - t * t, 0) * max(1 - (v.co.x / (SEAT_W / 2)) ** 2, 0)
    parts.append(tag(drape(seat), "cushion", "seat"))
    ring = [(x, y, seat_z - 0.06 - DROOP * (x / (SEAT_W / 2)) ** 2) for x, y in rounded_rect(0, 0.02, SEAT_W / 2 + 0.015, SEAT_L / 2 + 0.015, 0.16)]
    parts.append(tag(tube("Piping", ring, 0.042, closed=True), "cream", "seat"))

    # Raised front pommel with a cream rim and a ring handle; raised rear cantle with a rim
    py = front + 0.04
    parts.append(tag(drape(rounded_box("Pommel", (0.7, 0.17, 0.2), (0, py, top + 0.1), 0.07)), "leather", "frame"))
    parts.append(tag(tube("PommelRim", [(x / 8 * 0.6 - 0.3, py, top + 0.205 - DROOP * ((x / 8 * 0.6 - 0.3) / 0.35) ** 2) for x in range(9)], 0.038), "cream", "frame"))
    hy, hz = HANDLE
    # Handle: a round ring standing on the pommel, held with both hands
    ring = [(0.11 * math.cos(2 * math.pi * i / 20), py, hz + 0.11 * math.sin(2 * math.pi * i / 20)) for i in range(20)]
    parts.append(tag(tube("Handle", ring, 0.045, closed=True), "dark", "frame"))
    cy = rear - 0.06
    cantle = drape(rounded_box("Cantle", (0.98, 0.17, 0.3), (0, cy, top + 0.14), 0.08))
    cantle.rotation_euler = (math.radians(-14), 0, 0)
    parts.append(tag(cantle, "leather", "frame"))
    rim = [(x, cy + 0.06 + 0.03 * (x / 0.47) ** 2, top + 0.3 - (0.04 + DROOP) * (x / 0.47) ** 2) for x in [i / 8 * 0.94 - 0.47 for i in range(9)]]
    parts.append(tag(tube("CantleRim", rim, 0.045), "cream", "frame"))

    # Girth strap all the way around the body, under the panels
    girth = strap_sweep("Girth", body_loop(BODY_HALF + 0.035, BODY_RADIUS + 0.035), 0.24, 0.04, closed=True)
    parts.append(tag(soft(girth, 0.012, 2, 0), "dark", "girth"))

    sy, sz = STIRRUP
    for side in (-1, 1):
        x = side * (BODY_HALF + FIT + 0.08)
        out = side * (BODY_HALF + FIT + 0.2)  # the stirrups hang out from the body, under the feet
        # Girth buckle just under the panel
        loop = [(side * (BODY_HALF + 0.09), dy, -DROP - 0.14 + dz) for dy, dz in rounded_rect(0, 0, 0.16, 0.14, 0.04)]
        parts.append(tag(tube("GirthBuckle", loop, 0.034, closed=True), "gold", "buckles", side))
        tongue = [(side * (BODY_HALF + 0.1), 0.0, -DROP - 0.02), (side * (BODY_HALF + 0.1), 0.0, -DROP - 0.2)]
        parts.append(tag(tube("GirthTongue", tongue, 0.022), "gold", "buckles", side))

        # Paw emblem on the panel, behind the stirrup leather: a gold coin with an orange paw
        ey, ez = 0.14, -0.36
        coin = disc("Coin", 0.17, 0.045, (x + side * 0.005, ey, ez))
        parts.append(tag(soft(coin, 0.012, 2, 0), "gold", "emblem", side))
        px = x + side * 0.035
        parts.append(tag(disc("Paw", 0.065, 0.02, (px, ey, ez - 0.045), verts=16), "paw", "emblem", side))
        for dy, dz in ((-0.068, 0.023), (-0.025, 0.052), (0.025, 0.052), (0.068, 0.023)):
            parts.append(tag(disc("Toe", 0.026, 0.02, (px, ey + dy, ez + dz), verts=12), "paw", "emblem", side))

        # Stirrup leather from the top of the panel down to the stirrup, with a small buckle; the stirrup:
        # a rounded triangle with a tread, right where the rider's foot rests
        leather_top = -0.05
        leather_bottom = sz + 0.12
        strap = tube("StirrupLeather", [(x, sy, leather_top), (out, sy, leather_bottom)], 0.035)
        parts.append(tag(strap, "dark", "stirrups", side))

        # Knee roll: a puffy cream pad at the front of the flap, where the rider's thigh rests
        roll = tube("KneeRoll", [(side * (BODY_HALF - 0.12), -LENGTH / 2 + 0.12, 0.06), (side * (BODY_HALF + FIT + 0.06), -LENGTH / 2 + 0.1, -0.3), (side * (BODY_HALF + FIT + 0.08), -LENGTH / 2 + 0.1, -0.55)], 0.075)
        parts.append(tag(roll, "cream", "panels", side))
        loop = [(x + side * 0.03, sy + dy, -0.2 + dz) for dy, dz in rounded_rect(0, 0, 0.075, 0.065, 0.02)]
        parts.append(tag(tube("StirrupBuckle", loop, 0.02, closed=True), "gold", "buckles", side))
        corners = [(0, sz + 0.2), (-0.17, sz - 0.08), (0.17, sz - 0.08)]
        stirrup = []
        for i, (cy2, cz) in enumerate(corners):
            ny, nz = corners[(i + 1) % 3]
            for k in range(6):
                t = k / 6
                stirrup.append((out, sy + cy2 + (ny - cy2) * t, cz + (nz - cz) * t))
        parts.append(tag(soft(tube("Stirrup", stirrup, 0.045, closed=True), 0, 0, 1), "gold", "stirrups", side))
        tread = box("Tread", (0.16, 0.28, 0.045), (out + side * 0.03, sy, sz - 0.08))
        parts.append(tag(soft(tread, 0.02, 2, 0), "dark", "stirrups", side))
    return parts


EXPLODE = {
    "seat": (0, 0, 1.3),
    "frame": (0, 0, 0.7),
    "panels": (0, 0, 0.0),
    "pad": (0, 0, -0.45),
    "girth": (0, 0, -1.3),
    "buckles": (0.55, 0, -0.2),
    "emblem": (0.35, 0, 0.1),
    "stirrups": (0.85, 0, -0.5),
}


def explode(parts):
    for obj in parts:
        dx, dy, dz = EXPLODE[obj["group"]]
        side = obj["side"] or 1
        obj.location = obj.location + Vector((dx * side, dy, dz))


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


def render_views(camera, name="Saddle", views=None):
    from PIL import Image

    target = Vector((0, 0, -0.25))
    views = views or [("three_quarter", 35, 0.35), ("front", 0, 0.12), ("side", 90, 0.12), ("back", 180, 0.12), ("top", 0, 3.0), ("bottom", 0, -3.0)]
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
    out = os.path.join(OUT, f"{name}.png")
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
    explode(parts)
    camera.data.ortho_scale = 5.6
    render_views(camera, "Saddle_exploded", [("three_quarter", 35, 0.3), ("front", 0, 0.08)])


main()
