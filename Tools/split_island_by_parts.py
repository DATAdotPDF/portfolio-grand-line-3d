"""Ilha texturizada (uma malha, UVs e os 3 mapas do Meshy) + ilha segmentada do Meshy (partes, sem
textura) → GLB com a malha ORIGINAL cortada nas mesmas partes. Sem bake: cada triângulo da original
vai para a parte segmentada mais próxima (BVH, a partir do centro do triângulo) e mantém UV,
materiais e texturas. As partes saem com os nomes da segmentada (model_partN), com os vértices no
espaço da ilha (origem da ilha), como o IslandEffects espera.

Uso: blender -b --factory-startup -P Tools/split_island_by_parts.py -- <segmentada.glb> <texturizada.glb> <saida.glb>
"""
import bmesh
import bpy
import sys
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:]
seg_path, tex_path, out_path = args[0], args[1], args[2]


def bounds(objs):
	vs = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
	mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
	mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
	return mn, mx


def select_only(objs, active=None):
	for o in bpy.context.scene.objects:
		o.select_set(False)
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = active or objs[0]


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=tex_path)
source = [o for o in bpy.context.scene.objects if o.type == "MESH"]
select_only(source)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if len(source) > 1:
	bpy.ops.object.join()
src = bpy.context.view_layer.objects.active
s_mn, s_mx = bounds([src])

before = set(bpy.context.scene.objects)
bpy.ops.import_scene.gltf(filepath=seg_path)
parts = [o for o in bpy.context.scene.objects if o not in before and o.type == "MESH"]
select_only(parts)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# Mesmo alinhamento pela caixa usado no bake (a segmentada vem com outra escala/centro).
p_mn, p_mx = bounds(parts)
scale = max(s_mx - s_mn) / max(p_mx - p_mn)
xf = Matrix.Translation((s_mn + s_mx) / 2) @ Matrix.Scale(scale, 4) @ Matrix.Translation(-(p_mn + p_mx) / 2)

# Uma BVH com todas as partes; cada polígono lembra de qual parte veio.
verts, polys, owner = [], [], []
for index, o in enumerate(parts):
	base = len(verts)
	verts.extend(xf @ v.co for v in o.data.vertices)
	for p in o.data.polygons:
		polys.append([base + i for i in p.vertices])
		owner.append(index)
tree = BVHTree.FromPolygons(verts, polys)

mesh = src.data
assign = []
for p in mesh.polygons:
	hit = tree.find_nearest(p.center)
	assign.append(owner[hit[2]] if hit[2] is not None else 0)
names = [o.name for o in parts]
for o in parts:
	bpy.data.objects.remove(o, do_unlink=True)

# Separa por parte (seleção de faces), mantendo UV, materiais e normais da original.
select_only([src])
pieces = {}
for index in sorted(set(assign)):
	select_only([src])
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_mode(type="FACE")
	bpy.ops.mesh.select_all(action="DESELECT")
	edit = bmesh.from_edit_mesh(src.data)
	edit.faces.ensure_lookup_table()
	for face, a in zip(edit.faces, assign):
		if a == index:
			face.select_set(True)
	edit.select_flush_mode()
	bmesh.update_edit_mesh(src.data)
	bpy.ops.mesh.separate(type="SELECTED")
	bpy.ops.object.mode_set(mode="OBJECT")
	piece = [o for o in bpy.context.selected_objects if o != src][0]
	piece.name = names[index]
	piece.data.name = names[index]
	pieces[names[index]] = len(piece.data.polygons)
	# A original perdeu essas faces: refaz a lista de donos para o que sobrou.
	assign = [a for a in assign if a != index]
bpy.data.objects.remove(src, do_unlink=True)

select_only(list(bpy.context.scene.objects))
bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True, export_image_format="AUTO")
print("ISLAND_SPLIT %s parts=%d %s" % (out_path.replace("\\", "/").split("/")[-1], len(pieces), " ".join("%s:%d" % kv for kv in sorted(pieces.items()))))
