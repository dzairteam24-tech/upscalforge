"""Map props from Meshy (art: the props sheets): textured models made in Meshy from a sheet of 12 props, split
into separate props, each given its own 1024 texture (Roblox shows textures at 1024 at most, so the sheet's
one shared 4096 texture would leave each prop blurry), small texture mistakes painted over, and sized in studs.

    python art/blender/props.py            renders OUT/Props.png (every prop, 3/4 view)
    python art/blender/props.py roblox     writes art/models/Props.glb (one textured mesh per prop, named
                                           Prop__<Name>) and roblox/shared/Config/PropLooks.luau

Sources: art/sources/*.glb (Meshy exports), listed in BATCHES with what each prop is, in the order the split
finds them (rows from the back, then left to right). Needs Python with bpy (Blender 4.2+) and pillow.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
REPO = os.path.join(ROOT, "..")
OUT = os.environ.get("OUT", ROOT)
TEXTURE = 1024

# Each source sheet: its props in split order, as (name, height in studs, zones it decorates, fixes).
# Fixes paint over texture mistakes before baking: ("hue", lo, hi, min saturation, rgb) recolors that hue
# range; ("rings", light, dark) draws tree rings on the flat top.
WOOD_LIGHT = (0.86, 0.62, 0.36)
WOOD_DARK = (0.55, 0.32, 0.15)
BATCHES = [
    (
        "meshy_batch1.glb",
        [
            ("Bush", 6, (1, 2), []),
            ("Tree", 16, (1, 3), [("hue", 0.6, 0.9, 0.08, (0.32, 0.72, 0.18))]),
            ("Fence", 5, (1,), []),
            ("Flowers", 4, (1, 2), []),
            ("MossRock", 5, (1,), []),
            ("Tulip", 7, (2,), []),
            ("BigFlower", 8, (2,), []),
            ("Beehive", 9, (2,), []),
            ("Stump", 5, (3,), [("rings", WOOD_LIGHT, WOOD_DARK)]),
            ("Fern", 5, (3,), []),
            ("Pine", 18, (3,), [("hue", 0.85, 1.0, 0.15, (0.12, 0.42, 0.28)), ("hue", 0.0, 0.04, 0.2, (0.12, 0.42, 0.28))]),
            ("Log", 4, (3,), []),
        ],
    ),
]


def split(path):
    """The sheet's props as separate objects (loose parts grouped by overlapping footprints), in order."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    obj = next(o for o in bpy.data.objects if o not in before and o.type == "MESH")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.mesh.separate(type="LOOSE")
    parts = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]

    def box(p):
        ws = [v.co for v in p.data.vertices]
        return (min(v.x for v in ws), min(v.y for v in ws), max(v.x for v in ws), max(v.y for v in ws))

    boxes = [box(p) for p in parts]
    parent = list(range(len(parts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    margin = 0.005
    for i in range(len(parts)):
        for j in range(i + 1, len(parts)):
            a, b = boxes[i], boxes[j]
            if a[0] - margin < b[2] and b[0] - margin < a[2] and a[1] - margin < b[3] and b[1] - margin < a[3]:
                parent[find(i)] = find(j)
    groups = {}
    for i in range(len(parts)):
        groups.setdefault(find(i), []).append(i)
    keep = [g for g in groups.values() if sum(len(parts[i].data.polygons) for i in g) >= 30]

    def middle(g):
        return ((min(boxes[i][0] for i in g) + max(boxes[i][2] for i in g)) / 2, (min(boxes[i][1] for i in g) + max(boxes[i][3] for i in g)) / 2)

    keep.sort(key=lambda g: (-round(middle(g)[1] / 0.15), middle(g)[0]))
    props = []
    for g in keep:
        bpy.ops.object.select_all(action="DESELECT")
        for i in g:
            parts[i].select_set(True)
        bpy.context.view_layer.objects.active = parts[g[0]]
        if len(g) > 1:
            bpy.ops.object.join()
        props.append(bpy.context.view_layer.objects.active)
    keep_names = {p.name for p in props}
    for o in list(bpy.data.objects):
        if o not in before and o.type == "MESH" and o.name not in keep_names:
            bpy.data.objects.remove(o)
    return props


def fit(obj, height):
    """Stands the prop on z = 0, its middle at x = y = 0, `height` studs tall."""
    ws = [v.co for v in obj.data.vertices]
    lo = Vector((min(v.x for v in ws), min(v.y for v in ws), min(v.z for v in ws)))
    hi = Vector((max(v.x for v in ws), max(v.y for v in ws), max(v.z for v in ws)))
    s = height / (hi.z - lo.z)
    base = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for v in obj.data.vertices:
        v.co = (v.co - base) * s


def fixed_color(tree, color, fixes, top):
    """Shader nodes painting the fixes over the texture's color: returns the fixed color socket."""
    nodes, links = tree.nodes, tree.links
    out = color
    for fix in fixes:
        if fix[0] == "hue":
            _, lo, hi, sat, rgb = fix
            hsv = nodes.new("ShaderNodeSeparateColor")
            hsv.mode = "HSV"
            links.new(out, hsv.inputs[0])
            above = nodes.new("ShaderNodeMath")
            above.operation = "GREATER_THAN"
            links.new(hsv.outputs[0], above.inputs[0])
            above.inputs[1].default_value = lo
            below = nodes.new("ShaderNodeMath")
            below.operation = "LESS_THAN"
            links.new(hsv.outputs[0], below.inputs[0])
            below.inputs[1].default_value = hi
            saturated = nodes.new("ShaderNodeMath")
            saturated.operation = "GREATER_THAN"
            links.new(hsv.outputs[1], saturated.inputs[0])
            saturated.inputs[1].default_value = sat
            both = nodes.new("ShaderNodeMath")
            both.operation = "MULTIPLY"
            links.new(above.outputs[0], both.inputs[0])
            links.new(below.outputs[0], both.inputs[1])
            mask = nodes.new("ShaderNodeMath")
            mask.operation = "MULTIPLY"
            links.new(both.outputs[0], mask.inputs[0])
            links.new(saturated.outputs[0], mask.inputs[1])
            # keep the texture's shading: the new color times the old brightness
            bright = nodes.new("ShaderNodeMath")
            bright.operation = "MULTIPLY"
            links.new(hsv.outputs[2], bright.inputs[0])
            bright.inputs[1].default_value = 1.4
            shade = nodes.new("ShaderNodeMix")
            shade.data_type = "RGBA"
            shade.blend_type = "MULTIPLY"
            shade.inputs["Factor"].default_value = 1
            shade.inputs["A"].default_value = (*rgb, 1)
            links.new(bright.outputs[0], shade.inputs["B"])
            mix = nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            links.new(mask.outputs[0], mix.inputs["Factor"])
            links.new(out, mix.inputs["A"])
            links.new(shade.outputs["Result"], mix.inputs["B"])
            out = mix.outputs["Result"]
        elif fix[0] == "rings":
            _, light, dark = fix
            geo = nodes.new("ShaderNodeNewGeometry")
            normal = nodes.new("ShaderNodeSeparateXYZ")
            links.new(geo.outputs["Normal"], normal.inputs[0])
            pos = nodes.new("ShaderNodeSeparateXYZ")
            links.new(geo.outputs["Position"], pos.inputs[0])
            flat = nodes.new("ShaderNodeMath")
            flat.operation = "GREATER_THAN"
            links.new(normal.outputs["Z"], flat.inputs[0])
            flat.inputs[1].default_value = 0.8
            high = nodes.new("ShaderNodeMath")
            high.operation = "GREATER_THAN"
            links.new(pos.outputs["Z"], high.inputs[0])
            high.inputs[1].default_value = top * 0.85
            mask = nodes.new("ShaderNodeMath")
            mask.operation = "MULTIPLY"
            links.new(flat.outputs[0], mask.inputs[0])
            links.new(high.outputs[0], mask.inputs[1])
            # rings: by the distance from the middle
            dist = nodes.new("ShaderNodeVectorMath")
            dist.operation = "LENGTH"
            comb = nodes.new("ShaderNodeCombineXYZ")
            links.new(pos.outputs["X"], comb.inputs["X"])
            links.new(pos.outputs["Y"], comb.inputs["Y"])
            links.new(comb.outputs[0], dist.inputs[0])
            wave = nodes.new("ShaderNodeMath")
            wave.operation = "SINE"
            scale = nodes.new("ShaderNodeMath")
            scale.operation = "MULTIPLY"
            links.new(dist.outputs["Value"], scale.inputs[0])
            scale.inputs[1].default_value = 7.0
            links.new(scale.outputs[0], wave.inputs[0])
            sharp = nodes.new("ShaderNodeMath")
            sharp.operation = "GREATER_THAN"
            links.new(wave.outputs[0], sharp.inputs[0])
            sharp.inputs[1].default_value = 0.75
            ring = nodes.new("ShaderNodeMix")
            ring.data_type = "RGBA"
            links.new(sharp.outputs[0], ring.inputs["Factor"])
            ring.inputs["A"].default_value = (*light, 1)
            ring.inputs["B"].default_value = (*dark, 1)
            mix = nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            links.new(mask.outputs[0], mix.inputs["Factor"])
            links.new(out, mix.inputs["A"])
            links.new(ring.outputs["Result"], mix.inputs["B"])
            out = mix.outputs["Result"]
    return out


def bake(obj, name, fixes, height):
    """Gives the prop its own TEXTURE x TEXTURE color texture on a fresh UV layout, with the fixes painted."""
    mesh = obj.data
    source_uv = mesh.uv_layers[0].name
    target = mesh.uv_layers.new(name="Bake")
    mesh.uv_layers.active = target
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")

    old = obj.active_material
    base = next(n for n in old.node_tree.nodes if n.type == "TEX_IMAGE" and any(l.to_socket.name == "Base Color" for l in n.outputs[0].links))
    image = bpy.data.images.new(f"Prop_{name}", TEXTURE, TEXTURE)
    mat = bpy.data.materials.new(f"Bake_{name}")
    mat.use_nodes = True
    tree = mat.node_tree
    for n in list(tree.nodes):
        tree.nodes.remove(n)
    uv = tree.nodes.new("ShaderNodeUVMap")
    uv.uv_map = source_uv
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = base.image
    tree.links.new(uv.outputs[0], tex.inputs[0])
    color = fixed_color(tree, tex.outputs["Color"], fixes, height)
    emit = tree.nodes.new("ShaderNodeEmission")
    tree.links.new(color, emit.inputs["Color"])
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(emit.outputs[0], output.inputs["Surface"])
    target_node = tree.nodes.new("ShaderNodeTexImage")
    target_node.image = image
    tree.nodes.active = target_node
    obj.data.materials.clear()
    obj.data.materials.append(mat)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.render.bake.margin = 8
    bpy.ops.object.bake(type="EMIT")

    # The final material: the baked texture on the new layout, the only one left
    for n in list(tree.nodes):
        tree.nodes.remove(n)
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    bsdf = tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.6
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(bsdf.outputs[0], output.inputs["Surface"])
    mesh.uv_layers.remove(mesh.uv_layers[source_uv])
    mesh.uv_layers["Bake"].name = "UVMap"
    image.filepath_raw = os.path.join(OUT, f"_tex_{name}.png")
    image.file_format = "PNG"
    image.save()
    image.pack()


def build():
    props = []
    for file, entries in BATCHES:
        objs = split(os.path.join(ROOT, "sources", file))
        if len(objs) != len(entries):
            raise SystemExit(f"{file}: found {len(objs)} props, BATCHES lists {len(entries)}")
        for obj, (name, height, zones, fixes) in zip(objs, entries):
            fit(obj, height)
            bake(obj, name, fixes, height)
            obj.name = f"Prop__{name}"
            obj.data.name = obj.name
            for p in obj.data.polygons:
                p.use_smooth = True
            props.append((obj, name, height, zones))
    return props


def render(props):
    from PIL import Image, ImageDraw

    scene = bpy.context.scene
    scene.cycles.samples = 32
    scene.render.resolution_x = 400
    scene.render.resolution_y = 400
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.72, 0.8, 0.95, 1)
    bpy.ops.object.light_add(type="SUN")
    sun = bpy.context.active_object
    sun.rotation_euler = (0.7, 0.2, 0.6)
    sun.data.energy = 2.2
    bpy.ops.object.camera_add()
    camera = bpy.context.active_object
    camera.data.type = "ORTHO"
    scene.camera = camera
    tiles = []
    for obj, name, height, _ in props:
        for other, *_ in props:
            other.hide_render = other is not obj
        ws = [v.co for v in obj.data.vertices]
        lo = Vector((min(v.x for v in ws), min(v.y for v in ws), 0))
        hi = Vector((max(v.x for v in ws), max(v.y for v in ws), height))
        middle = (lo + hi) / 2
        camera.data.ortho_scale = (hi - lo).length * 1.05
        d = Vector((0.5, -1, 0.55)).normalized()
        camera.location = middle + d * 60
        camera.rotation_euler = (middle - camera.location).to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(OUT, "_prop.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        tile = Image.open(path).copy()
        os.remove(path)
        ImageDraw.Draw(tile).text((8, 8), f"{name} ({height} studs)", fill=(30, 30, 60))
        tiles.append(tile)
    cols = 6
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 400, rows * 400), (220, 228, 245))
    for i, tile in enumerate(tiles):
        sheet.paste(tile, ((i % cols) * 400, (i // cols) * 400))
    path = os.path.join(OUT, "Props.png")
    sheet.save(path)
    print("wrote", path)


def export(props):
    bpy.ops.object.select_all(action="DESELECT")
    for obj, *_ in props:
        obj.select_set(True)
    out = os.path.join(ROOT, "models", "Props.glb")
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True, export_image_format="JPEG", export_jpeg_quality=90)
    print("wrote", out)
    lines = [
        "--!strict",
        "-- The map props' models as exported (written by art/blender/props.py roblox; don't edit by hand): per prop,",
        "-- its size in studs (as modeled: Y up) and the zones it decorates. PropService places them.",
        "",
        "export type Look = { name: string, size: Vector3, zones: { number } }",
        "",
        "local looks: { Look } = {",
    ]
    for obj, name, height, zones in props:
        ws = [v.co for v in obj.data.vertices]
        sx = max(v.x for v in ws) - min(v.x for v in ws)
        sy = max(v.y for v in ws) - min(v.y for v in ws)
        print(f"{name}: faces {len(obj.data.polygons)}, size {sx:.1f} x {height} x {sy:.1f}")
        lines.append(f'\t{{ name = "{name}", size = Vector3.new({sx:.2f}, {height:.2f}, {sy:.2f}), zones = {{ {", ".join(str(z) for z in zones)} }} }},')
    lines += ["}", "", "return looks", ""]
    path = os.path.join(REPO, "roblox", "shared", "Config", "PropLooks.luau")
    open(path, "w").write("\n".join(lines))
    print("wrote", path)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    props = build()
    if "roblox" in sys.argv[1:]:
        export(props)
    else:
        render(props)


main()
