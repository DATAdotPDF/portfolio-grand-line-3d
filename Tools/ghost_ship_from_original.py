"""Navio fantasma refeito a partir do GLB ORIGINAL do Meshy (malha inteira, UVs e os 3 mapas), sem
decimar. A versão anterior (Assets/Optimized/ghost_ship.glb) tinha sido reduzida de 1,2 mi para
~23 mil triângulos e perdeu UV e texturas: o shader só pintava verde chapado. Aqui cada triângulo do
original vai para a peça mais próxima da versão antiga (GhostHull / GhostSails / GhostFlag, mesmo
alinhamento pela caixa), e as peças saem com os mesmos nomes e no mesmo espaço (o GhostShip.gd e o
shader continuam funcionando, agora com a textura de verdade).

Uso: blender -b --factory-startup -P Tools/ghost_ship_from_original.py -- <glb antigo (referência)> <saída.glb>
"""
import bmesh
import bpy
import os
import sys
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

REPO = r"D:\Godot\Projects\portifolio-pedro-ferreira-3d-2026"
ORIGINAL = os.path.join(REPO, "Assets", "Meshy_AI_ghost_pirate_ship_3d_1008204337_image-to-3d-texture.glb")
args = sys.argv[sys.argv.index("--") + 1:]
reference, out_path = args[0], args[1]


def bounds(objs):
	vs = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
	return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
		Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def select_only(objs, active=None):
	for o in bpy.context.scene.objects:
		o.select_set(False)
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = active or objs[0]


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=reference)
parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
r_mn, r_mx = bounds(parts)
before = set(bpy.context.scene.objects)
bpy.ops.import_scene.gltf(filepath=ORIGINAL)
source = [o for o in bpy.context.scene.objects if o not in before and o.type == "MESH"]
select_only(source)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if len(source) > 1:
	bpy.ops.object.join()
ship = bpy.context.view_layer.objects.active
s_mn, s_mx = bounds([ship])
# Original → espaço da versão antiga (mesma orientação; escala e centro pela caixa).
scale = max(r_mx - r_mn) / max(s_mx - s_mn)
ship.data.transform(Matrix.Translation((r_mn + r_mx) / 2) @ Matrix.Scale(scale, 4) @ Matrix.Translation(-(s_mn + s_mx) / 2))
ship.data.update()

verts, polys, owner = [], [], []
names = [o.name for o in parts]
for index, o in enumerate(parts):
	base = len(verts)
	verts.extend(o.matrix_world @ v.co for v in o.data.vertices)
	for p in o.data.polygons:
		polys.append([base + i for i in p.vertices])
		owner.append(index)
tree = BVHTree.FromPolygons(verts, polys)
assign = [names[owner[tree.find_nearest(p.center)[2]]] for p in ship.data.polygons]
for o in parts:
	bpy.data.objects.remove(o, do_unlink=True)

counts = {}
for name in names:
	if name == "GhostHull":
		continue
	select_only([ship])
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_mode(type="FACE")
	bpy.ops.mesh.select_all(action="DESELECT")
	edit = bmesh.from_edit_mesh(ship.data)
	edit.faces.ensure_lookup_table()
	for face, a in zip(edit.faces, assign):
		if a == name:
			face.select_set(True)
	edit.select_flush_mode()
	bmesh.update_edit_mesh(ship.data)
	bpy.ops.mesh.separate(type="SELECTED")
	bpy.ops.object.mode_set(mode="OBJECT")
	piece = [o for o in bpy.context.selected_objects if o != ship][0]
	piece.name = name
	piece.data.name = name
	counts[name] = len(piece.data.polygons)
	assign = [a for a in assign if a != name]
ship.name = "GhostHull"
ship.data.name = "GhostHull"
counts["GhostHull"] = len(ship.data.polygons)
select_only([o for o in bpy.context.scene.objects if o.type == "MESH"])
bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True, export_image_format="AUTO")
print("GHOST_SHIP", counts, round(os.path.getsize(out_path) / 1e6, 1), "MB")
