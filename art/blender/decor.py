"""The map's decor (art/models/Decor.glb) and the town (art/models/Town.glb: the buildings and the town's decor),
each in one file to import in Studio once.

The props come from the Meshy sheets in art/sources (six per sheet, listed in art/sources/README.md): each sheet
is split into its props by loose parts (parts whose footprints overlap belong together; a sheet that comes out
with fewer than six is split again along its widest group), named Prop__<Name>, stood on the ground at its
height in studs, and keeps only its color texture, at 1024 px. The buildings are art/models/Buildings.glb as
building.py exports them (parts Building<Shop>__<role>, flat colors).

    python art/blender/decor.py            writes art/models/Decor.glb (the zones' props) and renders OUT/Decor.png
    python art/blender/decor.py town       writes art/models/Town.glb (buildings and town decor) and OUT/Town.png
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402, I001 (bmesh only exists once bpy is loaded)
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

ROOT = os.path.join(HERE, "..")
OUT = os.environ.get("OUT", ROOT)

# Per sheet, its props in order (the image's top row left to right, then the bottom row) and their heights in studs
SHEETS = {
    "meadow": [("Tree", 16), ("Bush", 4), ("Fence", 3.5), ("Flowers", 2.5), ("MossRock", 4), ("BigFlower", 7)],
    "forest": [("Tulip", 6), ("Beehive", 5), ("Pine", 18), ("Log", 3), ("Stump", 3), ("Fern", 4)],
    "beach": [("Umbrella", 9), ("Seashell", 3), ("PalmTree", 18), ("Rowboat", 3.5), ("SandCastle", 6), ("Starfish", 1.5)],
    "cave": [("GiantMushroom", 14), ("GlowShrooms", 4), ("CrystalCluster", 7), ("CaveBoulder", 5), ("Stalagmite", 9), ("RedMushroom", 5)],
    "desert": [("Pyramid", 16), ("BarrelCactus", 3.5), ("Cactus", 10), ("BrokenColumn", 8), ("SandRock", 4), ("Skull", 3)],
    "snow": [("SnowyPine", 18), ("Cabin", 12), ("Snowman", 7), ("SnowRock", 4), ("SnowPile", 2.5), ("Sled", 2.5)],
    "volcano": [("LavaRock", 5), ("LavaPool", 1.5), ("BurntTree", 14), ("SteamVent", 4), ("MiniVolcano", 12), ("EmberRocks", 3)],
    "ice": [("IceCrystals", 8), ("IceBlock", 5), ("SnowBank", 3), ("FrozenTree", 16), ("IcePillar", 12), ("IceShards", 5)],
    "pixel": [("NeonCube", 5), ("GridPillar", 12), ("ArcadeScreen", 9), ("PixelTree", 14), ("PixelHeart", 6), ("PixelFlower", 6)],
    "town": [("Archway", 16), ("Hedge", 4), ("FlowerPlanter", 3.5), ("Bench", 3.5), ("StreetLamp", 12), ("CatFountain", 10)],
}
TEXTURE = 1024


def components(bm):
    """The mesh's loose parts, as lists of face indices."""
    seen = set()
    groups = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, group = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            group.append(g.index)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        groups.append(group)
    return groups


def footprint(bm, faces):
    pts = [v.co for i in faces for v in bm.faces[i].verts]
    return (min(p.x for p in pts), min(p.y for p in pts), max(p.x for p in pts), max(p.y for p in pts))


def box3(bm, faces):
    pts = [v.co for i in faces for v in bm.faces[i].verts]
    return [min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts), max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)]


def main_body(bm, faces, gap=0.01):
    """A prop's faces without the bits that float apart from it (pieces of a neighbor that the cut took along,
    or Meshy's strays): only the biggest cluster of touching parts and what touches its box are kept."""
    sub = bmesh.new()
    vmap = {}
    index = {}
    for i in faces:
        f = bm.faces[i]
        nf = sub.faces.new([vmap.setdefault(v, sub.verts.new(v.co)) for v in f.verts]) if len(set(f.verts)) == len(f.verts) else None
        if nf:
            index[nf] = i
    sub.faces.index_update()
    sub.faces.ensure_lookup_table()
    parts = components(sub)
    boxes = [box3(sub, g) for g in parts]
    order = sorted(range(len(parts)), key=lambda k: -len(parts[k]))
    body = list(boxes[order[0]])
    kept = [order[0]]
    grew = True
    while grew:
        grew = False
        for k in order:
            if k in kept:
                continue
            b = boxes[k]
            if all(b[a] < body[a + 3] + gap and body[a] < b[a + 3] + gap for a in range(3)):
                kept.append(k)
                body = [min(body[a], b[a]) for a in range(3)] + [max(body[a + 3], b[a + 3]) for a in range(3)]
                grew = True
    result = [index[sub.faces[i]] for k in kept for i in parts[k]]
    sub.free()
    return result


def split_sheet(bm, count, gap=0.003):
    """The sheet's faces grouped into its `count` props, in the image's order (the back row, +Y, first, each
    row left to right). Loose parts closer than `gap` belong together; the biggest clusters are the props and
    the rest are Meshy's stray bits. Two props that touch come out as one cluster, so while there are too few,
    the widest cluster is cut in two along its long side."""
    import numpy as np

    parts = components(bm)
    boxes = np.array([footprint(bm, g) for g in parts])
    parent = list(range(len(parts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(parts)):
        near = np.nonzero((boxes[:, 0] < boxes[i, 2] + gap) & (boxes[i, 0] < boxes[:, 2] + gap) & (boxes[:, 1] < boxes[i, 3] + gap) & (boxes[i, 1] < boxes[:, 3] + gap))[0]
        for j in near:
            a, b = find(i), find(int(j))
            if a != b:
                parent[a] = b
    clusters = {}
    for i, g in enumerate(parts):
        clusters.setdefault(find(i), []).extend(g)
    big = max(len(g) for g in clusters.values())
    groups = [g for g in clusters.values() if len(g) > big * 0.08]
    while len(groups) < count:
        fp = [footprint(bm, g) for g in groups]
        i = max(range(len(groups)), key=lambda k: max(fp[k][2] - fp[k][0], fp[k][3] - fp[k][1]))
        axis = 0 if fp[i][2] - fp[i][0] >= fp[i][3] - fp[i][1] else 1
        centers = {f: bm.faces[f].calc_center_median()[axis] for f in groups[i]}
        lo, hi = fp[i][axis], fp[i][axis + 2]
        for _ in range(20):  # 2-means along the axis
            mid = (lo + hi) / 2
            left = [c for c in centers.values() if c < mid]
            right = [c for c in centers.values() if c >= mid]
            lo, hi = sum(left) / len(left), sum(right) / len(right)
        mid = (lo + hi) / 2
        groups[i:i + 1] = [[f for f in groups[i] if centers[f] < mid], [f for f in groups[i] if centers[f] >= mid]]
    groups = [main_body(bm, g) for g in sorted(groups, key=len, reverse=True)[:count]]
    fp = [footprint(bm, g) for g in groups]
    order = sorted(range(count), key=lambda k: -(fp[k][1] + fp[k][3]))
    rows = [sorted(order[: count // 2], key=lambda k: fp[k][0]), sorted(order[count // 2:], key=lambda k: fp[k][0])]
    return [groups[k] for k in rows[0] + rows[1]]


def color_only(mat):
    """Keeps only the material's color texture, scaled down to TEXTURE px."""
    nodes = mat.node_tree.nodes
    bsdf = nodes["Principled BSDF"]
    links = mat.node_tree.links
    for name in ("Metallic", "Roughness", "Normal"):
        for link in list(bsdf.inputs[name].links):
            links.remove(link)
    bsdf.inputs["Metallic"].default_value = 0
    bsdf.inputs["Roughness"].default_value = 0.7
    for link in bsdf.inputs["Base Color"].links:
        image = link.from_node.image
        if image and image.size[0] > TEXTURE:
            image.scale(TEXTURE, TEXTURE)
    for node in list(nodes):
        if node.type == "TEX_IMAGE" and not node.outputs["Color"].links or node.type == "NORMAL_MAP":
            nodes.remove(node)


def props(sheets):
    pieces = []
    only = os.environ.get("SHEET")
    for sheet in sheets:
        if only and sheet not in only.split(","):
            continue
        names = SHEETS[sheet]
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "sources", f"props_{sheet}.glb"))
        obj = next(o for o in bpy.data.objects if o not in before and o.type == "MESH")
        for mat in obj.data.materials:
            color_only(mat)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.faces.ensure_lookup_table()
        groups = split_sheet(bm, len(names))
        print(sheet, [len(g) for g in groups])
        bm.free()
        debug = os.environ.get("DEBUG")
        for n, ((name, height), faces) in enumerate(zip(names, groups)):
            if debug:
                name, height = f"{sheet}{n}", None
            piece = obj.copy()
            piece.data = obj.data.copy()
            bpy.context.collection.objects.link(piece)
            keep = set(faces)
            pbm = bmesh.new()
            pbm.from_mesh(piece.data)
            pbm.faces.ensure_lookup_table()
            bmesh.ops.delete(pbm, geom=[f for f in pbm.faces if f.index not in keep], context="FACES")
            # Standing on the ground at its middle, `height` studs tall
            pts = [v.co for v in pbm.verts]
            lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
            hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
            k = height / (hi.z - lo.z) if height else 30
            base = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
            for v in pbm.verts:
                v.co = (v.co - base) * k
            pbm.to_mesh(piece.data)
            pbm.free()
            piece.name = piece.data.name = "Prop__" + name
            pieces.append(piece)
        bpy.data.objects.remove(obj)
    return pieces


def buildings():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "models", "Buildings.glb"))
    found = {}
    for obj in bpy.data.objects:
        if obj not in before and obj.type == "MESH":
            found.setdefault(obj.name.split("__")[0], []).append(obj)
    return found


def layout(pieces, houses):
    """Lays every piece out on a grid (where they are doesn't matter to the game; it's for looking at)."""
    x = 0.0
    row = 0
    for i, piece in enumerate(pieces):
        if i % 12 == 0 and i:
            row += 1
            x = 0.0
        size = max(piece.dimensions.x, piece.dimensions.y)
        piece.location = (x + size / 2, row * 24, 0)
        x += size + 4
    for i, (name, parts) in enumerate(sorted(houses.items())):
        for obj in parts:
            obj.location.x += i * 20
            obj.location.y -= 30


def render(objs):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.render.resolution_x = 2400
    scene.render.resolution_y = 1600
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.72, 0.8, 0.95, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.2
    bpy.ops.object.light_add(type="SUN")
    sun = bpy.context.active_object
    sun.rotation_euler = (0.7, 0.2, 0.6)
    sun.data.energy = 2.2
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    target = (lo + hi) / 2
    bpy.ops.object.camera_add()
    camera = bpy.context.active_object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = max(hi.x - lo.x, hi.y - lo.y) * 1.05
    camera.data.clip_end = 2000
    scene.camera = camera
    camera.location = target + Vector((0, -1, 1.1)).normalized() * 500
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    for obj in objs:
        if obj.name.startswith("Prop__"):
            bpy.ops.object.text_add(location=(obj.location.x, obj.location.y - 6, 0.1))
            text = bpy.context.active_object
            text.data.body = obj.name[6:]
            text.data.size = 1.6
            text.data.align_x = "CENTER"
    out = os.path.join(OUT, ("Town" if bpy.data.objects.get("Prop__CatFountain") else "Decor") + ".png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("wrote", out)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    town = "town" in sys.argv[1:]
    pieces = props(["town"] if town else [k for k in SHEETS if k != "town"])
    houses = buildings() if town else {}
    layout(pieces, houses)
    objs = pieces + [o for parts in houses.values() for o in parts]
    for obj in bpy.data.objects:
        if obj.type != "MESH" or obj not in objs:
            bpy.data.objects.remove(obj)
    for obj in pieces:
        print(obj.name, len(obj.data.polygons), "faces", tuple(round(d, 1) for d in obj.dimensions))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    out = os.path.join(ROOT, "models", "Town.glb" if town else "Decor.glb")
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True, export_image_format="JPEG")
    print("wrote", out, os.path.getsize(out) // 1024, "KB")
    render(objs)


main()
