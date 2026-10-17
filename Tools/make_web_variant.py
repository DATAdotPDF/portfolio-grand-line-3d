"""Variante WEB de um modelo (o original fica intacto como fonte; isto só gera a cópia leve do site).

Uso (Blender em modo batch):
  blender -b --factory-startup -P Tools/make_web_variant.py -- <entrada.glb> <saida.glb> <triangulos> <textura_px> <mapas>

- triangulos: alvo total depois da redução (dividido entre as malhas pelo tamanho de cada uma).
- textura_px: lado máximo das texturas.
- mapas: "full" (cor + rugosidade/metal + normal), "color_normal" ou "color" (só a cor).
Por que não abre buracos: os modelos do Meshy vêm "soltos" nas costuras da textura; soldamos os
vértices (bem perto, sem mudar UV) antes do Decimate — sem isso cada pedaço encolhia sozinho.
Malhas com esqueleto (bichos) mantêm os pesos e as animações: o Decimate é aplicado antes do
modificador de Armature, que fica como está. Partes separadas (ilhas animadas, roda d'água) ficam
separadas e com os mesmos nomes, para o jogo continuar achando cada peça.
"""
import math
import bpy
import bmesh
import sys

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
target_tris = int(args[2])
tex_px = int(args[3])
maps = args[4] if len(args) > 4 else "color_normal"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
# Cópia da malha original de cada objeto: depois do Decimate as normais vêm dela (Data Transfer),
# então a luz cai como no modelo do Meshy, sem facetas (Pedro, 2026-10-16: "poucos polígonos").
sources = {}
for obj in meshes:
	src_obj = obj.copy()
	src_obj.data = obj.data.copy()
	src_obj.modifiers.clear()
	src_obj.name = obj.name + "__normals_src"
	bpy.context.scene.collection.objects.link(src_obj)
	sources[obj.name] = src_obj


def tri_count(obj):
	return sum(len(p.vertices) - 2 for p in obj.data.polygons)


total = sum(tri_count(o) for o in meshes) or 1
before_total = total
for obj in meshes:
	# Solda as costuras (UV fica por canto de face, a textura não muda).
	vs = obj.data.vertices
	if len(vs) == 0:
		continue
	span = max(max(v.co[i] for v in vs) - min(v.co[i] for v in vs) for i in range(3)) or 1.0
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=span * 1e-4)
	bm.to_mesh(obj.data)
	bm.free()
	tris = tri_count(obj)
	# Cada malha recebe a sua parte do orçamento; peças pequenas (que animam) guardam um mínimo.
	want = max(400, int(target_tris * tris / total))
	if tris > want:
		mod = obj.modifiers.new("web_decimate", "DECIMATE")
		mod.ratio = want / tris
		mod.use_collapse_triangulate = True
		# Antes do Armature (se houver): só o Decimate é aplicado; o esqueleto continua.
		while obj.modifiers.find("web_decimate") > 0:
			with bpy.context.temp_override(object=obj):
				bpy.ops.object.modifier_move_up(modifier="web_decimate")
		with bpy.context.temp_override(object=obj):
			bpy.ops.object.modifier_apply(modifier="web_decimate")

# Normais do original na malha reduzida: tudo liso e as normais copiadas da cópia original (canto a
# canto, pela face mais perto) — as arestas vivas do original continuam vivas.
for obj in meshes:
	src_obj = sources[obj.name]
	for poly in obj.data.polygons:
		poly.use_smooth = True
	mod = obj.modifiers.new("web_normals", "DATA_TRANSFER")
	mod.object = src_obj
	mod.use_object_transform = True
	mod.use_loop_data = True
	mod.data_types_loops = {"CUSTOM_NORMAL"}
	mod.loop_mapping = "POLYINTERP_NEAREST"
	while obj.modifiers.find("web_normals") > 0:
		with bpy.context.temp_override(object=obj):
			bpy.ops.object.modifier_move_up(modifier="web_normals")
	with bpy.context.temp_override(object=obj, active_object=obj):
		bpy.ops.object.modifier_apply(modifier="web_normals")
for src_obj in sources.values():
	bpy.data.objects.remove(src_obj, do_unlink=True)

# Texturas: reduz e tira os mapas que este nível não usa.
for mat in bpy.data.materials:
	if not mat or not mat.use_nodes:
		continue
	nodes = mat.node_tree.nodes
	bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
	if bsdf is None:
		continue
	drop = []
	if maps in ("color", "color_normal"):
		drop += ["Metallic", "Roughness"]
	if maps == "color":
		drop += ["Normal"]
	for name in drop:
		socket = bsdf.inputs.get(name)
		if socket:
			for link in list(socket.links):
				mat.node_tree.links.remove(link)
	if "Roughness" in drop:
		bsdf.inputs["Metallic"].default_value = 0.0
		bsdf.inputs["Roughness"].default_value = 0.85
for img in bpy.data.images:
	if img.size[0] > tex_px or img.size[1] > tex_px:
		img.scale(min(img.size[0], tex_px), min(img.size[1], tex_px))
# Imagens que ficaram sem uso (mapas tirados) não vão para o arquivo.
for img in list(bpy.data.images):
	if img.users == 0:
		bpy.data.images.remove(img)

after_total = sum(tri_count(o) for o in meshes)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=85,
	export_animations=True, export_skins=True, export_morph=True, export_apply=False)
print("WEB_VARIANT %s tris %d -> %d tex %d maps %s" % (out.replace("\\", "/").split("/")[-1], before_total, after_total, tex_px, maps))
