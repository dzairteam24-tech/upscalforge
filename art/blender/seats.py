"""The floating seats (art: the floating seats sheet): seats the player sits on cross-legged while travelling,
one per zone. For now the meadow's Cloud Seat: a puffy white cloud cushion with a soft lavender underside,
dipped on top where the rider sits, a Cubeling face on its front (eyes with shines, pink blush, a small "w"
mouth), two little cat ears and gold stars.

Units are studs (the game uses them as they are). The seat's bottom is z = 0, its middle x = y = 0, front is
-Y like the creatures. Each seat is exported with a tiny marker part, <Seat>__front, in front of its middle:
the game finds the seat's front from it (Studio's importer may turn a model around).

    python art/blender/seats.py            renders: art/renders/Seats.png (3/4, front, side, back, top)
    python art/blender/seats.py roblox     also writes art/models/Seats.glb: one mesh per color role and seat
                                           (Cloud__body, Cloud__shade, Cloud__eye, Cloud__shine, Cloud__blush,
                                           Cloud__mouth, Cloud__earin, Cloud__star, Cloud__front), for
                                           Studio's Import 3D

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
    "body": (0.97, 0.97, 1.0),
    "shade": (0.72, 0.74, 0.98),
    "eye": (0.03, 0.02, 0.03),
    "shine": (1.0, 1.0, 1.0),
    "blush": (1.0, 0.45, 0.6),
    "mouth": (0.08, 0.03, 0.03),
    "earin": (1.0, 0.55, 0.7),
    "star": (1.0, 0.72, 0.1),
    "front": (1.0, 0.0, 1.0),
}

# The Cloud Seat
WIDTH = 3.6  # side to side
DEPTH = 3.0  # front to back
TOP = 1.15  # the seat's surface in the middle, above its bottom (RideClient's SEAT_TOP)
DIP = 0.2  # how much the top dips where the rider sits
SEAT_SCALE = 1.6  # the game draws the seats this much bigger (SeatModel)

materials = {}


def material(key):
    if key in materials:
        return materials[key]
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*COLORS[key], 1)
    bsdf.inputs["Roughness"].default_value = 0.2 if key in ("eye", "star") else 0.55
    if key == "star":
        bsdf.inputs["Metallic"].default_value = 0.6
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


def join(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def ball(name, radius, location, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=radius, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def tube(name, points, radius):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 4
    curve.use_fill_caps = True
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj.select_set(False)
    return bpy.context.view_layer.objects.active


def blob(name, balls, voxel=0.07, keep=6000):
    """Puffs melted into one smooth cloud: spheres joined, voxel-remeshed, smoothed and thinned out."""
    objs = [ball(f"{name}{i}", r, loc, scale) for i, (r, loc, scale) in enumerate(balls)]
    obj = join(objs)
    obj.name = name
    # (its points in the world's frame, so heights read straight from them)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    mod = obj.modifiers.new("Remesh", "REMESH")
    mod.mode = "VOXEL"
    mod.voxel_size = voxel
    smooth = obj.modifiers.new("Smooth", "SMOOTH")
    smooth.iterations = 6
    smooth.factor = 0.8
    apply_modifiers(obj)
    if len(obj.data.polygons) > keep:
        dec = obj.modifiers.new("Decimate", "DECIMATE")
        dec.ratio = keep / len(obj.data.polygons)
        apply_modifiers(obj)
    return obj


def star(name, center, radius, normal_y, thickness=0.06):
    """A puffy five-point star facing along +-Y."""
    bm = bmesh.new()
    pts = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        r = radius if i % 2 == 0 else radius * 0.45
        pts.append((math.cos(a) * r, math.sin(a) * r))
    front = [bm.verts.new((x, -thickness / 2, z)) for x, z in pts]
    back = [bm.verts.new((x, thickness / 2, z)) for x, z in pts]
    bm.faces.new(front[::-1])
    bm.faces.new(back)
    for i in range(10):
        j = (i + 1) % 10
        bm.faces.new((front[i], front[j], back[j], back[i]))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    b = obj.modifiers.new("Bevel", "BEVEL")
    b.width = thickness * 0.45
    b.segments = 3
    apply_modifiers(obj)
    obj.rotation_euler = (0, 0, 0 if normal_y < 0 else math.pi)
    obj.location = center
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
    return obj


# ---------------------------------------------------------------------------------------------------------
# The Cloud Seat


def cloud():
    parts = []
    hw, hd = WIDTH / 2, DEPTH / 2
    # The cushion: a ring of big puffs round a lower middle, with smaller puffs filling in
    puffs = [(0.95, (0, 0, 0.62), (1.35, 1.2, 0.62))]
    for i in range(10):
        a = 2 * math.pi * i / 10
        x, y = math.cos(a) * (hw - 0.62), math.sin(a) * (hd - 0.58)
        r = 0.62 if i % 2 == 0 else 0.55
        puffs.append((r, (x, y, 0.62 + (0.06 if i % 2 == 0 else 0)), (1, 1, 0.9)))
    body = blob("CloudBody", puffs)
    # The seat's top: flatten what's above it, and dip it in the middle where the rider sits
    for v in body.data.vertices:
        if v.co.z > TOP:
            v.co.z = TOP + (v.co.z - TOP) * 0.35
        rr = math.hypot(v.co.x / (hw * 0.62), v.co.y / (hd * 0.62))
        if v.co.z > TOP - 0.25 and rr < 1:
            v.co.z -= DIP * (1 - rr * rr)
    # Underside: the lower part gets its own lavender mesh (split by height)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    lower = [f for f in bm.faces if f.calc_center_median().z < 0.4]
    shade_mesh = bpy.data.meshes.new("CloudShade")
    sbm = bmesh.new()
    vmap = {}
    for f in lower:
        vs = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = sbm.verts.new(v.co)
            vs.append(vmap[v])
        sbm.faces.new(vs)
    sbm.to_mesh(shade_mesh)
    sbm.free()
    bmesh.ops.delete(bm, geom=lower, context="FACES")
    bm.to_mesh(body.data)
    bm.free()
    shade = bpy.data.objects.new("CloudShade", shade_mesh)
    bpy.context.collection.objects.link(shade)
    parts.append(finish(body, "body"))
    parts.append(finish(shade, "shade"))

    # The face on the front puff
    fy = -hd + 0.05  # the front surface
    fz = 0.62
    for sx in (-1, 1):
        parts.append(finish(ball("Eye", 0.17, (sx * 0.42, fy - 0.02, fz + 0.05), (1, 0.45, 1.2)), "eye"))
        parts.append(finish(ball("Shine", 0.055, (sx * 0.42 - 0.05, fy - 0.1, fz + 0.15), (1, 0.5, 1)), "shine"))
        parts.append(finish(ball("Blush", 0.14, (sx * 0.78, fy + 0.04, fz - 0.12), (1.2, 0.35, 0.7)), "blush"))
    w = [(-0.18, fy - 0.07, fz - 0.12), (-0.09, fy - 0.08, fz - 0.2), (0.0, fy - 0.08, fz - 0.13), (0.09, fy - 0.08, fz - 0.2), (0.18, fy - 0.07, fz - 0.12)]
    parts.append(finish(tube("Mouth", w, 0.028), "mouth"))

    # Two little cat ears on the front top, pink inside
    for sx in (-1, 1):
        bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.3, radius2=0.04, depth=0.5, location=(sx * 0.95, -hd + 0.75, TOP + 0.12))
        ear = bpy.context.active_object
        ear.rotation_euler = (math.radians(-15), math.radians(sx * 12), 0)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        b = ear.modifiers.new("Sub", "SUBSURF")
        b.levels = 1
        apply_modifiers(ear)
        parts.append(finish(ear, "body"))
        bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.17, radius2=0.03, depth=0.3, location=(sx * 0.95, -hd + 0.62, TOP + 0.12))
        inner = bpy.context.active_object
        inner.rotation_euler = (math.radians(-15), math.radians(sx * 12), 0)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        parts.append(finish(inner, "earin"))

    # Gold stars on the sides, facing out, standing a little proud of the puffs
    for a, z, r in ((200, 0.8, 0.21), (-20, 0.78, 0.23), (-60, 1.0, 0.16), (130, 0.95, 0.16)):
        d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
        at = Vector((d.x * (hw - 0.02), d.y * (hd - 0.02), z))
        s = star("Star", (0, 0, 0), r, -1)
        s.rotation_euler = (0, 0, math.atan2(d.x, -d.y))
        s.location = at
        bpy.context.view_layer.objects.active = s
        bpy.ops.object.select_all(action="DESELECT")
        s.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
        parts.append(finish(s, "star"))

    # The front marker: a tiny box in front of the middle (the game hides it)
    bpy.ops.mesh.primitive_cube_add(size=0.05, location=(0, -hd - 0.3, 0.05))
    parts.append(finish(bpy.context.active_object, "front"))
    return parts


# ---------------------------------------------------------------------------------------------------------
# Render and export


def setup_render(resolution=600):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.72, 0.8, 0.95, 1)
    bpy.ops.object.light_add(type="SUN", location=(4, -6, 8))
    sun = bpy.context.active_object
    sun.data.energy = 2.4
    sun.rotation_euler = (math.radians(45), math.radians(10), math.radians(25))
    bpy.ops.object.light_add(type="AREA", location=(-4, -5, 4))
    fill = bpy.context.active_object
    fill.data.energy = 250
    fill.data.size = 8
    fill.rotation_euler = (math.radians(60), 0, math.radians(-40))
    bpy.ops.object.camera_add()
    camera = bpy.context.active_object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 4.8
    scene.camera = camera
    return camera


def render_views(camera, parts, name="Seats", target=Vector((0, 0, 0.7))):
    from PIL import Image

    for obj in parts:
        if obj["role"] == "front":
            obj.hide_render = True
    views = [("three_quarter", 35, 0.35), ("front", 0, 0.08), ("side", 90, 0.08), ("back", 180, 0.12), ("top", 0, 3.0)]
    images = []
    for view, angle, up in views:
        rad = math.radians(angle)
        direction = Vector((-math.sin(rad), -math.cos(rad), up)).normalized()
        camera.location = target + direction * 12
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(OUT, f"_seat_{view}.png")
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        images.append(Image.open(path).copy())
        os.remove(path)
    sheet = Image.new("RGB", (sum(i.width for i in images), images[0].height))
    x = 0
    for image in images:
        sheet.paste(image, (x, 0))
        x += image.width
    out = os.path.join(OUT, name + ".png")
    sheet.save(out)
    print("wrote", out)


def add_rider(path):
    """A rider from a JSON list of blocks in the game's frame for the seat (studs, Y up, front -Z, origin on
    the ground under the seat's middle): a standard R15 rig posed by the game's own solver (SeatPose and
    RideIK, as RideClient does it), so the render shows what the game does."""
    import json

    from mathutils import Matrix

    # game (x, y, z) -> Blender (-x, z, y), and the game's seat is drawn SEAT_SCALE bigger (SeatModel)
    shrink = 1 / SEAT_SCALE
    turn = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))
    parts = []
    for block in json.load(open(path))["parts"]:
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.active_object
        obj.scale = [v * shrink for v in block["s"]]
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        bevel = obj.modifiers.new("Bevel", "BEVEL")
        bevel.width = 0.05
        bevel.segments = 2
        r = block["r"]  # rows: the block's X, Y and Z axes
        rot = Matrix(((r[0], r[3], r[6]), (r[1], r[4], r[7]), (r[2], r[5], r[8])))
        obj.matrix_world = Matrix.Translation(turn @ Vector(block["p"]) * shrink) @ (turn @ rot @ turn.transposed()).to_4x4()
        key = "rider_" + "_".join(f"{c:.2f}" for c in block["c"])
        COLORS.setdefault(key, tuple(c**2.2 for c in block["c"]))
        finish(obj, key)
        parts.append(obj)
    return parts


def export_roblox(seats):
    """One mesh per color role and seat, named <Seat>__<role> (the mesh too: Studio names parts after it)."""
    joined = []
    for seat, parts in seats.items():
        by_role = {}
        for obj in parts:
            by_role.setdefault(obj["role"], []).append(obj)
        for role, objs in by_role.items():
            obj = join(objs) if len(objs) > 1 else objs[0]
            obj.name = f"{seat}__{role}"
            obj.data.name = obj.name
            joined.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in joined:
        obj.select_set(True)
    out = os.path.join(ROOT, "models", "Seats.glb")
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True)
    for obj in joined:
        print(obj.name, "faces", len(obj.data.polygons))
    print("wrote", out)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    seats = {"Cloud": cloud()}
    if "roblox" in sys.argv[1:]:
        export_roblox(seats)
        return
    camera = setup_render()
    rider = os.environ.get("RIDER")
    if rider:
        add_rider(rider)
        camera.data.ortho_scale = float(os.environ.get("ZOOM", 7.5))
        render_views(camera, seats["Cloud"], "SeatRide", Vector((0, 0, float(os.environ.get("AIM", 2.3)))))
        return
    render_views(camera, seats["Cloud"])


main()
