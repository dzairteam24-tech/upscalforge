"""The Cubeling Ride saddle (art: the riding model sheet): a small pony saddle sitting ON the pony's back. A big
red padded seat (the dominant part) on a thin leather base over a cream fleece, closed by a low pommel with
a wide handle in front and a rounded cantle behind; short padded side flaps lying on the back's rounded
edges under the rider's thighs; a separate girth, the only part going around the body; and big stirrups
right under the rider's feet.

Units are the pony's (art/blender/pony.py), 2 studs each in the game: the body is 1.6 wide (sides at
x = +-0.8, edges rounded by 0.55) and 1.7 tall, the top of the back is z = 0, front is -Y. The saddle is
3.5 studs wide with its flaps, its seat 2.5 wide and 0.4 thick, 2.6 long from pommel to cantle. The rider's
pose (RideClient, pony.py) sets where the hips, hands and feet go (HIP, HANDLE, STIRRUP).

    python art/blender/saddle.py            renders: art/renders/Saddle.png (3/4, front, side, back, top,
                                            bottom) and art/renders/Saddle_exploded.png
    python art/blender/saddle.py roblox     also writes art/models/Saddle.glb, one mesh per color role
                                            (Saddle__cushion, Saddle__cream, Saddle__leather, Saddle__dark,
                                            Saddle__gold), for Studio's Import 3D

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

BODY_HALF = 0.8  # the pony's side, from its middle (its body is 1.6 wide, 2.2 long, 1.7 tall)
BODY_HEIGHT = 1.7  # the body, top of the back to the belly
BODY_RADIUS = 0.55  # the body's rounded edges
# In the game 1 unit is 2 studs: the saddle is 3.5 studs wide with its flaps, its padded seat 2.5 wide, and
# 2.6 long from the front of the pommel to the back of the cantle; the seat is 0.4 thick.
SADDLE_L = 1.3  # pommel to cantle
TREE_W = 1.36  # the leather base the seat sits on, just wider than the seat
SEAT_W = 1.25  # the padded seat: 2.5 studs
SEAT_L = 0.96  # the padded seat between the pommel and the cantle
SEAT_T = 0.2  # its thickness: 0.4 studs
DROOP = 0.04  # how much the base and seat curve down at the sides
FLAP_L = 0.9  # the side flaps, front to back
FLAP_DROP = 0.42  # how far down the body's rounded edge the flaps reach: under the rider's thighs
HIP = 0.1  # the rider's hips above the back: sunk into the seat (its top is about 0.27)
HANDLE = (-0.45, 0.415)  # where the rider's hands hold the handle (y, z), from the rider's pose
STIRRUP = (0.986, -0.36, -0.632)  # where the rider's feet rest (x, y, sole z), from the same pose

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


def back_z(x):
    """The top of the pony's back at x across it: flat in the middle, rounding down to the sides."""
    flat = BODY_HALF - BODY_RADIUS
    ax = min(abs(x), BODY_HALF)
    if ax <= flat:
        return 0.0
    return -BODY_RADIUS + math.sqrt(max(BODY_RADIUS**2 - (ax - flat) ** 2, 0))


def seat_z(x):
    """The saddle's base and seat: nearly flat, curving down a little to the sides."""
    return -DROOP * (x / (TREE_W / 2)) ** 2


def drape(obj, curve=seat_z):
    for v in obj.data.vertices:
        v.co.z += curve(v.co.x + obj.location.x)
    return obj


def flap_path(off, drop, steps=10):
    """One side flap (x > 0), `off` above the body: from under the seat's edge, following the back's rounded
    edge down to `drop` below the back."""
    flat = BODY_HALF - BODY_RADIUS
    r = BODY_RADIUS + off
    a0 = math.acos(min((SEAT_W / 2 - 0.12 - flat) / r, 1))
    a1 = math.asin(max(min((-drop + BODY_RADIUS) / r, 1), -1))
    return [(flat + r * math.cos(a0 + (a1 - a0) * i / steps), -BODY_RADIUS + r * math.sin(a0 + (a1 - a0) * i / steps)) for i in range(steps + 1)]


def build():
    parts = []
    front = -SADDLE_L / 2

    # The base: a thin leather platform ON the back (pommel to cantle), with a cream fleece peeking out
    pad = rounded_box("Fleece", (TREE_W + 0.08, SADDLE_L + 0.06, 0.04), (0, 0, 0.02), 0.02)
    parts.append(tag(drape(pad), "cream", "frame"))
    base = rounded_box("Base", (TREE_W, SADDLE_L, 0.06), (0, 0, 0.07), 0.03)
    parts.append(tag(drape(base), "leather", "frame"))
    top = 0.1  # the base's top in the middle

    # The padded seat: the big part of the saddle, dipped where the rider's pelvis sits, with a cream piping
    sz = top + SEAT_T / 2
    seat = box("Seat", (SEAT_W, SEAT_L, SEAT_T), (0, 0.02, sz))
    soft(seat, 0.08, 4, 2)
    for v in seat.data.vertices:
        if v.co.z > 0:
            t = (v.co.y - 0.02) / (SEAT_L / 2)
            u = v.co.x / (SEAT_W / 2)
            v.co.z -= 0.05 * max(1 - t * t, 0) * max(1 - u * u, 0)
    parts.append(tag(drape(seat), "cushion", "seat"))
    ring = [(x, y, top + 0.02 + seat_z(x)) for x, y in rounded_rect(0, 0.02, SEAT_W / 2 + 0.01, SEAT_L / 2 + 0.01, 0.2)]
    parts.append(tag(tube("Piping", ring, 0.04, closed=True), "cream", "seat"))

    # Pommel and cantle: low rounded rolls closing the seat in front and behind
    py = front + 0.1
    parts.append(tag(drape(rounded_box("Pommel", (0.95, 0.2, 0.2), (0, py, top + 0.11), 0.09)), "leather", "seat"))
    parts.append(tag(tube("PommelRim", [(x, py, top + 0.215 + seat_z(x)) for x in [i / 8 * 0.84 - 0.42 for i in range(9)]], 0.035), "cream", "seat"))
    cy = SADDLE_L / 2 - 0.1
    parts.append(tag(drape(rounded_box("Cantle", (1.15, 0.2, 0.24), (0, cy, top + 0.13), 0.09)), "leather", "seat"))
    parts.append(tag(tube("CantleRim", [(x, cy + 0.02, top + 0.255 + seat_z(x)) for x in [i / 8 * 1.04 - 0.52 for i in range(9)]], 0.04), "cream", "seat"))

    # The handle: one wide rounded bar on the pommel, right in front of the rider's hands
    hy, hz = HANDLE
    half, r = 0.24, 0.07
    handle = [(-half, py, top + 0.18)]
    for i in range(7):
        a = math.pi - (math.pi / 2) * i / 6
        handle.append((-half + r + r * math.cos(a), hy, hz - r + r * math.sin(a)))
    for i in range(7):
        a = math.pi / 2 - (math.pi / 2) * i / 6
        handle.append((half - r + r * math.cos(a), hy, hz - r + r * math.sin(a)))
    handle.append((half, py, top + 0.18))
    parts.append(tag(tube("Handle", handle, 0.045), "dark", "seat"))

    sx, sy, sole = STIRRUP
    for side in (-1, 1):
        # (mirrored to the left side, the path is reversed so its outside stays outside)
        mirror = lambda pts: [(side * x, z) for x, z in (pts if side > 0 else reversed(pts))]  # noqa: E731
        # Side flap: a padded leather panel under the seat's edge, lying on the back's rounded edge where the
        # rider's thigh rests, over a cream lining that shows around it; a small paw emblem
        lining = strap_sweep("FlapLining", mirror(flap_path(0.02, FLAP_DROP + 0.04)), FLAP_L + 0.06, 0.035, 0.18)
        parts.append(tag(soft(lining, 0.012, 2, 1), "cream", "flaps", side))
        flap = strap_sweep("Flap", mirror(flap_path(0.05, FLAP_DROP)), FLAP_L, 0.06, 0.16)
        parts.append(tag(soft(flap, 0.02, 2, 1), "leather", "flaps", side))
        ex, ez = flap_path(0.12, 0.3)[-1]
        coin = disc("Coin", 0.1, 0.035, (side * ex, 0.22, ez))
        coin.rotation_euler = (0, math.atan2(ex - BODY_HALF + BODY_RADIUS, ez + BODY_RADIUS) * side, 0)
        parts.append(tag(soft(coin, 0.01, 2, 0), "gold", "flaps", side))

        # Stirrup: right under the rider's foot, on a leather from under the flap; a big rounded D with a tread
        fx, fz = flap_path(0.08, FLAP_DROP - 0.05)[-1]
        leather = [(side * (fx - 0.04), sy, fz + 0.12), (side * fx, sy, fz), (side * sx, sy, sole + 0.3)]
        parts.append(tag(tube("StirrupLeather", leather, 0.035), "dark", "stirrups", side))
        d = []
        for i in range(9):
            a = math.pi * i / 8
            d.append((side * sx, sy + 0.27 * math.cos(a), sole + 0.08 + 0.22 * math.sin(a)))
        d += [(side * sx, sy - 0.27, sole - 0.02), (side * sx, sy + 0.27, sole - 0.02)]
        stirrup = tube("Stirrup", [d[-1]] + d[:-1], 0.045, closed=True)
        parts.append(tag(soft(stirrup, 0, 0, 1), "gold", "stirrups", side))
        tread = box("Tread", (0.34, 0.56, 0.05), (side * sx, sy, sole - 0.025))
        parts.append(tag(soft(tread, 0.02, 2, 0), "dark", "stirrups", side))

        # Girth buckle on the side of the body, below the flap
        loop = [(side * (BODY_HALF + 0.08), 0.05 + dy, -0.7 + dz) for dy, dz in rounded_rect(0, 0, 0.14, 0.11, 0.035)]
        parts.append(tag(tube("GirthBuckle", loop, 0.03, closed=True), "gold", "girth", side))

    # The girth: the one part that goes around the body, under the belly
    girth = strap_sweep("Girth", body_loop(BODY_HALF + 0.035, BODY_RADIUS + 0.035), 0.24, 0.04, closed=True, y=0.05)
    parts.append(tag(soft(girth, 0.012, 2, 0), "dark", "girth"))
    return parts


EXPLODE = {
    "seat": (0, 0, 0.8),
    "frame": (0, 0, 0.35),
    "flaps": (0.4, 0, 0.0),
    "stirrups": (0.85, 0, -0.35),
    "girth": (0, 0, -1.1),
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
