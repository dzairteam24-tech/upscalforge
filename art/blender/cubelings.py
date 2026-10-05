"""Builds Cubelings creatures in Blender from a small spec, renders a turnaround sheet and exports
a Roblox-ready mesh.

Run (Blender's Python, no window needed):
    python art/blender/cubelings.py Kitty

Outputs:
    art/renders/<Name>.png     front / side / back / 3-4 views, to compare with art/concepts/<Name>.png
    art/models/<Name>.fbx      one mesh, colors come from a small palette texture (embedded)
    art/models/<Name>.glb      same model as glTF
    art/models/<Name>_palette.png

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
    mat["palette_color"] = color
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


def tube(name, points, radius):
    """A round tube along a list of 3D points (mouth lines and such)."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
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
# Building


def build(spec):
    colors = {key: hex_color(value) for key, value in spec["colors"].items()}
    mat = {key: material(key, value, gloss=key in ("eye", "shine", "nose")) for key, value in colors.items()}
    parts = []

    # Body: one rounded cube
    body = rounded_box("Body", (BODY_W, BODY_D, BODY_H), (0, 0, BODY_Z), BEVEL, segments=5)
    parts.append(finish(body, mat["body"]))

    # Belly: a shell of the body (slightly bigger) cut by an ellipse at the front, so it wraps the bevel
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

    # Legs: four short rounded blocks at the corners
    for x in (-0.62, 0.62):
        for y in (-0.62, 0.62):
            leg = rounded_box("Leg", (0.46, 0.46, LEG_H + 0.3), (x, y, (LEG_H + 0.3) / 2), 0.1, segments=3)
            parts.append(finish(leg, mat["legs"]))

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

    # Eyes with a white shine
    eye_scale = spec.get("eyes", 1.0)
    for side in (-1, 1):
        eye = ellipsoid("Eye", (0.19 * eye_scale, 0.07, 0.24 * eye_scale), face_point(0.47 * side, 0.1, 0.0))
        parts.append(finish(eye, mat["eye"]))
        shine = ellipsoid("Shine", (0.055 * eye_scale, 0.03, 0.055 * eye_scale), face_point(0.47 * side + 0.06 * eye_scale, 0.1 + 0.09 * eye_scale, 0.06), segments=10, rings=6)
        parts.append(finish(shine, mat["shine"]))

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

    # Mouth: a cat "w" or a simple smile
    mouth_kind = spec.get("mouth", "cat")
    points = []
    if mouth_kind == "cat":
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
    mouth = tube("Mouth", points, 0.026)
    parts.append(finish(mouth, mat["mouth"]))

    # Buck teeth under the mouth
    if spec.get("teeth"):
        # A dark backing so white teeth still read on a white face
        backing = rounded_box("TeethBack", (0.2, 0.03, 0.15), face_point(0, -0.285, 0.0), 0.03, segments=2)
        parts.append(finish(backing, mat["mouth"]))
        for side in (-1, 1):
            tooth = rounded_box("Tooth", (0.075, 0.04, 0.11), face_point(0.043 * side, -0.29, 0.025), 0.018, segments=2)
            parts.append(finish(tooth, mat["teeth"]))

    # Blush
    for side in (-1, 1):
        blush = ellipsoid("Blush", (0.13, 0.02, 0.09), face_point(0.76 * side, -0.07, 0.0), segments=14, rings=6)
        parts.append(finish(blush, mat["blush"]))

    # Tail
    if spec["tail"] == "stub":
        tail = rounded_box("Tail", (0.34, 0.75, 0.32), (0, BODY_D / 2 + 0.28, BODY_Z - 0.36), 0.1, segments=3, rotation=(math.radians(-18), 0, 0))
        parts.append(finish(tail, mat["legs"]))
    elif spec["tail"] == "puff":
        tail = ellipsoid("Tail", (0.3, 0.26, 0.3), (0, BODY_D / 2 + 0.08, BODY_Z - 0.35), segments=20, rings=12)
        parts.append(finish(tail, mat["tail"]))
    elif spec["tail"] == "nub":
        tail = ellipsoid("Tail", (0.18, 0.16, 0.18), (0, BODY_D / 2 + 0.04, BODY_Z - 0.4), segments=16, rings=10)
        parts.append(finish(tail, mat["tail"]))

    return parts


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
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (*hex_color("#B9B9B9"), 1)
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
    views = [("front", 0), ("side", 90), ("back", 180), ("three_quarter", 35)]
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


def main():
    names = sys.argv[1:] or ["Kitty"]
    for name in names:
        reset()
        parts = build(SPECIES[name])
        camera = setup_render()
        render_views(name, camera)
        triangles = export(name, parts)
        print(f"[cubelings] {name}: {triangles} triangles")
    if len(names) > 1:
        # Lineup: the 3/4 view of each creature side by side
        from PIL import Image

        views = []
        for name in names:
            sheet = Image.open(os.path.join(ROOT, "renders", f"{name}.png"))
            w = sheet.width // 4
            views.append(sheet.crop((3 * w, 0, 4 * w, sheet.height)))
        lineup = Image.new("RGB", (sum(v.width for v in views), views[0].height))
        x = 0
        for view in views:
            lineup.paste(view, (x, 0))
            x += view.width
        lineup.save(os.path.join(ROOT, "renders", "lineup.png"))


if __name__ == "__main__":
    main()
