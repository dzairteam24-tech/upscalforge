"""The Cubeling Ride's pony body (art: the Cubeling pony model sheet from ChatGPT): a chunky rounded body
with a cream belly patch, four rounded legs with brown hooves, a curled fluffy tail with a cream tip and a
mane of three chunks behind the head. The head is the rider's own creature (the game puts it on the front
of the body), so every species gets a pony body in its color.

Units: the body is 2 wide (x = +-1) like the saddle's creature, the ground is z = 0, the top of the back
is at z = BACK. Front is -Y, like the creatures.

    python art/blender/pony.py              renders: art/renders/Pony.png (front, side, back, 3/4, top),
                                            with the Kitty's head (art/models/Cubelings_Roblox.glb) and the saddle
    python art/blender/pony.py roblox       also writes art/models/Pony.glb: Pony__body, Pony__cream,
                                            Pony__mane, and per leg Pony__leg__legFL... and
                                            Pony__hoof__legFL..., for Studio's Import 3D

Needs Python with bpy (Blender 4.2+) and pillow.
"""

import math
import os
import sys

import bpy  # noqa: I001 (bmesh only exists once bpy is loaded)
from mathutils import Vector

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.environ.get("OUT", ROOT)

# Kitty's colors, for the render (the game colors the body like the creature)
COLORS = {
    "body": (0.92, 0.38, 0.1),
    "cream": (0.95, 0.78, 0.55),
    "mane": (0.8, 0.22, 0.04),
    "hoof": (0.2, 0.08, 0.03),
}

HALF = 1.0  # the body's side, from its middle
LENGTH = 3.0  # the body, front to back
BACK = 3.0  # top of the back above the ground
BELLY = 1.35  # bottom of the body above the ground
LEG_X = 0.58
LEG_Y = 1.0
HOOF = 0.32
HEAD_WIDTH = 1.8  # the creature's head, for the render; the game uses the same numbers (RideModel)
HEAD_Y = -1.4
HEAD_BOTTOM = 2.45

materials = {}


def material(key):
    if key in materials:
        return materials[key]
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*COLORS[key], 1)
    bsdf.inputs["Roughness"].default_value = 0.4
    bsdf.inputs["Coat Weight"].default_value = 0.25
    materials[key] = mat
    return mat


def finish(obj, key, name=None):
    obj.data.materials.clear()
    obj.data.materials.append(material(key))
    obj["role"] = name or key
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def soft(obj, bevel, segments=3, subdiv=1):
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


def box(name, size, location):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def ball(name, radius, location, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=radius, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def post(name, bottom, top, r_bottom, r_top, x, y):
    """A rounded post: a cylinder from z = bottom to z = top, a little wider at the bottom."""
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=r_bottom, radius2=r_top, depth=top - bottom, location=(x, y, (top + bottom) / 2))
    obj = bpy.context.active_object
    obj.name = name
    return obj


def join(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


# ---------------------------------------------------------------------------------------------------------
# The pony


def build():
    parts = []

    # Body: a chunky rounded box
    height = BACK - BELLY
    body = box("Body", (HALF * 2, LENGTH, height), (0, 0, BELLY + height / 2))
    soft(body, 0.45, 4, 1)
    # Tail: a fluffy curl going up and forward over the back, from the back of the body
    tail = []
    curl = [(0.0, 1.55, 2.45, 0.42), (0.0, 1.95, 2.85, 0.5), (0.0, 2.15, 3.45, 0.55), (0.0, 1.95, 3.95, 0.5)]
    for i, (x, y, z, r) in enumerate(curl):
        tail.append(ball(f"Tail{i}", r, (x, y, z), (0.85, 1, 1)))
    parts.append(finish(join([body] + tail), "body"))

    # Cream: the belly patch on each side and under the body, and the tip of the tail
    patch = box("Belly", (HALF * 2 + 0.06, LENGTH * 0.62, height * 0.42), (0, -0.25, BELLY + height * 0.2))
    soft(patch, 0.2, 3, 1)
    tip = ball("TailTip", 0.4, (0.0, 1.6, 4.25), (0.8, 1, 0.9))
    parts.append(finish(join([patch, tip]), "cream"))

    # Mane: three rounded chunks down the back of the head onto the front of the back
    mane = []
    for i, (y, z, s) in enumerate(((0.0, 4.3, 0.42), (0.18, 3.75, 0.4), (0.3, 3.25, 0.34))):
        chunk = box(f"Mane{i}", (0.42, s * 1.5, s * 1.6), (0, y, z))
        chunk.rotation_euler = (math.radians(-25), 0, 0)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        soft(chunk, 0.16, 3, 1)
        mane.append(chunk)
    parts.append(finish(join(mane), "mane"))

    # Legs: rounded posts into the body, each with a hoof
    for name, sx, sy in (("legFL", -1, -1), ("legFR", 1, -1), ("legBL", -1, 1), ("legBR", 1, 1)):
        x, y = sx * LEG_X, sy * LEG_Y
        leg = post(f"Leg_{name}", HOOF - 0.05, BELLY + 0.35, 0.4, 0.34, x, y)
        soft(leg, 0.08, 2, 1)
        parts.append(finish(leg, "body", f"leg__{name}"))
        hoof = post(f"Hoof_{name}", 0.0, HOOF, 0.44, 0.42, x, y)
        soft(hoof, 0.09, 2, 1)
        parts.append(finish(hoof, "hoof", f"hoof__{name}"))
    return parts


# ---------------------------------------------------------------------------------------------------------
# Render (with the Kitty's head and the saddle) and export


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def add_head_and_saddle():
    """The Kitty, scaled and placed as the head (without its legs and tail), and the saddle on the back."""
    for o in import_glb(os.path.join(ROOT, "models", "Cubelings_Roblox.glb")):
        if not o.name.startswith("Kitty") or "legs" in o.name or "mouthO" in o.name:
            bpy.data.objects.remove(o)
    head = bpy.data.objects["Kitty"]
    head.location = (0, 0, 0)
    head.scale = (1, 1, 1)
    bpy.context.view_layer.update()
    body = bpy.data.objects["Kitty__body"]
    corners = [body.matrix_world @ Vector(c) for c in body.bound_box]
    width = max(c.x for c in corners) - min(c.x for c in corners)
    bottom = min(c.z for c in corners)
    middle = (max(c.y for c in corners) + min(c.y for c in corners)) / 2
    scale = HEAD_WIDTH / width
    head.scale = (scale, scale, scale)
    head.location = (0, HEAD_Y - middle * scale, HEAD_BOTTOM - bottom * scale)

    saddle = import_glb(os.path.join(ROOT, "models", "Saddle.glb"))
    holder = bpy.data.objects.new("SaddleHolder", None)
    bpy.context.collection.objects.link(holder)
    for o in saddle:
        if o.parent is None:
            o.parent = holder
    holder.location = (0, 0.45, BACK)


def setup_render(resolution=640):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.72, 0.68, 1)
    bpy.ops.object.light_add(type="SUN", location=(4, -6, 8))
    sun = bpy.context.active_object
    sun.data.energy = 2.2
    sun.rotation_euler = (math.radians(45), math.radians(10), math.radians(25))
    bpy.ops.object.light_add(type="AREA", location=(-4, -5, 4))
    fill = bpy.context.active_object
    fill.data.energy = 300
    fill.data.size = 8
    fill.rotation_euler = (math.radians(60), 0, math.radians(-40))
    bpy.ops.object.camera_add()
    camera = bpy.context.active_object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 7.6
    scene.camera = camera
    return camera


def render_views(camera):
    from PIL import Image

    target = Vector((0, 0.2, 2.7))
    views = [("three_quarter", 35, 0.35), ("front", 0, 0.08), ("side", 90, 0.08), ("back", 180, 0.12), ("top", 0, 3.0)]
    images = []
    for view, angle, up in views:
        rad = math.radians(angle)
        direction = Vector((-math.sin(rad), -math.cos(rad), up)).normalized()
        camera.location = target + direction * 14
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(OUT, f"_pony_{view}.png")
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        images.append(Image.open(path).copy())
        os.remove(path)
    sheet = Image.new("RGB", (sum(i.width for i in images), images[0].height))
    x = 0
    for image in images:
        sheet.paste(image, (x, 0))
        x += image.width
    out = os.path.join(OUT, "Pony.png")
    sheet.save(out)
    print("wrote", out)


def export_roblox(parts):
    """One mesh per color role (Pony__body, Pony__cream, Pony__mane) and per leg and hoof."""
    by_role = {}
    for obj in parts:
        by_role.setdefault(obj["role"], []).append(obj)
    joined = []
    for role, objs in by_role.items():
        obj = join(objs) if len(objs) > 1 else objs[0]
        obj.name = f"Pony__{role}"
        joined.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in joined:
        obj.select_set(True)
    out = os.path.join(ROOT, "models", "Pony.glb")
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True)
    for obj in joined:
        print(obj.name, "faces", len(obj.data.polygons))
    print("wrote", out)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = build()
    if "roblox" in sys.argv[1:]:
        export_roblox(parts)
        return
    add_head_and_saddle()
    camera = setup_render()
    render_views(camera)


main()
