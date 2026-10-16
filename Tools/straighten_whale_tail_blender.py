"""Endireita a cauda da baleia colosso no REPOUSO do rig do Meshy (o arquivo-fonte "(WITH RIG)…").

Pedro quer a cauda reta (horizontal) como pose de repouso: a animação (animate_meshy_rigs_blender.py,
anim_whale) bate de -45° a +45° em volta dela. Gira cada osso da cauda, da base para a ponta, até
a horizontal (mantém o rumo para os lados), grava a forma na malha (aplica o Armature e põe de novo)
e salva a pose como repouso. Esqueleto, nomes, pesos e texturas continuam os mesmos.
Uso: blender -b --factory-startup -P Tools/straighten_whale_tail_blender.py -- <fonte.glb> <saida.glb>
"""
import math
import sys

import bpy
from mathutils import Vector

TAIL = ["Bone_018", "Bone_017", "Bone_016", "Bone_015", "Bone_014"]

src, out = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")


def incline(pb):
	d = (rig.matrix_world.to_3x3() @ (pb.tail - pb.head)).normalized()
	return math.degrees(math.asin(max(-1.0, min(1.0, d.z))))


bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
before = {n: incline(rig.pose.bones[n]) for n in TAIL}
for name in TAIL:
	pb = rig.pose.bones[name]
	bpy.context.view_layer.update()
	world = rig.matrix_world.to_3x3()
	d = (world @ (pb.tail - pb.head)).normalized()
	flat = Vector((d.x, d.y, 0.0)).normalized()
	# Rotação no mundo que leva a direção atual para a horizontal, levada para o espaço do osso.
	q_world = d.rotation_difference(flat)
	bone_world = (rig.matrix_world @ pb.matrix).to_quaternion()
	q_local = bone_world.inverted() @ q_world @ bone_world
	pb.rotation_mode = "QUATERNION"
	pb.rotation_quaternion = q_local @ pb.rotation_quaternion
bpy.context.view_layer.update()
after_pose = {n: incline(rig.pose.bones[n]) for n in TAIL}
bpy.ops.object.mode_set(mode="OBJECT")

# Grava a forma endireitada na malha e põe o Armature de novo (mesmos vertex groups).
mod = next(m for m in mesh.modifiers if m.type == "ARMATURE")
mod_name = mod.name
bpy.context.view_layer.objects.active = mesh
with bpy.context.temp_override(object=mesh, active_object=mesh):
	bpy.ops.object.modifier_apply(modifier=mod_name)
new_mod = mesh.modifiers.new("Armature", "ARMATURE")
new_mod.object = rig

# A pose reta vira o repouso.
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.pose.select_all(action="SELECT")
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode="OBJECT")
rest = {}
for name in TAIL:
	b = rig.data.bones[name]
	d = (rig.matrix_world.to_3x3() @ (b.tail_local - b.head_local)).normalized()
	rest[name] = math.degrees(math.asin(max(-1.0, min(1.0, d.z))))

for o in bpy.context.scene.objects:
	o.select_set(o in (rig, mesh))
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_skins=True,
	export_animations=False, export_apply=False, export_image_format="AUTO")
print("WHALE_TAIL antes=%s pose=%s repouso=%s" % ({k: round(v, 1) for k, v in before.items()},
	{k: round(v, 1) for k, v in after_pose.items()}, {k: round(v, 1) for k, v in rest.items()}))
