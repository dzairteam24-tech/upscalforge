"""The Cubeling Ride's pony body (art: the Cubeling riding model sheet): a chunky rounded cube body with a
cream belly patch, four short thick legs with brown hooves and a big curled tail with a cream tip. The head
is the rider's own creature, low on the front of the body (the game puts it there), so every species gets a
pony body in its color and the rider shows above the head.

Units: the body is 1.6 wide (x = +-0.8) and 2.2 long, the ground is z = 0, the top of the back is at
z = BACK. Front is -Y, like the creatures.

    python art/blender/pony.py              renders: art/renders/Pony.png (3/4, front, side, back, top),
                                            with the Kitty's head (art/models/Cubelings_Roblox.glb) and the
                                            saddle
    python art/blender/pony.py ride         renders: art/renders/Ride.png, the same with a rider on the saddle
                                            (3/4 front, front, side, 3/4 rear, back, top, bottom)
    python art/blender/pony.py roblox       also writes art/models/Pony.glb: Pony__body, Pony__cream, and
                                            per leg Pony__leg__legFL... and Pony__hoof__legFL..., for
                                            Studio's Import 3D

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
    # the rider in the riding sheet: a blocky Roblox character
    "shirt": (0.025, 0.025, 0.03),
    "pants": (0.03, 0.06, 0.25),
    "skin": (0.8, 0.55, 0.38),
}

HALF = 0.8  # the body's side, from its middle
LENGTH = 2.2  # the body, front to back
BACK = 2.35  # top of the back above the ground
BELLY = 0.65  # bottom of the body above the ground
ROUND = 0.55  # the body's rounded edges
LEG_X = 0.45
LEG_Y = 0.62
HOOF = 0.26
SADDLE_Y = 0.3  # the saddle's middle, behind the body's middle (RideModel uses the same)
HEAD_WIDTH = 1.6  # the creature's head, for the render; the game uses the same numbers (RideModel)
HEAD_Y = -1.4
HEAD_BOTTOM = 1.0

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

    # Body: a chunky rounded cube, a little longer than wide
    height = BACK - BELLY
    body = box("Body", (HALF * 2, LENGTH, height), (0, 0, BELLY + height / 2))
    soft(body, ROUND, 4, 1)
    # Tail: a small fluffy curl going up from the back of the body
    tail = []
    back = LENGTH / 2
    curl = [(back + 0.05, 1.7, 0.3), (back + 0.36, 2.05, 0.36), (back + 0.46, 2.55, 0.38), (back + 0.3, 3.0, 0.34)]
    for i, (y, z, r) in enumerate(curl):
        tail.append(ball(f"Tail{i}", r, (0.0, y, z), (0.85, 1, 1)))
    parts.append(finish(join([body] + tail), "body"))

    # Cream: the belly patch on each side and under the body, and the tip of the tail
    patch = box("Belly", (HALF * 2 + 0.05, LENGTH * 0.55, height * 0.4), (0, -0.2, BELLY + height * 0.2))
    soft(patch, 0.18, 3, 1)
    tip = ball("TailTip", 0.3, (0.0, back + 0.08, 3.22), (0.8, 1, 0.9))
    parts.append(finish(join([patch, tip]), "cream"))

    # Legs: short rounded posts into the body, each with a hoof
    for name, sx, sy in (("legFL", -1, -1), ("legFR", 1, -1), ("legBL", -1, 1), ("legBR", 1, 1)):
        x, y = sx * LEG_X, sy * LEG_Y
        leg = post(f"Leg_{name}", HOOF - 0.05, BELLY + 0.35, 0.4, 0.36, x, y)
        soft(leg, 0.07, 2, 1)
        parts.append(finish(leg, "body", f"leg__{name}"))
        hoof = post(f"Hoof_{name}", 0.0, HOOF, 0.44, 0.42, x, y)
        soft(hoof, 0.08, 2, 1)
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
    holder.location = (0, SADDLE_Y, BACK)


# The rider, for the riding sheet: an R15 character of blocks posed like the game poses it (RideClient POSE,
# degrees), its hips RIDER_HIP above the back in the middle of the saddle. Built in the game's axes (studs,
# Y up, front -Z) and turned into Blender's (units of 2 studs, Z up, front -Y).
POSE = {"hipPitch": 15, "hipRoll": 70, "kneePitch": -40, "kneeRoll": -50, "armPitch": 0, "armRoll": 48, "elbowPitch": 74}
RIDER_HIP = 0.16


def add_rider():
    from mathutils import Matrix

    def angles(pitch, roll):
        return Matrix.Rotation(math.radians(pitch), 3, "X") @ Matrix.Rotation(math.radians(roll), 3, "Z")

    swap = Matrix(((1, 0, 0), (0, 0, 1), (0, 1, 0)))
    seat = Vector((0, SADDLE_Y, BACK + RIDER_HIP))

    def block(size, rot, pos, key):
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.active_object
        obj.scale = (size[0] / 2, size[2] / 2, size[1] / 2)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        soft(obj, 0.03, 2, 0)
        obj.matrix_world = Matrix.Translation(seat + swap @ Vector(pos) / 2) @ (swap @ rot @ swap).to_4x4()
        finish(obj, key)

    one = Matrix.Identity(3)
    P = POSE
    block((2, 0.4, 1), one, (0, 0.2, 0), "pants")
    block((2, 1.6, 1), one, (0, 1.2, 0), "shirt")
    block((1.2, 1.2, 1.2), one, (0, 2.6, 0), "skin")
    for side in (-1, 1):
        hip = Vector((side * 0.5, 0, 0))
        rh = angles(P["hipPitch"], P["hipRoll"] * side)
        knee = hip + rh @ Vector((0, -1.2, 0))
        block((0.9, 1.2, 0.9), rh, hip + rh @ Vector((0, -0.6, 0)), "pants")
        rk = rh @ angles(P["kneePitch"], P["kneeRoll"] * side)
        block((0.85, 1.2, 0.85), rk, knee + rk @ Vector((0, -0.6, 0)), "pants")
        block((0.9, 0.3, 1.1), rk, knee + rk @ Vector((0, -1.3, -0.1)), "shirt")
        shoulder = Vector((side * 1.0, 1.85, 0))
        ra = angles(P["armPitch"], P["armRoll"] * -side)
        block((0.9, 1.05, 0.9), ra, shoulder + ra @ Vector((side * 0.5, -0.5, 0)), "shirt")
        elbow = shoulder + ra @ Vector((0, -1.0, 0))
        re = ra @ angles(P["elbowPitch"], 0)
        block((0.85, 0.8, 0.85), re, elbow + re @ Vector((side * 0.5, -0.4, 0)), "shirt")
        block((0.8, 0.35, 0.8), re, elbow + re @ Vector((side * 0.5, -0.95, 0)), "skin")


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
    camera.data.ortho_scale = 6.0
    scene.camera = camera
    return camera


def render_views(camera, name="Pony", views=None, target=Vector((0, 0.1, 2.2))):
    from PIL import Image

    views = views or [("three_quarter", 35, 0.35), ("front", 0, 0.08), ("side", 90, 0.08), ("back", 180, 0.12), ("top", 0, 3.0)]
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
    out = os.path.join(OUT, f"{name}.png")
    sheet.save(out)
    print("wrote", out)


def export_roblox(parts):
    """One mesh per color role (Pony__body, Pony__cream) and per leg and hoof."""
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
    if "ride" in sys.argv[1:]:
        # The riding sheet: with the rider, from every side
        add_rider()
        camera.data.ortho_scale = 5.6
        views = [("front_34", 40, 0.3), ("front", 0, 0.08), ("side", 90, 0.08), ("rear_34", 140, 0.3), ("back", 180, 0.08), ("top", 0, 3.0), ("bottom", 0, -3.0)]
        render_views(camera, "Ride", views, Vector((0, 0.15, 2.45)))
        return
    render_views(camera)


main()
