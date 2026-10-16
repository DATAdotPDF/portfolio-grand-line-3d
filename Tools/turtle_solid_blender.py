"""Tartaruga gigante INTEIRA (Meshy_AI_swimming_stone_turtle, já em pose de nado, como o conceito
References/2D/Meshy_AI_stone-turtle-swimming-rig-concept.png) riggada e animada no Blender.

Uso: blender -b --factory-startup -P Tools/turtle_solid_blender.py -- <saída.glb> [render_dir]

- Malha original (sem decimar), materiais originais; só solda vértices exatamente sobrepostos.
- Frente = +Y (cabeça), tamanho original (o jogo escala).
- Ossos (medidos na vista de cima/lado com grade de 0,1): Root no casco; Neck_01 → Neck_02 → Head;
  cada nadadeira ombro/quadril → meio → ponta (Flipper_XX_01, _02).
- Pesos POR REGIÃO: dentro do disco do casco (raio 0,5 em volta de (0, -0,19)) tudo 100% Root — casco
  e ilha não se mexem com os membros; fora dele, cada vértice vai para a cadeia do membro mais perto,
  com gradiente suave ao longo dela (que começa dentro do casco, então a raiz mistura com o Root).
- Clipe "Swim" (4 s, loop): dianteiras em remada longa de "voo" (desce varrendo para trás com a lâmina
  chapada, volta emplumada, o meio e a ponta atrasados = lâmina flexível), traseiras de leme, pescoço
  balançando e a cabeça olhando em volta, casco rolando de leve.
"""
import bpy
import bmesh
import glob
import math
import os
import sys
from mathutils import Vector, Matrix, Quaternion

REPO = r"D:\Godot\Projects\portifolio-pedro-ferreira-3d-2026"
SOURCE = glob.glob(os.path.join(REPO, "Assets", "Meshy_AI_swimming_stone_turtle_*.glb"))[0]
args = sys.argv[sys.argv.index("--") + 1:]
OUT = args[0]
RENDER = args[1] if len(args) > 1 else ""
FPS = 30
SHELL_CENTER = Vector((0.0, -0.19))
SHELL_R = 0.50

V = lambda x, y, z: Vector((x, y, z))
# Cadeias: (ossos, pontos). O primeiro ponto fica dentro do casco (o primeiro "osso" da cadeia é o Root).
CHAINS = {
	"Neck": (["Root", "Neck_01", "Neck_02", "Head"], [V(0, 0.22, -0.15), V(0, 0.36, -0.14), V(0.02, 0.47, -0.03), V(0.05, 0.56, 0.06), V(0.11, 0.80, 0.05)]),
	"FR": (["Root", "Flipper_FR_01", "Flipper_FR_02"], [V(0.08, 0.2, -0.22), V(0.19, 0.32, -0.25), V(0.60, 0.41, -0.30), V(0.95, 0.27, -0.33)]),
	"FL": (["Root", "Flipper_FL_01", "Flipper_FL_02"], [V(-0.08, 0.2, -0.22), V(-0.19, 0.32, -0.25), V(-0.58, 0.45, -0.30), V(-0.94, 0.30, -0.33)]),
	"RR": (["Root", "Flipper_RR_01", "Flipper_RR_02"], [V(0.32, -0.42, -0.28), V(0.44, -0.52, -0.30), V(0.59, -0.58, -0.32), V(0.75, -0.70, -0.34)]),
	"RL": (["Root", "Flipper_RL_01", "Flipper_RL_02"], [V(-0.32, -0.42, -0.28), V(-0.44, -0.52, -0.30), V(-0.60, -0.62, -0.32), V(-0.76, -0.69, -0.34)]),
}


def select_only(objs, active=None):
	for o in bpy.context.scene.objects:
		o.select_set(False)
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = active or objs[0]


def load():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.context.scene.render.fps = FPS
	bpy.ops.import_scene.gltf(filepath=SOURCE)
	meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
	select_only(meshes)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	if len(meshes) > 1:
		bpy.ops.object.join()
	mesh = bpy.context.view_layer.objects.active
	for o in list(bpy.context.scene.objects):
		if o != mesh:
			bpy.data.objects.remove(o, do_unlink=True)
	mesh.parent = None
	# Cabeça para +Y; origem no centro da caixa.
	mesh.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
	vs = [v.co for v in mesh.data.vertices]
	mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
	mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
	mesh.data.transform(Matrix.Translation(-(mn + mx) / 2))
	bm = bmesh.new()
	bm.from_mesh(mesh.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
	bm.to_mesh(mesh.data)
	bm.free()
	mesh.name = "Turtle"
	mesh.data.name = "Turtle"
	return mesh, (mn + mx) / 2


def build_rig(offset):
	"""offset: centro da caixa original (os pontos medidos estão no espaço antes de centrar)."""
	data = bpy.data.armatures.new("TurtleRig")
	rig = bpy.data.objects.new("TurtleRig", data)
	bpy.context.scene.collection.objects.link(rig)
	select_only([rig])
	bpy.ops.object.mode_set(mode="EDIT")
	root = data.edit_bones.new("Root")
	root.head = V(0, -0.19, -0.15) - offset
	root.tail = V(0, 0.15, -0.15) - offset
	made = {"Root": root}
	for key, (names, pts) in CHAINS.items():
		for i, name in enumerate(names[1:], start=1):
			eb = data.edit_bones.new(name)
			eb.head = pts[i] - offset
			eb.tail = pts[i + 1] - offset
			eb.parent = made[names[i - 1]] if i > 1 else root
			eb.use_connect = i > 1
			made[name] = eb
	bpy.ops.object.mode_set(mode="OBJECT")
	for pb in rig.pose.bones:
		pb.rotation_mode = "QUATERNION"
	return rig


def weights(mesh, rig, offset):
	select_only([mesh, rig], rig)
	bpy.ops.object.parent_set(type="ARMATURE_NAME")
	groups = {g.name: g for g in mesh.vertex_groups}
	chains = {k: (names, [p - offset for p in pts]) for k, (names, pts) in CHAINS.items()}
	center = Vector((SHELL_CENTER.x - offset.x, SHELL_CENTER.y - offset.y))
	counts = {}
	for v in mesh.data.vertices:
		co = v.co
		r = (Vector((co.x, co.y)) - center).length
		best = None
		if r >= SHELL_R:
			for key, (names, pts) in chains.items():
				for j in range(len(pts) - 1):
					seg = pts[j + 1] - pts[j]
					k = max(0.0, min(1.0, (co - pts[j]).dot(seg) / seg.length_squared))
					d = (co - (pts[j] + seg * k)).length
					if best is None or d < best[0]:
						best = (d, key, j, k)
		# Casco/ilha (ou borda do casco longe de qualquer membro): rígido no Root.
		if best is None or (best[0] > 0.14 and r < SHELL_R + 0.1):
			groups["Root"].add([v.index], 1.0, "REPLACE")
			counts["Root"] = counts.get("Root", 0) + 1
			continue
		_, key, j, k = best
		names, pts = chains[key]
		# Gradiente entre o osso do segmento e o vizinho (a meio caminho fica 50/50, nas pontas 100%).
		if k < 0.5 and j > 0:
			u = 0.5 + k
			a, b = names[j - 1], names[j]
		elif k >= 0.5 and j < len(names) - 1:
			u = k - 0.5
			a, b = names[j], names[j + 1]
		else:
			u = 0.0
			a = b = names[j]
		u = u * u * (3 - 2 * u)
		groups[a].add([v.index], 1.0 - u, "REPLACE")
		if b != a and u > 0.001:
			groups[b].add([v.index], u, "ADD")
		counts[names[j]] = counts.get(names[j], 0) + 1
	return counts


def key_world(rig, frame, pose):
	for pb in rig.pose.bones:
		q = Quaternion()
		rest = pb.bone.matrix_local.to_3x3()
		for axis, deg in pose.get(pb.name, []):
			local = (rest.inverted() @ Vector(axis)).normalized()
			q = Quaternion(local, math.radians(deg)) @ q
		pb.rotation_quaternion = q
		pb.keyframe_insert("rotation_quaternion", frame=frame)


def animate(rig):
	frames = 120
	X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
	for f in range(0, frames + 1, 2):
		s = f / frames
		# Dianteiras: descida 0-0,55 (força, varre para trás, lâmina chapada), volta emplumada.
		if s < 0.55:
			u = 0.5 - 0.5 * math.cos(math.pi * s / 0.55)
			flap = -16 + 40 * u            # direita: negativo = ponta para cima
			sweep = 14 - 36 * u            # direita: positivo = para a frente
			feather = 0.0
		else:
			u = 0.5 - 0.5 * math.cos(math.pi * (s - 0.55) / 0.45)
			flap = 24 - 40 * u
			sweep = -22 + 36 * u
			feather = 32 * math.sin(math.pi * (s - 0.55) / 0.45)
		lag = math.sin(2 * math.pi * s - 0.9)  # meio/ponta atrasados (lâmina flexível)
		fr_axis = (CHAINS["FR"][1][2] - CHAINS["FR"][1][1]).normalized()
		fl_axis = (CHAINS["FL"][1][2] - CHAINS["FL"][1][1]).normalized()
		pose = {
			"Flipper_FR_01": [(fr_axis, -feather), (Z, sweep), (Y, flap)],
			"Flipper_FR_02": [(Y, 10 * lag), (Z, -6 * lag)],
			"Flipper_FL_01": [(fl_axis, -feather), (Z, -sweep), (Y, -flap)],
			"Flipper_FL_02": [(Y, -10 * lag), (Z, 6 * lag)],
		}
		# Traseiras: leme, remada curta defasada.
		paddle = 9 * math.sin(2 * math.pi * s - 1.2)
		pose["Flipper_RR_01"] = [(Z, paddle), (Y, 5 * math.sin(2 * math.pi * s))]
		pose["Flipper_RR_02"] = [(Z, 5 * math.sin(2 * math.pi * s - 2.0))]
		pose["Flipper_RL_01"] = [(Z, -paddle), (Y, -5 * math.sin(2 * math.pi * s))]
		pose["Flipper_RL_02"] = [(Z, -5 * math.sin(2 * math.pi * s - 2.0))]
		# Pescoço balançando devagar, cabeça olhando em volta.
		pose["Neck_01"] = [(Z, 5 * math.sin(2 * math.pi * s)), (X, 2 * math.sin(4 * math.pi * s))]
		pose["Neck_02"] = [(Z, 5 * math.sin(2 * math.pi * s - 0.6))]
		pose["Head"] = [(Z, 14 * math.sin(2 * math.pi * s + 1.3)), (X, 4 * math.sin(4 * math.pi * s + 0.5))]
		# Casco: rola e arfa de leve junto da remada.
		pose["Root"] = [(Y, 1.5 * math.sin(2 * math.pi * s)), (X, 1.0 * math.sin(2 * math.pi * s - 0.6))]
		key_world(rig, f, pose)
	ad = rig.animation_data
	action = ad.action
	action.name = "Swim"
	track = ad.nla_tracks.new()
	track.name = "Swim"
	track.strips.new("Swim", 0, action)
	ad.action = None
	for pb in rig.pose.bones:
		pb.rotation_quaternion = Quaternion()


def render(rig, folder):
	os.makedirs(folder, exist_ok=True)
	sc = bpy.context.scene
	sc.render.engine = "BLENDER_WORKBENCH"
	sc.display.shading.color_type = "TEXTURE"
	sc.render.resolution_x = 520
	sc.render.resolution_y = 400
	cd = bpy.data.cameras.new("v")
	cam = bpy.data.objects.new("v", cd)
	sc.collection.objects.link(cam)
	sc.camera = cam
	cd.type = "ORTHO"
	cd.ortho_scale = 2.3
	track = rig.animation_data.nla_tracks[0]
	for view, loc in {"front": (0, 6, 0.6), "three_q": (4, 3.5, 3)}.items():
		cam.location = loc
		cam.rotation_euler = (Vector((0, 0, -0.1)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
		for f in (0, 30, 66, 96):
			sc.frame_set(f)
			sc.render.filepath = os.path.join(folder, "solid_%s_%03d.png" % (view, f))
			bpy.ops.render.render(write_still=True)
	sc.frame_set(0)
	bpy.data.objects.remove(cam, do_unlink=True)


mesh, offset = load()
rig = build_rig(offset)
counts = weights(mesh, rig, offset)
animate(rig)
if RENDER:
	render(rig, RENDER)
select_only([mesh, rig], rig)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
	export_image_format="AUTO", export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
	export_frame_step=1, export_skins=True, export_morph=True, export_def_bones=True)
print("TURTLE_SOLID", {k: counts[k] for k in sorted(counts)}, "offset", tuple(round(x, 3) for x in offset),
	round(os.path.getsize(OUT) / 1e6, 1), "MB")
