"""Tartaruga gigante modular (Meshy, peças separadas) montada e animada no Blender.

Uso: blender -b --factory-startup -P Tools/turtle_assemble_blender.py -- <saída.glb> [render_dir] [--no-anim]

Peças (Assets/): casco-ilha com anéis no aro, pescoço com bola na base, cabeça com bola atrás,
nadadeiras dianteira/traseira com bola na raiz. Medidas tiradas da própria malha
(Builds/Creatures, análise dos anéis e ajuste de esfera nas bolas):
  - anéis do casco a ~0,90 do centro, altura -0,22, furo com raio ~0,085: pescoço em 89° (+Y = frente),
    nadadeiras nas diagonais (43°/135° dianteiras, 315°/223° traseiras); 268° (cauda) fica vazio; os
    toquinhos a 0° e 180° são as bicas de onde sai a água (cachoeiras no Godot);
  - escala de cada peça pela bola caber no furo do anel (nadadeiras, pescoço); cabeça pela proporção
    do conceito (mais ou menos a largura do pescoço).
A cabeça do Meshy já vem com o bico de baixo (boca aberta): a mandíbula é recortada dela mesma (mesma
textura, encaixe perfeito) e articulada no canto da boca; o arquivo de mandíbula separado ficaria
duplicado e não cabe nesta cabeça.
Peças rígidas girando nas juntas (sem deformação de osso); pivô exatamente no centro de cada bola.
Hierarquia: Shell → Neck → Head → Jaw; Shell → 4 nadadeiras. Clipe "Swim" (8 s, loop).
Malhas e materiais originais, sem decimar.
"""
import bpy
import bmesh
import glob
import math
import os
import sys
from mathutils import Vector, Matrix, Quaternion

REPO = r"D:\Godot\Projects\portifolio-pedro-ferreira-3d-2026"
ASSETS = os.path.join(REPO, "Assets")
args = sys.argv[sys.argv.index("--") + 1:]
OUT = args[0]
RENDER = args[1] if len(args) > 1 and not args[1].startswith("--") else ""
ANIM = "--no-anim" not in args
FPS = 30

# Juntas medidas em cada peça (unidades da peça): centro da bola, escala, ponto da outra ponta.
FRONT = {"file": "Meshy_AI_modular_turtle_front__*.glb", "ball": Vector((0.728, 0.2883, 0.4979)), "scale": 0.50}
REAR = {"file": "Meshy_AI_modular_turtle_rear_f_*.glb", "ball": Vector((-0.7848, 0.1199, 0.3558)), "scale": 0.36}
NECK = {"file": "Meshy_AI_modular_turtle_neck_3_*.glb", "ball": Vector((-0.70, 0.0, 0.05)), "end": Vector((0.95, 0.0, 0.0)), "scale": 0.335}
HEAD = {"file": "Meshy_AI_modular_turtle_head_3_*.glb", "ball": Vector((0.0, 0.816, 0.03)), "scale": 0.33,
	# boca: linha do bico de cima (y -0,95 → z 0,0; y 0,15 → z -0,13); canto (dobradiça) em y 0,12, z -0,15
	"mouth": ((-0.95, 0.0), (0.15, -0.13)), "hinge": Vector((0.0, 0.12, -0.15))}
SHELL = "Meshy_AI_modular_turtle_shell__*.glb"
SOCKET_R = 0.91
SOCKET_Z = -0.22


def socket(angle_deg):
	a = math.radians(angle_deg)
	return Vector((SOCKET_R * math.cos(a), SOCKET_R * math.sin(a), SOCKET_Z))


def import_part(pattern, name):
	before = set(bpy.context.scene.objects)
	bpy.ops.import_scene.gltf(filepath=glob.glob(os.path.join(ASSETS, pattern))[0])
	objs = [o for o in bpy.context.scene.objects if o not in before]
	meshes = [o for o in objs if o.type == "MESH"]
	for o in bpy.context.scene.objects:
		o.select_set(False)
	for o in meshes:
		o.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	if len(meshes) > 1:
		bpy.ops.object.join()
	obj = bpy.context.view_layer.objects.active
	obj.parent = None
	for o in objs:
		if o != obj and o.name in bpy.data.objects:
			bpy.data.objects.remove(o, do_unlink=True)
	obj.name = name
	obj.data.name = name
	return obj


def frame(axis, up):
	a = axis.normalized()
	u = (up - a * up.dot(a)).normalized()
	return Matrix((a, u, a.cross(u))).transposed()


def place(obj, joint_part, axis_part, up_part, joint_world, axis_world, up_world, scale):
	"""Leva a peça para o mundo: a bola (joint) vai para joint_world, o eixo da peça para axis_world."""
	rot = frame(axis_world, up_world) @ frame(axis_part, up_part).transposed()
	m = Matrix.Translation(joint_world) @ rot.to_4x4() @ Matrix.Scale(scale, 4) @ Matrix.Translation(-joint_part)
	obj.data.transform(m)
	set_pivot(obj, joint_world)


def set_pivot(obj, point):
	obj.data.transform(Matrix.Translation(-point))
	obj.location = point
	obj.data.update()


def blade(obj, joint):
	"""Eixo da nadadeira (bola → ponta mais distante) e normal da lâmina (menor variação)."""
	cos = [v.co for v in obj.data.vertices]
	tip = max(cos, key=lambda c: (c - joint).length)
	axis = (tip - joint).normalized()
	n = len(cos)
	mean = sum(cos, Vector()) / n
	import numpy as np
	arr = np.array([c - mean for c in cos[::7]])
	_, _, vt = np.linalg.svd(arr, full_matrices=False)
	normal = Vector(vt[2])
	return axis, normal


def place_blade(obj, joint, axis_p, normal_p, joint_world, axis_world, scale, bulge_world):
	"""Como place(), mas escolhe o lado da lâmina: o centroide da nadadeira (a parte larga) fica para o
	lado bulge_world (trás nas dianteiras, fora nas traseiras) — com o lado errado ela fica 'ao contrário'."""
	cos = [v.co for i, v in enumerate(obj.data.vertices) if i % 11 == 0]
	centroid = sum(cos, Vector()) / len(cos)
	best = None
	for sign in (1, -1):
		rot = frame(axis_world, Vector((0, 0, 1))) @ frame(axis_p, normal_p * sign).transposed()
		offset = rot @ (centroid - joint)
		offset -= axis_world.normalized() * offset.dot(axis_world.normalized())
		score = offset.dot(bulge_world)
		if best is None or score > best[0]:
			best = (score, sign)
	place(obj, joint, axis_p, normal_p * best[1], joint_world, axis_world, Vector((0, 0, 1)), scale)


def mirror_copy(obj, name):
	"""Cópia espelhada em X (mundo), com a malha própria e normais acertadas."""
	bpy.context.view_layer.update()
	copy = obj.copy()
	copy.data = obj.data.copy()
	copy.name = name
	copy.data.name = name
	bpy.context.scene.collection.objects.link(copy)
	world = obj.matrix_world.copy()
	copy.data.transform(world)
	copy.matrix_world = Matrix.Identity(4)
	copy.data.transform(Matrix.Scale(-1, 4, Vector((1, 0, 0))))
	bm = bmesh.new()
	bm.from_mesh(copy.data)
	bmesh.ops.reverse_faces(bm, faces=bm.faces)
	bm.to_mesh(copy.data)
	bm.free()
	pivot = obj.location.copy()
	pivot.x = -pivot.x
	set_pivot(copy, pivot)
	return copy


def cut_jaw(head):
	"""Recorta o bico de baixo da própria cabeça (abaixo da linha da boca, à frente do canto)."""
	(y0, z0), (y1, z1) = HEAD["mouth"]
	def below(c):
		zline = z0 + (z1 - z0) * (c.y - y0) / (y1 - y0)
		return c.y < y1 and c.z < zline - 0.01
	bpy.ops.object.select_all(action="DESELECT")
	head.select_set(True)
	bpy.context.view_layer.objects.active = head
	bpy.ops.object.mode_set(mode="EDIT")
	bm = bmesh.from_edit_mesh(head.data)
	for f in bm.faces:
		f.select_set(below(f.calc_center_median()))
	bm.select_flush_mode()
	bmesh.update_edit_mesh(head.data)
	bpy.ops.mesh.separate(type="SELECTED")
	bpy.ops.object.mode_set(mode="OBJECT")
	jaw = [o for o in bpy.context.selected_objects if o != head][0]
	jaw.name = "Jaw"
	jaw.data.name = "Jaw"
	return jaw


def parent(child, parent_obj):
	# matrix_world só é recalculada no update: sem ele a peça voltava para a origem.
	bpy.context.view_layer.update()
	world = child.matrix_world.copy()
	child.parent = parent_obj
	child.matrix_world = world


def build():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.context.scene.render.fps = FPS
	shell = import_part(SHELL, "Shell")
	# Pescoço: eixo +X da peça para a frente, subindo.
	neck = import_part(NECK["file"], "Neck")
	# 38°: o pescoço sai do anel embaixo d'água (metade da tartaruga fica submersa) e a cabeça
	# precisa sair inteira da água.
	pitch = math.radians(38)
	neck_axis = Vector((0, math.cos(pitch), math.sin(pitch)))
	neck_up = Vector((0, -math.sin(pitch), math.cos(pitch)))
	place(neck, NECK["ball"], Vector((1, 0, 0)), Vector((0, 0, 1)), socket(89.3), neck_axis, neck_up, NECK["scale"])
	neck_end = neck.matrix_world @ (Matrix.Scale(NECK["scale"], 4) @ (NECK["end"] - NECK["ball"]))
	neck_end = socket(89.3) + neck_axis * ((NECK["end"] - NECK["ball"]).length * NECK["scale"] * 0.96)
	# Cabeça: frente (-Y da peça) olhando para a frente, um pouco para baixo; mandíbula recortada dela.
	head = import_part(HEAD["file"], "Head")
	jaw = cut_jaw(head)
	look = math.radians(-6)
	head_axis = Vector((0, math.cos(look), math.sin(look)))
	head_up = Vector((0, -math.sin(look), math.cos(look)))
	rot_part = (Vector((0, -1, 0)), Vector((0, 0, 1)))
	place(head, HEAD["ball"], rot_part[0], rot_part[1], neck_end, head_axis, head_up, HEAD["scale"])
	# A mandíbula segue a mesma transformação da cabeça, com o pivô no canto da boca.
	rot = frame(head_axis, head_up) @ frame(rot_part[0], rot_part[1]).transposed()
	m = Matrix.Translation(neck_end) @ rot.to_4x4() @ Matrix.Scale(HEAD["scale"], 4) @ Matrix.Translation(-HEAD["ball"])
	jaw.data.transform(m)
	set_pivot(jaw, m @ HEAD["hinge"])
	# Nadadeiras: a direita (x+) é posicionada; a esquerda é o espelho.
	front = import_part(FRONT["file"], "Flipper_FR")
	axis_p, normal_p = blade(front, FRONT["ball"])
	# Como na referência (Meshy_AI_swimming_stone_turtle): dianteiras abertas para o lado e um pouco
	# para a frente (15° a partir do lado), baixas (pontas descem ~14°), chapadas.
	fr_dir = Vector((math.cos(math.radians(15)), math.sin(math.radians(15)), -0.25)).normalized()
	place_blade(front, FRONT["ball"], axis_p, normal_p, socket(43), fr_dir, FRONT["scale"], Vector((0, -1, 0)))
	rear = import_part(REAR["file"], "Flipper_RR")
	axis_r, normal_r = blade(rear, REAR["ball"])
	# Traseiras: para trás e para fora (300°), chapadas, de leme.
	rr_dir = Vector((math.cos(math.radians(300)), math.sin(math.radians(300)), -0.15)).normalized()
	place_blade(rear, REAR["ball"], axis_r, normal_r, socket(315), rr_dir, REAR["scale"], Vector((1, 0, 0)))
	fl = mirror_copy(front, "Flipper_FL")
	rl = mirror_copy(rear, "Flipper_RL")
	for child in (neck, front, rear, fl, rl):
		parent(child, shell)
	parent(head, neck)
	parent(jaw, head)
	return {"shell": shell, "neck": neck, "head": head, "jaw": jaw, "FR": front, "FL": fl, "RR": rear, "RL": rl}


def key_rot(obj, frame_no, rotations, location=None):
	"""rotations: [(eixo no espaço do pai, graus)] somadas sobre a pose de repouso."""
	q = Quaternion()
	for axis, deg in rotations:
		q = Quaternion(Vector(axis).normalized(), math.radians(deg)) @ q
	obj.rotation_mode = "QUATERNION"
	obj.rotation_quaternion = q
	obj.keyframe_insert("rotation_quaternion", frame=frame_no)
	if location is not None:
		obj.location = location
		obj.keyframe_insert("location", frame=frame_no)


def animate(parts):
	"""Swim (8 s = 2 braçadas): dianteiras em voo (desce varrendo para trás com a lâmina chapada,
	volta de lado/emplumada), traseiras de leme com remada curta, pescoço balançando devagar e cabeça
	olhando em volta, boca abrindo uma vez, casco subindo/descendo e rolando junto da braçada."""
	frames = 240
	stroke = 120                                    # uma remada a cada 4 s
	shell = parts["shell"]
	rest_shell = shell.location.copy()
	fr_axis = (parts["FR"].matrix_world.to_3x3() @ Vector((1, 0, 0)))  # só para ter um vetor; não usado
	for f in range(0, frames + 1, 3):
		t = f / frames
		s = (f % stroke) / stroke                   # fase da braçada 0..1
		# Dianteiras (tartaruga MARINHA, embaixo d'água, dentro do limite da bola no anel): remada lenta,
		# descida varrendo para trás com a lâmina chapada (força) e volta para a frente de lado (emplumada).
		if s < 0.55:
			u = 0.5 - 0.5 * math.cos(math.pi * s / 0.55)
			flap = 10 - 25 * u                                         # +10 → -15 (desce)
			sweep = 12 - 32 * u                                        # frente → trás
			feather = 0.0
		else:
			u = 0.5 - 0.5 * math.cos(math.pi * (s - 0.55) / 0.45)
			flap = -15 + 25 * u
			sweep = -20 + 32 * u
			feather = 35 * math.sin(math.pi * (s - 0.55) / 0.45)       # vira de lado na volta
		fr_long = Vector((math.cos(math.radians(15)), math.sin(math.radians(15)), -0.25)).normalized()
		key_rot(parts["FR"], f, [(fr_long, -feather), (Vector((0, 0, 1)), sweep), (Vector((0, 1, 0)), -flap)])
		key_rot(parts["FL"], f, [(Vector((-fr_long.x, fr_long.y, fr_long.z)), feather), (Vector((0, 0, 1)), -sweep), (Vector((0, 1, 0)), flap)])
		# Traseiras: leme com remada curta, defasada.
		paddle = 7 * math.sin(2 * math.pi * s - 1.2)
		rudder = 4 * math.sin(2 * math.pi * t)
		key_rot(parts["RR"], f, [(Vector((0, 0, 1)), rudder + paddle), (Vector((0, 1, 0)), 5 * math.sin(2 * math.pi * s))])
		key_rot(parts["RL"], f, [(Vector((0, 0, 1)), rudder - paddle), (Vector((0, 1, 0)), -5 * math.sin(2 * math.pi * s))])
		# Pescoço: balanço lento; cabeça olhando em volta (eixos no espaço do pai em repouso).
		key_rot(parts["neck"], f, [(Vector((0, 0, 1)), 7 * math.sin(2 * math.pi * t)), (Vector((1, 0, 0)), 3 * math.sin(2 * math.pi * s))])
		look = 16 * math.sin(2 * math.pi * t * 1.0 + 1.3) * (0.6 + 0.4 * math.sin(2 * math.pi * t * 2))
		key_rot(parts["head"], f, [(Vector((0, 0, 1)), look), (Vector((1, 0, 0)), 4 * math.sin(2 * math.pi * t * 2 + 0.5))])
		# Boca: abre uma vez por ciclo (quadros 150-200).
		open_amt = max(0.0, math.sin(math.pi * (f - 150) / 50)) if 150 <= f <= 200 else 0.0
		key_rot(parts["jaw"], f, [(Vector((1, 0, 0)), -14 * open_amt)])
		# Casco: sobe na descida das nadadeiras, rola de leve e arfa junto.
		bob = 0.012 * math.sin(2 * math.pi * s - 0.6)
		key_rot(shell, f, [(Vector((0, 1, 0)), 1.6 * math.sin(2 * math.pi * t)), (Vector((1, 0, 0)), 1.2 * math.sin(2 * math.pi * s))],
			rest_shell + Vector((0, 0, bob)))
	for obj in parts.values():
		ad = obj.animation_data
		if ad and ad.action:
			action = ad.action
			action.name = "Swim_%s" % obj.name
			track = ad.nla_tracks.new()
			track.name = "Swim"
			track.strips.new("Swim", 0, action)
			ad.action = None
	bpy.context.scene.frame_set(0)


def render_views(parts, folder):
	os.makedirs(folder, exist_ok=True)
	sc = bpy.context.scene
	sc.render.engine = "BLENDER_WORKBENCH"
	sc.display.shading.light = "STUDIO"
	sc.display.shading.color_type = "TEXTURE"
	sc.render.resolution_x = 700
	sc.render.resolution_y = 520
	cd = bpy.data.cameras.new("view")
	cam = bpy.data.objects.new("view", cd)
	sc.collection.objects.link(cam)
	sc.camera = cam
	cd.type = "ORTHO"
	cd.ortho_scale = 3.2
	for name, loc in {"top": (0, 0.001, 6), "side": (6, 0, 0.5), "front": (0, 6, 0.8), "three_q": (4, 3.5, 3)}.items():
		cam.location = loc
		cam.rotation_euler = (Vector((0, 0, -0.1)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
		sc.render.filepath = os.path.join(folder, "turtle_%s.png" % name)
		bpy.ops.render.render(write_still=True)
	bpy.data.objects.remove(cam, do_unlink=True)


parts = build()
for k, o in parts.items():
	vs = [o.matrix_world @ Vector(c) for c in o.bound_box]
	mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
	mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
	print("PART %-6s pivot=%s min=%s max=%s" % (k, tuple(round(x, 2) for x in o.matrix_world.translation), tuple(round(x, 2) for x in mn), tuple(round(x, 2) for x in mx)))
if ANIM:
	animate(parts)
if RENDER:
	render_views(parts, RENDER)
for o in bpy.context.scene.objects:
	o.select_set(o.type == "MESH")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
	export_image_format="AUTO", export_animations=ANIM, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
	export_frame_step=1)
print("TURTLE_DONE", {k: len(v.data.polygons) for k, v in parts.items()}, round(os.path.getsize(OUT) / 1e6, 1), "MB")
