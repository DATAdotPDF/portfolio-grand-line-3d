"""APOSENTADO (Pedro, 2026-10-09): PROIBIDO reduzir/decimar/quantizar os GLBs do Meshy. Não use;
veja Tools/optimize_world_assets.sh.

Otimiza um modelo do Meshy (GLB texturizado) para o mundo web (Godot Compatibility).

Uso (Blender em modo batch):
  blender -b --factory-startup -P Tools/optimize_world_asset.py -- <entrada.glb> <saida.glb> <triangulos> <textura_px> <tamanho_m> <eixo> <calado>

- triangulos: alvo depois do Decimate (collapse).
- textura_px: lado da textura de cor (só a cor fica; normal/metal/rugosidade saem).
- tamanho_m: medida final do maior lado (eixo "max") ou da altura (eixo "z").
- calado: fração da altura que fica embaixo d'água (a origem vai para a linha d'água).
- mapas (opcional): "normal" mantém também o mapa de normais do Meshy (reduzido como a cor), para
  o modelo reduzido continuar parecido com o original.
"""
import bpy
import sys
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
target_tris = int(args[2])
tex_px = int(args[3])
size_m = float(args[4])
axis = args[5]
draft = float(args[6])
keep_maps = args[7].split(",") if len(args) > 7 and args[7] else []

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.selected_objects:
	o.select_set(False)
for o in meshes:
	o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if len(meshes) > 1:
	bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
# O Meshy entrega a malha "solta" nas costuras da textura (vértices duplicados): sem soldar, o
# Decimate encolhe cada pedaço sozinho e abre buracos (a boia virou renda). Solda antes (os UVs
# ficam por canto de face, então a textura não muda).
import bmesh
vs0 = [v.co for v in obj.data.vertices]
span = max(max(v[i] for v in vs0) - min(v[i] for v in vs0) for i in range(3))
bm = bmesh.new()
bm.from_mesh(obj.data)
before = len(bm.verts)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=span * 1e-4)
bm.to_mesh(obj.data)
bm.free()
print("OPT_WELD %d -> %d vertices" % (before, len(obj.data.vertices)))
tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
if tris > target_tris:
	mod = obj.modifiers.new("dec", "DECIMATE")
	mod.ratio = target_tris / tris
	mod.use_collapse_triangulate = True
	bpy.ops.object.modifier_apply(modifier="dec")

# Só a textura de cor, reduzida.
for mat in obj.data.materials:
	if not mat or not mat.node_tree:
		continue
	nodes = mat.node_tree.nodes
	bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
	if bsdf is None:
		continue
	strip = ["Metallic", "Roughness", "Emission Color", "Alpha"] + ([] if "normal" in keep_maps else ["Normal"])
	for name in strip:
		socket = bsdf.inputs.get(name)
		if socket:
			for link in list(socket.links):
				mat.node_tree.links.remove(link)
	bsdf.inputs["Metallic"].default_value = 0.0
	bsdf.inputs["Roughness"].default_value = 0.85
	base = bsdf.inputs["Base Color"]
	keep = set()
	feeds = [base]
	normal = bsdf.inputs.get("Normal")
	if "normal" in keep_maps and normal and normal.links:
		nmap = normal.links[0].from_node
		keep.add(nmap.name)
		feeds += [i for i in nmap.inputs if i.links]
	for socket in feeds:
		if not socket.links:
			continue
		node = socket.links[0].from_node
		keep.add(node.name)
		if node.type == "TEX_IMAGE" and node.image:
			img = node.image
			if max(img.size) > tex_px:
				img.scale(tex_px, tex_px)
	for n in list(nodes):
		if n.type == "TEX_IMAGE" and n.name not in keep:
			nodes.remove(n)

# Escala e origem na linha d'água (centro da base).
vs = [obj.matrix_world @ v.co for v in obj.data.vertices]
mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
dims = mx - mn
reference = dims.z if axis == "z" else max(dims)
scale = size_m / reference
water = mn.z + dims.z * draft
center = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, water))
obj.data.transform(Matrix.Scale(scale, 4) @ Matrix.Translation(-center))
obj.data.update()
obj.name = "Model"
final_tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_image_format="JPEG", export_jpeg_quality=82)
print("OPT %s tris=%d dims=(%.1f %.1f %.1f) m" % (out.split("\\")[-1], final_tris, dims.x * scale, dims.y * scale, dims.z * scale))
