"""The town shops' logos (art: the user's emblem sheet): a thick round badge per shop with one raised symbol,
in a few flat colors, made to sit on the buildings' plaques.

Units are studs. Each badge faces the front (-Y), its middle at x = z = 0, radius 1.

    python art/blender/logos.py            renders OUT/Logos.png
    python art/blender/logos.py roblox     writes art/models/Logos.glb (parts named Logo<Shop>__<role>)
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402, I001 (bmesh only exists once bpy is loaded)
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

import seatkit  # noqa: E402
from seatkit import ball, cylinder, finish, torus, tube  # noqa: E402

ROOT = os.path.join(HERE, "..")
OUT = os.environ.get("OUT", ROOT)


def srgb(r, g, b):
    return tuple((c / 255) ** 2.2 for c in (r, g, b))


DEPTH = 0.34  # the badge's thickness
FRONT = -DEPTH / 2  # its face


def at(u, v, dy=0.0):
    """A point on the badge's face: u right, v up, dy out of the face (toward the front)."""
    return (u, FRONT - dy, v)


def facing(obj):
    """Turns a part made along Z to face the front, and bakes it."""
    obj.rotation_euler = (math.pi / 2, 0, 0)
    return seatkit.bake(obj)


def badge(name, radius, role, bevel=0.1):
    """The badge's body: a thick disc with rounded edges."""
    return finish(facing(cylinder(name, radius, DEPTH, (0, 0, 0), vertices=64, bevel=bevel)), role)


def pad(name, r, u, v, sx, sz, role, height=0.13, dy=0.0):
    """A soft raised blob on the face."""
    return finish(ball(name, r, at(u, v, dy), (sx, height / r, sz)), role)


def arc(radius, a0, a1, steps=20):
    return [(math.cos(a0 + (a1 - a0) * i / steps) * radius, math.sin(a0 + (a1 - a0) * i / steps) * radius) for i in range(steps + 1)]


def flat_tube(name, pts, r, role, dy=0.12, squash=0.55):
    obj = tube(name, [(u, 0, v) for u, v in pts], r)
    obj.scale = (1, squash, 1)
    seatkit.bake(obj)
    obj.location = (0, FRONT - dy * 0.6, 0)
    return finish(seatkit.bake(obj), role)


def arrow_head(name, u, v, angle, size, role, depth=0.22):
    """A rounded triangle on the face, its back edge at (u, v), pointing along `angle`."""
    d = Vector((math.cos(angle), math.sin(angle)))
    n = Vector((-d.y, d.x))
    corners = [d * size * 1.05, n * size * 0.85, -n * size * 0.85]
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((u + c.x, FRONT, v + c.y)) for c in corners])
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    bmesh.ops.translate(bm, verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)], vec=(0, -depth, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = 0.06
    mod.segments = 4
    seatkit.apply_modifiers(obj)
    return finish(obj, role)


def cut_above(obj, z):
    """Cuts a part flat at height z, keeping what's below and closing the top."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z), plane_no=(0, 0, 1), clear_outer=True)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    bmesh.ops.edgeloop_fill(bm, edges=edges)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def shop():
    """A gold coin with a raised rim, a deeper gold face and a pale yellow paw print."""
    parts = [badge("Coin", 1.0, "rim")]
    parts.append(finish(_at_face(torus("Rim", 0.86, 0.09, (0, 0, 0)), 0.02), "rim"))
    parts.append(finish(_at_face(cylinder("Face", 0.8, 0.04, (0, 0, 0), vertices=64, bevel=0.01), 0.0), "face"))
    parts.append(pad("Pad", 0.34, 0.0, -0.22, 1.15, 0.85, "paw"))
    for u, v, r in ((-0.48, 0.12, 0.15), (-0.2, 0.38, 0.16), (0.14, 0.38, 0.16), (0.44, 0.12, 0.15)):
        parts.append(pad("Toe", r, u, v, 0.95, 1.18, "paw"))
    return parts


def trade():
    """A cream badge with two chunky arrows chasing round: green above, red below."""
    parts = [badge("Badge", 1.0, "badge")]
    r = 0.5
    for name, start, end, role in (("Top", 205, 85, "green"), ("Bottom", 25, -95, "red")):
        parts.append(flat_tube("Arrow" + name, arc(r, math.radians(start), math.radians(end)), 0.19, role))
        e = math.radians(end)
        parts.append(arrow_head("Head" + name, math.cos(e) * r, math.sin(e) * r, e - math.pi / 2, 0.33, role))
    return parts


def potion():
    """A blue badge with a round glass flask of purple potion and a cork."""
    parts = [badge("Badge", 1.0, "badge")]
    flask = ball("Flask", 0.46, at(0, -0.14, 0.08), (1, 0.4, 1))
    parts.append(finish(flask, "glass"))
    neck = cylinder("Neck", 0.17, 0.32, at(0, 0.36, 0.1), vertices=32, bevel=0.04)
    neck.scale = (1, 0.75, 1)
    parts.append(finish(seatkit.bake(neck), "glass"))
    lip = torus("Lip", 0.2, 0.06, at(0, 0.5, 0.1))
    lip.scale = (1, 0.85, 1)
    parts.append(finish(seatkit.bake(lip), "glass"))
    cork = cylinder("Cork", 0.15, 0.22, at(0, 0.62, 0.1), vertices=32, bevel=0.05)
    parts.append(finish(cork, "cork"))
    liquid = ball("Liquid", 0.39, at(0, -0.16, 0.16), (1, 0.4, 1))
    seatkit.bake(liquid)
    parts.append(finish(cut_above(liquid, -0.02), "potion"))
    for u, v, r in ((-0.14, -0.24, 0.07), (0.1, -0.36, 0.05)):
        parts.append(pad("Bubble", r, u, v, 1, 1, "bubble", height=0.05, dy=0.3))
    return parts


def _at_face(obj, dy):
    obj.rotation_euler = (math.pi / 2, 0, 0)
    seatkit.bake(obj)
    obj.location = (0, FRONT - dy, 0)
    return seatkit.bake(obj)


LOGOS = [
    ("Shop", shop, {"rim": srgb(253, 198, 30), "face": srgb(250, 176, 20), "paw": srgb(255, 214, 90)}),
    ("Trade", trade, {"badge": srgb(245, 236, 220), "green": srgb(100, 215, 150), "red": srgb(245, 90, 85)}),
    ("Potion", potion, {"badge": srgb(50, 160, 240), "glass": srgb(228, 230, 248), "potion": srgb(160, 60, 225), "bubble": srgb(205, 130, 245), "cork": srgb(175, 115, 65)}),
]


def render(groups):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 40
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 560
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    bpy.ops.object.light_add(type="SUN")
    sun = bpy.context.active_object
    sun.rotation_euler = (math.radians(55), 0, math.radians(-25))
    sun.data.energy = 2.6
    bpy.ops.object.camera_add()
    camera = bpy.context.active_object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 7.2
    scene.camera = camera
    for i, parts in enumerate(groups):
        for obj in parts:
            obj.location.x += (i - 1) * 2.5
    camera.location = Vector((0.3, -1, 0.08)).normalized() * 50
    camera.rotation_euler = (-camera.location).to_track_quat("-Z", "Y").to_euler()
    out = os.path.join(OUT, "Logos.png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("wrote", out)


def export(groups):
    joined = []
    for (name, _, _), parts in zip(LOGOS, groups):
        by_role = {}
        for obj in parts:
            by_role.setdefault(obj["role"], []).append(obj)
        for role, objs in by_role.items():
            obj = seatkit.join(objs) if len(objs) > 1 else objs[0]
            obj.name = obj.data.name = f"Logo{name}__{role}"
            joined.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in joined:
        obj.select_set(True)
    out = os.path.join(ROOT, "models", "Logos.glb")
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True)
    print("wrote", out)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    groups = []
    for name, build, colors in LOGOS:
        seatkit.current["seat"] = "Logo" + name
        seatkit.current["colors"] = colors
        groups.append(build())
    if "roblox" in sys.argv[1:]:
        export(groups)
    else:
        render(groups)


main()
