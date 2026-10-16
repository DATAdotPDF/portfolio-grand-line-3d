"""Tira os pesos pendurados (pêndulos) da chalupa segmentada do Meshy e leva para o espaço do
nosso modelo (Assets/Optimized/sloop_clean_sail.glb): mesma orientação (proa em -X), escala pela
altura/comprimento (x15,5) e origem de cada peça no ponto onde ela fica presa (topo).

Uso: blender -b --factory-startup -P Tools/extract_sloop_pendants.py -- <segmentado.glb> <saida.glb>
"""
import bpy
import sys
from mathutils import Vector, Matrix

src, out = sys.argv[sys.argv.index("--") + 1:][:2]
# Partes do Meshy: 3 e 4 = pesos na amurada; 6 e 7 = pesos na popa (perto da água).
PARTS = {"model_part3": "Pendant_RailPort", "model_part4": "Pendant_RailStarboard",
	"model_part6": "Pendant_SternPort", "model_part7": "Pendant_SternStarboard"}
SCALE = 15.5
NEW_CENTER = Vector((-0.001, 0.0, 0.0))
OLD_OFFSET = Vector((-0.02, 0.0, -0.79))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
keep = []
for o in list(bpy.context.scene.objects):
	if o.type != "MESH" or o.name not in PARTS:
		bpy.data.objects.remove(o, do_unlink=True)
		continue
	bpy.context.view_layer.objects.active = o
	for x in bpy.context.selected_objects:
		x.select_set(False)
	o.select_set(True)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
	if tris > 700:
		mod = o.modifiers.new("dec", "DECIMATE")
		mod.ratio = 700 / tris
		bpy.ops.object.modifier_apply(modifier="dec")
	o.data.transform(Matrix.Translation(OLD_OFFSET) @ Matrix.Scale(SCALE, 4) @ Matrix.Translation(-NEW_CENTER))
	# Origem no ponto de fixação (topo, centro da peça): é o pivô do pêndulo.
	vs = [v.co for v in o.data.vertices]
	top = Vector(((min(v.x for v in vs) + max(v.x for v in vs)) / 2, (min(v.y for v in vs) + max(v.y for v in vs)) / 2, max(v.z for v in vs)))
	o.data.transform(Matrix.Translation(-top))
	o.location = top
	o.data.materials.clear()
	o.name = PARTS[o.name]
	o.data.name = o.name
	keep.append(o)
	print("PENDANT %s tris=%d pivot=(%.3f %.3f %.3f)" % (o.name, sum(len(p.vertices) - 2 for p in o.data.polygons), top.x, top.y, top.z))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_materials="NONE")
