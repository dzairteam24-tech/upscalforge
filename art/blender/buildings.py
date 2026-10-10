# The town building: thinned, one 1024 texture per shop with its own roof color, and the shop's emblem in the
# blank plaque on the roof. Renders the six; with "export" writes the glb.
import bpy, sys, os, math
from mathutils import Vector, Matrix
from PIL import Image
src, out = sys.argv[-3], sys.argv[-2]; mode = sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
base=[o for o in bpy.data.objects if o.type=='MESH'][0]
bpy.context.view_layer.objects.active=base; base.select_set(True)
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
d=base.modifiers.new("d","DECIMATE"); d.ratio=10000/len(base.data.polygons); bpy.ops.object.modifier_apply(modifier="d")
# stand it on z=0, middle at x=y=0, 14 studs tall
ws=[v.co for v in base.data.vertices]
lo=Vector((min(v.x for v in ws),min(v.y for v in ws),min(v.z for v in ws))); hi=Vector((max(v.x for v in ws),max(v.y for v in ws),max(v.z for v in ws)))
s=14/(hi.z-lo.z); mid=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
for v in base.data.vertices: v.co=(v.co-mid)*s
H=14
# The plaque: near-white texture on the upper front, facing forward (-Y)
mat=base.active_material
tex=next(n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and any(l.to_socket.name=='Base Color' for l in n.outputs[0].links))
img=tex.image; W,Hh=img.size; px=list(img.pixels)
uv=base.data.uv_layers[0].data
# (the flat disc facing straight forward high on the front, in the middle)
Wd=max(v.co.x for v in base.data.vertices)-min(v.co.x for v in base.data.vertices)
acc=Vector(); nrm=Vector(); area=0; pts=[]
for f in base.data.polygons:
    if f.center.z>0.58*H and abs(f.center.x)<0.22*Wd and f.normal.y<-0.85:
        acc+=f.center*f.area; nrm+=f.normal*f.area; area+=f.area; pts.append(f.center)
center=acc/area; normal=nrm.normalized()
radius=(max(p.x for p in pts)-min(p.x for p in pts))/2
print("plaque",tuple(round(c,2) for c in center),tuple(round(c,2) for c in normal),round(radius,2))

SHOPS=[("Shop",0.42),("Trade",0.58),("Potion",0.76),("Spin",0.06),("Trips",0.55),("Arcade",0.92)]
# (hue for the roof; Trips uses a lighter blue than Trade)
def material(name,color,emit=0):
    m=bpy.data.materials.new(name); m.use_nodes=True; b=m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value=(*color,1); b.inputs["Roughness"].default_value=0.45
    if emit: b.inputs["Emission Color"].default_value=(*color,1); b.inputs["Emission Strength"].default_value=emit
    return m
def obj(o,m):
    o.data.materials.clear(); o.data.materials.append(m)
    for p in o.data.polygons: p.use_smooth=True
    return o
def cyl(r,depth,loc,verts=32):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=depth,location=loc); return bpy.context.active_object
def sph(r,loc,scale=(1,1,1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=r,location=loc); o=bpy.context.active_object; o.scale=scale; return o
def tube(points,r):
    cu=bpy.data.curves.new("t","CURVE"); cu.dimensions="3D"; cu.bevel_depth=r; cu.bevel_resolution=4; cu.use_fill_caps=True
    sp=cu.splines.new("POLY"); sp.points.add(len(points)-1)
    for p,c in zip(sp.points,points): p.co=(*c,1)
    o=bpy.data.objects.new("t",cu); bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active=o; o.select_set(True); bpy.ops.object.convert(target="MESH"); return bpy.context.view_layer.objects.active
GOLD=(1,0.66,0.12); GOLDD=(0.75,0.42,0.05)
# Emblems built facing -Y in the XZ plane around the origin, radius 1
def emblem(name):
    p=[]
    if name=="Shop":
        c=cyl(1,0.25,(0,0,0)); c.rotation_euler=(math.pi/2,0,0); p.append(obj(c,material("g",GOLD)))
        for x,z,r in ((0,-0.15,0.32),(-0.35,0.25,0.15),(-0.12,0.42,0.15),(0.12,0.42,0.15),(0.35,0.25,0.15)):
            p.append(obj(sph(r,(x,-0.16,z),(1,0.5,1)),material("gd",GOLDD)))
    elif name=="Trade":
        for k,(col,sgn) in enumerate((((0.3,0.8,0.55),1),((1,0.45,0.4),-1))):
            arc=[(math.cos(a)*0.62*sgn, -0.05, math.sin(a)*0.62*sgn+0.0) for a in [math.radians(t) for t in range(200,350,15)]]
            t=tube(arc,0.15); p.append(obj(t,material("a%d"%k,col)))
            tip=arc[-1]; bpy.ops.mesh.primitive_cone_add(vertices=16,radius1=0.32,radius2=0,depth=0.45,location=tip)
            cn=bpy.context.active_object; cn.rotation_euler=(0,math.radians(90 if sgn>0 else -90),0); p.append(obj(cn,material("a%d"%k,col)))
    elif name=="Potion":
        p.append(obj(sph(0.62,(0,-0.1,-0.22)),material("liq",(0.7,0.35,1.0),0.4)))
        p.append(obj(cyl(0.2,0.55,(0,-0.1,0.55)),material("glass",(0.85,0.9,1.0))))
        p.append(obj(cyl(0.25,0.18,(0,-0.1,0.88)),material("cork",(0.55,0.32,0.15))))
    elif name=="Spin":
        cols=[(1,0.4,0.4),(1,0.75,0.3),(1,0.95,0.4),(0.45,0.85,0.5),(0.4,0.7,1),(0.75,0.5,1)]
        for i,c in enumerate(cols):
            bpy.ops.mesh.primitive_cylinder_add(vertices=6,radius=0.95,depth=0.2,end_fill_type='NGON')
            w=bpy.context.active_object
            # keep one wedge: delete all but one triangle by scaling: simpler: thin wedge via cone of 3 verts
            bpy.data.objects.remove(w)
            bpy.ops.mesh.primitive_cone_add(vertices=3,radius1=0.0001,radius2=0.0001,depth=0.2)
            w=bpy.context.active_object; bpy.data.objects.remove(w)
            a0=i*math.pi/3; a1=a0+math.pi/3
            me=bpy.data.meshes.new("w"); verts=[(0,-0.1,0)]+[(math.cos(a0+(a1-a0)*k/6)*0.95,-0.1,math.sin(a0+(a1-a0)*k/6)*0.95) for k in range(7)]
            back=[(x,y+0.2,z) for x,y,z in verts]; me.from_pydata(verts+back,[],[[0,k+1,k] for k in range(1,7)]+[[8,8+k,8+k+1] for k in range(1,7)]+[[k,k+1,9+k,8+k] for k in range(1,7)])
            wo=bpy.data.objects.new("w",me); bpy.context.collection.objects.link(wo); p.append(obj(wo,material("s%d"%i,c)))
        t=bpy.data.objects.new("x",None)
        r=bpy.ops.mesh.primitive_torus_add(major_radius=0.97,minor_radius=0.09,location=(0,-0.1,0)); tr=bpy.context.active_object; tr.rotation_euler=(math.pi/2,0,0); p.append(obj(tr,material("g",GOLD)))
        p.append(obj(sph(0.18,(0,-0.22,0)),material("g",GOLD)))
    elif name=="Trips":
        p.append(obj(sph(0.62,(0,-0.1,0.18),(1,1,1.1)),material("bal",(1,0.45,0.45))))
        for x in (-0.22,0.22): p.append(obj(tube([(x,-0.1,-0.35),(x*0.6,-0.1,-0.62)],0.04),material("rope",(0.6,0.4,0.25))))
        b=cyl(0.24,0.28,(0,-0.1,-0.74)); p.append(obj(b,material("bask",(0.55,0.32,0.15))))
    elif name=="Arcade":
        p.append(obj(cyl(0.75,0.3,(0,-0.05,-0.55)),material("dark",(0.18,0.15,0.3))))
        p.append(obj(cyl(0.08,0.7,(0,-0.05,-0.1)),material("dark",(0.18,0.15,0.3))))
        p.append(obj(sph(0.34,(0,-0.05,0.38)),material("red",(1,0.25,0.3))))
    return p
def place(parts):
    # local -Y out of the plaque, +Z up along it
    up=(Vector((0,0,1))-normal*normal.z).normalized(); side=up.cross(-normal).normalized()
    M=Matrix(((side.x,-normal.x,up.x,0),(side.y,-normal.y,up.y,0),(side.z,-normal.z,up.z,0),(0,0,0,1)))
    M=Matrix.Translation(center+normal*0.12)@M@Matrix.Scale(radius*0.78,4)
    for o in parts:
        o.matrix_world=M@o.matrix_world
        bpy.context.view_layer.objects.active=o; bpy.ops.object.select_all(action='DESELECT'); o.select_set(True)
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
def bake_variant(name,hue):
    o=base.copy(); o.data=base.data.copy(); bpy.context.collection.objects.link(o); o.name="Building"+name
    me=o.data; src_uv=me.uv_layers[0].name
    tgt=me.uv_layers.new(name="Bake"); me.uv_layers.active=tgt
    bpy.ops.object.select_all(action='DESELECT'); bpy.context.view_layer.objects.active=o; o.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT'); bpy.ops.uv.smart_project(angle_limit=math.radians(60),island_margin=0.004); bpy.ops.object.mode_set(mode='OBJECT')
    im=bpy.data.images.new("Tex"+name,1024,1024)
    m=bpy.data.materials.new("Bake"+name); m.use_nodes=True; nt=m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    uvn=nt.nodes.new("ShaderNodeUVMap"); uvn.uv_map=src_uv
    t=nt.nodes.new("ShaderNodeTexImage"); t.image=img; nt.links.new(uvn.outputs[0],t.inputs[0])
    hsv=nt.nodes.new("ShaderNodeSeparateColor"); hsv.mode="HSV"; nt.links.new(t.outputs[0],hsv.inputs[0])
    def math_(op,a,b):
        n=nt.nodes.new("ShaderNodeMath"); n.operation=op
        for k,v in enumerate((a,b)):
            if isinstance(v,(int,float)): n.inputs[k].default_value=v
            else: nt.links.new(v,n.inputs[k])
        return n.outputs[0]
    mask=math_("MULTIPLY",math_("MULTIPLY",math_("GREATER_THAN",hsv.outputs[0],0.3),math_("LESS_THAN",hsv.outputs[0],0.5)),math_("GREATER_THAN",hsv.outputs[1],0.25))
    comb=nt.nodes.new("ShaderNodeCombineColor"); comb.mode="HSV"; comb.inputs[0].default_value=hue
    nt.links.new(hsv.outputs[1],comb.inputs[1]); nt.links.new(hsv.outputs[2],comb.inputs[2])
    mix=nt.nodes.new("ShaderNodeMix"); mix.data_type="RGBA"; nt.links.new(mask,mix.inputs["Factor"]); nt.links.new(t.outputs[0],mix.inputs["A"]); nt.links.new(comb.outputs[0],mix.inputs["B"])
    em=nt.nodes.new("ShaderNodeEmission"); nt.links.new(mix.outputs["Result"],em.inputs[0])
    outn=nt.nodes.new("ShaderNodeOutputMaterial"); nt.links.new(em.outputs[0],outn.inputs[0])
    tn=nt.nodes.new("ShaderNodeTexImage"); tn.image=im; nt.nodes.active=tn
    me.materials.clear(); me.materials.append(m)
    sc=bpy.context.scene; sc.render.engine="CYCLES"; sc.cycles.samples=1; sc.render.bake.margin=8
    bpy.ops.object.bake(type="EMIT")
    for n in list(nt.nodes): nt.nodes.remove(n)
    t2=nt.nodes.new("ShaderNodeTexImage"); t2.image=im; b=nt.nodes.new("ShaderNodeBsdfPrincipled"); b.inputs["Roughness"].default_value=0.5
    nt.links.new(t2.outputs[0],b.inputs["Base Color"]); o2=nt.nodes.new("ShaderNodeOutputMaterial"); nt.links.new(b.outputs[0],o2.inputs[0])
    me.uv_layers.remove(me.uv_layers[src_uv]); me.uv_layers["Bake"].name="UVMap"
    im.pack()
    for p in me.polygons: p.use_smooth=True
    return o
variants=[]
for i,(name,hue) in enumerate(SHOPS):
    o=bake_variant(name,hue)
    parts=[]
    for q in parts: q.name=f"Building{name}__emblem"
    off=Vector(((i%3)*20-20,-(i//3)*20,0))
    for q in [o]+parts: q.location+=off
    variants.append([o]+parts)
base.hide_render=True; base.hide_viewport=True
sc=bpy.context.scene; sc.cycles.samples=32; sc.render.resolution_x=1500; sc.render.resolution_y=1000; sc.view_settings.view_transform="Standard"
w=bpy.data.worlds.new("w"); sc.world=w; w.use_nodes=True; w.node_tree.nodes["Background"].inputs["Color"].default_value=(0.72,0.8,0.95,1)
bpy.ops.object.light_add(type="SUN"); bpy.context.active_object.rotation_euler=(0.7,0.2,0.6); bpy.context.active_object.data.energy=2.2
bpy.ops.object.camera_add(); cam=bpy.context.active_object; cam.data.type="ORTHO"; cam.data.ortho_scale=66; sc.camera=cam
c=Vector((0,-10,7)); dv=Vector((0.35,-1,0.55)).normalized(); cam.location=c+dv*120; cam.data.clip_end=500; cam.rotation_euler=(c-cam.location).to_track_quat('-Z','Y').to_euler()
sc.render.filepath=out+".png"; bpy.ops.render.render(write_still=True); print("rendered")
if mode=="export":
    for vs in variants:
        for q in vs: q.location-= q.location*0  # keep
    bpy.ops.object.select_all(action='DESELECT')
    for vs in variants:
        for q in vs: q.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out+".glb",use_selection=True,export_apply=True,export_image_format="JPEG",export_jpeg_quality=90)
    print("exported")
