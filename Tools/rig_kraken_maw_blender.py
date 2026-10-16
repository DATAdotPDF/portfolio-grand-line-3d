"""Rig e animação da boca nova do Kraken (Meshy "rigready volumetric kraken maw", 9 presas).

Rodado no Blender pela conexão MCP (exec deste arquivo + build(src, out)), numa cena própria.
- Osso raiz no corpo (fica rígido) + um osso por presa (base na borda de carne, ponta na ponta).
- Pesos: a presa segue o seu osso; a borda de carne logo abaixo faz a transição suave.
- Clipe "Gnash" (72 quadros, cíclico de verdade, sem vai-e-volta): cada presa abre para fora e
  morde para dentro, numa onda que corre em volta do anel; a carne pulsa de leve.
Material original intocado (só pesos e esqueleto); sem decimate.
"""
import math
import bpy
import numpy as np
from mathutils import Vector

FANGS = 9
FRAMES = 72


def _kmeans_angles(angles, k, iters=30):
	"""k-means no círculo (ângulos em radianos): devolve os centros das presas."""
	pts = np.stack([np.cos(angles), np.sin(angles)], axis=1)
	best = None
	for offset in np.linspace(0, 2 * math.pi / k, 6, endpoint=False):
		c = np.array([[math.cos(offset + 2 * math.pi * i / k), math.sin(offset + 2 * math.pi * i / k)] for i in range(k)])
		for _ in range(iters):
			lab = np.argmax(pts @ c.T, axis=1)
			for i in range(k):
				m = pts[lab == i]
				if len(m):
					v = m.mean(axis=0)
					c[i] = v / (np.linalg.norm(v) + 1e-9)
		score = np.sum(np.max(pts @ c.T, axis=1))
		if best is None or score > best[0]:
			best = (score, c.copy(), lab.copy())
	return np.arctan2(best[1][:, 1], best[1][:, 0]), best[2]


def build(src, out):
	scene = bpy.data.scenes.new("KrakenMawRig")
	bpy.context.window.scene = scene
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=src)
	meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
	mesh = meshes[0]
	for o in bpy.context.selected_objects:
		o.select_set(False)
	mesh.select_set(True)
	bpy.context.view_layer.objects.active = mesh
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

	n = len(mesh.data.vertices)
	co = np.empty(n * 3, dtype=np.float64)
	mesh.data.vertices.foreach_get("co", co)
	co = co.reshape(-1, 3)
	zmin, zmax = co[:, 2].min(), co[:, 2].max()
	H = zmax - zmin
	cx, cy = (co[:, 0].min() + co[:, 0].max()) / 2, (co[:, 1].min() + co[:, 1].max()) / 2
	ang = np.arctan2(co[:, 1] - cy, co[:, 0] - cx)
	rad = np.hypot(co[:, 0] - cx, co[:, 1] - cy)
	# Presas: a parte de cima do modelo (as pontas ficam acima da borda de carne).
	top = co[:, 2] > zmin + 0.74 * H
	centers, lab = _kmeans_angles(ang[top], FANGS)
	top_idx = np.nonzero(top)[0]
	base_z = zmin + 0.56 * H
	fangs = []
	for i in range(FANGS):
		sel = top_idx[lab == i]
		if len(sel) == 0:
			continue
		tip = co[sel][np.argmax(co[sel][:, 2])]
		r_base = float(np.median(rad[sel]))
		a = float(centers[i])
		head = Vector((cx + math.cos(a) * r_base, cy + math.sin(a) * r_base, base_z))
		fangs.append({"angle": a, "head": head, "tail": Vector(tip.tolist())})

	# Esqueleto.
	arm_data = bpy.data.armatures.new("KrakenMawRig")
	rig = bpy.data.objects.new("KrakenMawRig", arm_data)
	scene.collection.objects.link(rig)
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode="EDIT")
	root = arm_data.edit_bones.new("Root")
	root.head = Vector((cx, cy, zmin))
	root.tail = Vector((cx, cy, zmin + 0.3 * H))
	for i, f in enumerate(fangs):
		b = arm_data.edit_bones.new("Fang_%d" % i)
		b.head = f["head"]
		b.tail = f["tail"]
		b.parent = root
		# Z local apontando para fora (radial): girar em X dobra a presa para fora/para dentro.
		b.align_roll(Vector((math.cos(f["angle"]), math.sin(f["angle"]), 0.0)))
	bpy.ops.object.mode_set(mode="OBJECT")

	# Pesos (numpy): presa = altura acima da borda × proximidade angular; resto no Root.
	sector = 2 * math.pi / FANGS
	h = np.clip((co[:, 2] - (base_z - 0.07 * H)) / (0.12 * H), 0.0, 1.0)
	h = h * h * (3 - 2 * h)
	weights = []
	for f in fangs:
		d = np.angle(np.exp(1j * (ang - f["angle"])))
		weights.append(h * np.exp(-(d / (sector * 0.34)) ** 2))
	W = np.stack(weights, axis=1)
	total = W.sum(axis=1)
	over = total > 1.0
	W[over] /= total[over][:, None]
	root_w = np.clip(1.0 - W.sum(axis=1), 0.0, 1.0)
	mesh.vertex_groups.clear()
	g_root = mesh.vertex_groups.new(name="Root")
	idx_all = np.arange(n)
	for value in np.unique(np.round(root_w, 2)):
		ids = idx_all[np.round(root_w, 2) == value].tolist()
		if value > 0.0 and ids:
			g_root.add(ids, float(value), "REPLACE")
	for i in range(len(fangs)):
		g = mesh.vertex_groups.new(name="Fang_%d" % i)
		col = np.round(W[:, i], 2)
		for value in np.unique(col):
			if value <= 0.0:
				continue
			ids = idx_all[col == value].tolist()
			g.add(ids, float(value), "REPLACE")
	mod = mesh.modifiers.new("Armature", "ARMATURE")
	mod.object = rig
	mesh.parent = rig

	# Animação cíclica: onda de mordida em volta do anel + carne pulsando.
	rig.animation_data_create()
	action = bpy.data.actions.new("Gnash")
	rig.animation_data.action = action
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode="POSE")
	for pb in rig.pose.bones:
		pb.rotation_mode = "XYZ"
	for frame in range(0, FRAMES + 1, 4):
		t = frame / FRAMES
		for i in range(len(fangs)):
			pb = rig.pose.bones["Fang_%d" % i]
			phase = 2 * math.pi * (t - i / len(fangs))
			# Abre devagar e fecha rápido (mordida): forma de onda assimétrica, ainda periódica.
			bite = math.sin(phase) + 0.35 * math.sin(2 * phase)
			pb.rotation_euler = (math.radians(16.0) * bite, 0.0, 0.0)
			pb.keyframe_insert("rotation_euler", frame=frame)
		root_pb = rig.pose.bones["Root"]
		s = 1.0 + 0.03 * math.sin(2 * math.pi * t * 2)
		root_pb.scale = (s, s, 1.0 + 0.02 * math.sin(2 * math.pi * t * 2 + 1.0))
		root_pb.keyframe_insert("scale", frame=frame)
	bpy.ops.object.mode_set(mode="OBJECT")
	scene.frame_start = 0
	scene.frame_end = FRAMES

	for o in bpy.context.selected_objects:
		o.select_set(False)
	rig.select_set(True)
	mesh.select_set(True)
	bpy.context.view_layer.objects.active = rig
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=True,
		export_skins=True, export_apply=False, export_image_format="AUTO")
	report = {"fangs": len(fangs), "verts": n, "fang_weighted": int((W.sum(axis=1) > 0.05).sum()), "out": out}
	# Limpa a cena temporária (a cena aberta do usuário fica como estava).
	for o in [rig, mesh] + [o for o in bpy.data.objects if o not in before and o not in (rig, mesh)]:
		bpy.data.objects.remove(o, do_unlink=True)
	bpy.data.scenes.remove(scene)
	return report
