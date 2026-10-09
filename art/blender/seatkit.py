"""Shared pieces for the floating seats (art/blender/seats.py and the designs in seat_designs/).

Units are studs as the model is made (the game draws seats SEAT_SCALE bigger). A seat stands on z = 0 with its
middle at x = y = 0 and its front toward -Y. `finish(obj, role)` colors a part by its role from the design's
COLORS (seats.py sets them before building each design): one Roblox part per role.
"""

import math

import bpy  # noqa: I001 (bmesh only exists once bpy is loaded)
import bmesh
from mathutils import Matrix, Vector

SEAT_SCALE = 1.6  # the game draws the seats this much bigger (SeatModel)

# The design being built: its name and colors (linear RGB per role), set by seats.py
current = {"seat": "", "colors": {}}
materials = {}
SHINY = ("eye", "star", "gem", "gold", "pearl", "crystal", "glass", "ice")


def material(role):
    key = current["seat"] + "_" + role
    if key in materials:
        return materials[key]
    color = current["colors"].get(role, (1.0, 0.0, 1.0))
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = 0.2 if role in SHINY else 0.55
    if role in ("star", "gold"):
        bsdf.inputs["Metallic"].default_value = 0.6
    if role in current.get("glow", ()):
        bsdf.inputs["Emission Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Strength"].default_value = 1.5
    materials[key] = mat
    return mat


def finish(obj, role):
    obj.data.materials.clear()
    obj.data.materials.append(material(role))
    obj["role"] = role
    obj["seat"] = current["seat"]
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


def placed(obj, matrix):
    """Moves an object by a matrix and bakes it in."""
    obj.matrix_world = matrix @ obj.matrix_world
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def petal_matrix(angle, radius, z, tilt):
    """A petal's frame: its +Y pointing out along `angle` (degrees, -90 = the front), its outer end raised."""
    a = math.radians(angle)
    return (
        Matrix.Translation((math.cos(a) * radius, math.sin(a) * radius, z))
        @ Matrix.Rotation(a - math.pi / 2, 4, "Z")
        @ Matrix.Rotation(math.radians(tilt), 4, "X")
    )


def bake(obj):
    """Bakes an object's location, rotation and scale into its points."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def box(name, size, location, bevel=0.05, segments=3):
    """A box with rounded edges."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bake(obj)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        apply_modifiers(obj)
    return obj


def cylinder(name, radius, depth, location, vertices=32, bevel=0.04):
    """An upright cylinder (along Z) with rounded edges."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    obj = bpy.context.active_object
    obj.name = name
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        apply_modifiers(obj)
    return obj


def cone(name, radius1, radius2, depth, location, vertices=24):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2, depth=depth, location=location)
    obj = bpy.context.active_object
    obj.name = name
    return obj


def torus(name, major, minor, location, segments=48):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=segments, minor_segments=16, location=location)
    obj = bpy.context.active_object
    obj.name = name
    return obj


def subdivide(obj, levels=1):
    mod = obj.modifiers.new("Sub", "SUBSURF")
    mod.levels = levels
    apply_modifiers(obj)
    return obj


def split_below(obj, z, name):
    """Splits off the faces whose middle is below height z into a new object (e.g. a darker underside)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    lower = [f for f in bm.faces if f.calc_center_median().z < z]
    mesh = bpy.data.meshes.new(name)
    sbm = bmesh.new()
    vmap = {}
    for f in lower:
        vs = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = sbm.verts.new(v.co)
            vs.append(vmap[v])
        sbm.faces.new(vs)
    sbm.to_mesh(mesh)
    sbm.free()
    bmesh.ops.delete(bm, geom=lower, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    part = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(part)
    return part


def face(frame, size=1.0, mouth="smile"):
    """A Cubeling face (eyes with shines, pink blush, a small mouth) on a surface. `frame` is a Matrix whose
    origin is the face's middle on the surface, its -Y pointing out of the surface and +Z up the face (so
    `Matrix.Translation(p)` alone is a face on a front surface facing -Y). Returns the parts, colored
    eye / shine / blush / mouth."""
    s = size
    parts = []
    for sx in (-1, 1):
        parts.append(finish(placed(ball("Eye", 0.13 * s, (sx * 0.3 * s, -0.02 * s, 0.05 * s), (1, 0.45, 1.25)), frame), "eye"))
        parts.append(finish(placed(ball("Shine", 0.042 * s, (sx * 0.3 * s - 0.04 * s, -0.08 * s, 0.13 * s), (1, 0.5, 1)), frame), "shine"))
        parts.append(finish(placed(ball("Blush", 0.1 * s, (sx * 0.56 * s, 0.02 * s, -0.1 * s), (1.25, 0.35, 0.7)), frame), "blush"))
    if mouth == "w":
        pts = [(-0.14, -0.06, -0.09), (-0.07, -0.065, -0.15), (0.0, -0.065, -0.1), (0.07, -0.065, -0.15), (0.14, -0.06, -0.09)]
    else:
        pts = [(-0.1, -0.06, -0.08), (-0.05, -0.065, -0.13), (0.0, -0.065, -0.145), (0.05, -0.065, -0.13), (0.1, -0.06, -0.08)]
    parts.append(finish(placed(tube("Mouth", [(x * s, y * s, z * s) for x, y, z in pts], 0.022 * s), frame), "mouth"))
    return parts


def front_marker(depth):
    """The tiny box in front of the seat's middle that tells the game where its front is (hidden in game)."""
    bpy.ops.mesh.primitive_cube_add(size=0.05, location=(0, -depth / 2 - 0.3, 0.05))
    return finish(bpy.context.active_object, "front")


FACE_COLORS = {
    "eye": (0.03, 0.02, 0.03),
    "shine": (1.0, 1.0, 1.0),
    "blush": (1.0, 0.45, 0.6),
    "mouth": (0.08, 0.03, 0.03),
    "front": (1.0, 0.0, 1.0),
}
