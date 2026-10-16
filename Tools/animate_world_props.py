"""Animações dos modelos do mapa (boias, caixas, monólito), feitas no Blender e exportadas no GLB.

Parte dos GLBs ORIGINAIS do Meshy em Assets/ (topologia e materiais originais: nada é reduzido,
soldado, quantizado nem assado). Os segmentados (correntes de basalto) partem do GLB cortado em
partes por Tools/split_island_by_parts.py (a malha original, só separada), guardado em
Assets/World/_src/ (ignorado pelo Godot). Saída em Assets/World/.
- Rigs (armadura + pele, exportados no glTF): correntes do monólito e bandeira do cemitério.
- O balanço vai num Empty "Float" na linha d'água, pai do modelo (a malha não é mexida); o sino da
  boia é separado num objeto "Bell" (as mesmas faces, só em outro objeto) que balança.
- Uma ação "Idle" em loop por GLB (faixas NLA "Idle"). O Godot (Scripts/WorldDecor.gd) só toca a
  animação, põe o modelo em metros na linha d'água e na altura da onda.
- Amplitudes em metros, convertidas para a unidade do original (os do Meshy têm ~1,9 de lado).

Uso, pelo Blender MCP (cena temporária; a cena aberta não é tocada):
  g = {"PROJECT": r"<projeto>", "NAMES": ["bell_buoy"]}
  exec(open(r"<projeto>/Tools/animate_world_props.py", encoding="utf-8").read(), g)
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector

FPS = 24

## nome → [arquivo em Assets/ (ou World/... já em partes), tamanho em metros, "h" altura | "max", calado]
SOURCES = {
	"bell_buoy": ["Meshy_AI_channel_bell_buoy_3d_1008215810_image-to-3d-texture.glb", 4.5, "h", 0.35],
	"cargo_crates": ["Meshy_AI_floating_cargo_crates_1008220654_image-to-3d-texture.glb", 4.0, "max", 0.4],
	"spectral_lantern": ["Meshy_AI_clean_spectral_lanter_1009142211_image-to-3d-texture.glb", 5.0, "h", 0.3],
	"floating_basalt_chain": ["World/_src/floating_basalt_chain_parts.glb", 46.0, "max", 0.1],
	"ship_graveyard": ["World/_src/ship_graveyard_parts.glb", 60.0, "max", 0.12],
	"abandoned_stilt_waterworks": ["World/_src/abandoned_stilt_waterworks_parts.glb", 42.0, "max", 0.15],
	"twin_sea_pinnacles": ["Meshy_AI_twin_sea_pinnacles_3d_1009121457_image-to-3d-texture.glb", 42.0, "h", 0.08],
	"stilt_lookout_post": ["Meshy_AI_stilt_lookout_post_3d_1008215303_image-to-3d-texture.glb", 24.0, "h", 0.15],
	"split_monolith_runes": ["Meshy_AI_split_monolith_runes__1009111301_image-to-3d-texture.glb", 75.0, "h", 0.08],
}

# Metros → unidade do original (definido por modelo em run()).
UNIT = 1.0


def wave(t, loop, cycles, phase=0.0):
	"""Senoide que fecha o loop (cycles voltas inteiras em loop segundos)."""
	return math.sin(math.tau * cycles * t / loop + phase)


def bounds(objs):
	vs = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
	mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
	mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
	return mn, mx


def float_root(objs, draft):
	"""Empty "Float" na linha d'água (centro da base), pai dos objetos: é ele que balança."""
	mn, mx = bounds(objs)
	root = bpy.data.objects.new("Float", None)
	bpy.context.scene.collection.objects.link(root)
	root.location = ((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z + (mx.z - mn.z) * draft)
	bpy.context.view_layer.update()
	for o in objs:
		if o.parent is None:
			world = o.matrix_world.copy()
			o.parent = root
			o.matrix_world = world
	return root


def split_bell(model):
	"""Separa as faces do sino (dentro da gaiola, perto do eixo) num objeto "Bell" com a origem no
	topo do sino (pivô do balanço), filho do corpo."""
	vs = [model.matrix_world @ v.co for v in model.data.vertices]
	lo = min(v.z for v in vs)
	hi = max(v.z for v in vs)
	h = hi - lo
	base = [v for v in vs if v.z < lo + h * 0.25]
	axis = Vector((sum(v.x for v in base) / len(base), sum(v.y for v in base) / len(base)))
	band = (0.545, 0.69)
	radius = h * 0.072
	bpy.ops.object.select_all(action="DESELECT")
	model.select_set(True)
	bpy.context.view_layer.objects.active = model
	bpy.ops.object.mode_set(mode="EDIT")
	bm = bmesh.from_edit_mesh(model.data)
	count = 0
	for f in bm.faces:
		c = model.matrix_world @ f.calc_center_median()
		frac = (c.z - lo) / h
		inside = band[0] < frac < band[1] and (Vector((c.x, c.y)) - axis).length < radius
		f.select_set(inside)
		count += inside
	bmesh.update_edit_mesh(model.data)
	bpy.ops.mesh.separate(type="SELECTED")
	bpy.ops.object.mode_set(mode="OBJECT")
	bell = next(o for o in bpy.context.selected_objects if o != model)
	bell.name = "Bell"
	pivot = Vector((axis.x, axis.y, lo + h * band[1]))
	bpy.context.scene.cursor.location = pivot
	bpy.ops.object.select_all(action="DESELECT")
	bell.select_set(True)
	bpy.context.view_layer.objects.active = bell
	bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
	world = bell.matrix_world.copy()
	bell.parent = model
	bell.matrix_world = world
	print("ANIM sino: %d faces" % count)
	return bell


def keyframes(obj, loop, fn):
	"""fn(t) -> (deslocamento em metros, rotação) em relação à pose inicial; chave a cada 2 quadros."""
	# O importador de glTF deixa em quatérnio: as chaves de Euler seriam ignoradas.
	obj.rotation_mode = "XYZ"
	loc0 = obj.location.copy()
	rot0 = obj.rotation_euler.copy()
	frames = int(loop * FPS)
	for f in range(0, frames + 1, 2):
		t = f / FPS
		loc, rot = fn(t)
		obj.location = loc0 + Vector(loc) * UNIT
		obj.rotation_euler = (rot0.x + rot[0], rot0.y + rot[1], rot0.z + rot[2])
		obj.keyframe_insert("location", frame=f)
		obj.keyframe_insert("rotation_euler", frame=f)
	obj.location = loc0
	obj.rotation_euler = rot0
	# Uma faixa NLA "Idle" por objeto: o exportador junta as faixas de mesmo nome numa animação só.
	action = obj.animation_data.action
	action.name = "Idle_" + obj.name
	track = obj.animation_data.nla_tracks.new()
	track.name = "Idle"
	track.strips.new("Idle", 0, action)
	obj.animation_data.action = None
	return frames


def animate_bell_buoy(meshes, draft):
	loop = 4.0
	model = meshes[0]
	bell = split_bell(model)
	root = float_root([model], draft)

	def body(t):
		rx = 0.07 * wave(t, loop, 1) + 0.015 * wave(t, loop, 3, 0.7)
		ry = 0.05 * wave(t, loop, 1, 1.3)
		return (0, 0, 0.08 * wave(t, loop, 2, 0.4)), (rx, ry, 0)

	def swing(t):
		# O sino fica atrasado e contrário ao balanço do corpo (pêndulo), com um tremor a mais.
		lag = 0.55
		rx = -1.9 * 0.07 * wave(t - lag, loop, 1) + 0.05 * wave(t, loop, 3, 0.2)
		ry = -1.9 * 0.05 * wave(t - lag, loop, 1, 1.3) + 0.04 * wave(t, loop, 4, 1.1)
		return (0, 0, 0), (rx, ry, 0)

	keyframes(root, loop, body)
	keyframes(bell, loop, swing)
	return loop


def animate_lantern(meshes, draft):
	loop = 8.0
	root = float_root(meshes, draft)

	def body(t):
		z = 0.25 * wave(t, loop, 1) + 0.06 * wave(t, loop, 3, 0.9)
		rx = 0.07 * wave(t, loop, 1, 0.5)
		ry = 0.06 * wave(t, loop, 2, 1.7)
		return (0, 0, z), (rx, ry, math.tau * t / loop)

	keyframes(root, loop, body)
	return loop


def animate_cargo_crates(meshes, draft):
	loop = 5.0
	root = float_root(meshes, draft)

	def body(t):
		z = 0.1 * wave(t, loop, 1)
		return (0, 0, z), (0.06 * wave(t, loop, 1, 0.8), 0.05 * wave(t, loop, 2, 0.3), 0.03 * wave(t, loop, 1, 2.0))

	keyframes(root, loop, body)
	return loop


def make_armature(name, bones):
	"""Armadura na origem (espaço do modelo); bones = [(nome, cabeça, cauda, pai)]."""
	data = bpy.data.armatures.new(name)
	arm = bpy.data.objects.new(name, data)
	bpy.context.scene.collection.objects.link(arm)
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	for bone_name, head, tail, parent in bones:
		eb = data.edit_bones.new(bone_name)
		eb.head = head
		eb.tail = tail
		if parent:
			eb.parent = data.edit_bones[parent]
	bpy.ops.object.mode_set(mode="OBJECT")
	return arm


def skin(mesh, arm, weights):
	"""weights(índice, posição) -> [(osso, peso)]. Agrupa por peso (64 níveis) para ser rápido."""
	buckets = {}
	for v in mesh.data.vertices:
		for bone_name, w in weights(v.index, mesh.matrix_world @ v.co):
			if w <= 0.001:
				continue
			key = (bone_name, round(w * 64) / 64)
			buckets.setdefault(key, []).append(v.index)
	for (bone_name, w), idx in buckets.items():
		group = mesh.vertex_groups.get(bone_name) or mesh.vertex_groups.new(name=bone_name)
		group.add(idx, w, "REPLACE")
	mod = mesh.modifiers.new("Armature", "ARMATURE")
	mod.object = arm
	world = mesh.matrix_world.copy()
	mesh.parent = arm
	mesh.matrix_world = world


def bone_keys(arm, loop, fns):
	"""fns: osso -> fn(t) -> (deslocamento em metros no espaço do osso, rotação euler). Faixa NLA "Idle"."""
	frames = int(loop * FPS)
	for f in range(0, frames + 1, 2):
		t = f / FPS
		for bone_name, fn in fns.items():
			pb = arm.pose.bones[bone_name]
			pb.rotation_mode = "XYZ"
			loc, rot = fn(t)
			pb.location = Vector(loc) * UNIT
			pb.rotation_euler = rot
			pb.keyframe_insert("location", frame=f)
			pb.keyframe_insert("rotation_euler", frame=f)
	action = arm.animation_data.action
	action.name = "Idle_" + arm.name
	track = arm.animation_data.nla_tracks.new()
	track.name = "Idle"
	track.strips.new("Idle", 0, action)
	arm.animation_data.action = None
	for pb in arm.pose.bones:
		pb.location = (0, 0, 0)
		pb.rotation_euler = (0, 0, 0)


def smooth(a, b, x):
	t = min(max((x - a) / (b - a), 0.0), 1.0)
	return t * t * (3.0 - 2.0 * t)


def animate_basalt_chain(meshes, draft):
	"""Monólito acorrentado (partes da segmentação do Meshy): o monólito flutua num osso; as duas
	correntes presas a ele (ponta de baixo fixa na rocha, de cima no monólito) esticam e acompanham;
	a corrente quebrada menor balança solta, com peso, atrasada como num mar; a lasca solta boia.
	Movimentos pequenos: as correntes não se cruzam (sem física)."""
	loop = 8.0
	parts = {o.name: o for o in meshes}
	base, chains, monolith, broken, shard = (parts.get("model_part%d" % i) for i in range(5))
	mn, mx = bounds(meshes)
	h = mx.z - mn.z
	ma, mb = bounds([monolith])
	center = (ma + mb) / 2
	# Corrente quebrada: eixo da base (vértices mais baixos) até a ponta (mais altos).
	bv = [broken.matrix_world @ v.co for v in broken.data.vertices]
	bv.sort(key=lambda v: v.z)
	k = max(1, len(bv) // 10)
	foot = sum(bv[:k], Vector()) / k
	tip = sum(bv[-k:], Vector()) / k
	axis = tip - foot
	length = axis.length
	bones = [("Anchor", Vector((center.x, center.y, mn.z)), Vector((center.x, center.y, mn.z + h * 0.05)), None),
		("Monolith", center, center + Vector((0, 0, h * 0.1)), "Anchor")]
	if shard:
		sa, sb = bounds([shard])
		sc = (sa + sb) / 2
		bones.append(("Shard", sc, sc + Vector((0, 0, h * 0.04)), "Anchor"))
	for i in range(4):
		bones.append(("Broken%d" % i, foot + axis * (i / 4), foot + axis * ((i + 1) / 4), "Broken%d" % (i - 1) if i else "Anchor"))
	arm = make_armature("ChainRig", bones)
	skin(monolith, arm, lambda i, p: [("Monolith", 1.0)])
	if shard:
		skin(shard, arm, lambda i, p: [("Shard", 1.0)])
	# Correntes: peso do monólito sobe da rocha (0) até onde a corrente abraça o monólito (1).
	z0 = bounds([chains])[0].z + h * 0.04
	z1 = ma.z + (mb.z - ma.z) * 0.3

	def chain_w(i, p):
		w = smooth(z0, z1, p.z)
		return [("Monolith", w), ("Anchor", 1.0 - w)]

	skin(chains, arm, chain_w)

	def broken_w(i, p):
		t = min(max((p - foot).dot(axis) / (length * length), 0.0), 1.0) * 3.0
		return [("Broken%d" % b, max(0.0, 1.0 - abs(t - b))) for b in range(4)]

	skin(broken, arm, broken_w)

	def mono(t):
		z = 0.45 * wave(t, loop, 1) + 0.1 * wave(t, loop, 2, 1.1)
		# Osso em pé: o eixo Y do osso é o "para cima" do mundo.
		return (0, z, 0), (0.025 * wave(t, loop, 1, 0.6), 0.06 * wave(t, loop, 1, 0.3), 0.02 * wave(t, loop, 1, 2.1))

	fns = {"Monolith": mono}
	if shard:
		fns["Shard"] = lambda t: ((0, 0.3 * wave(t, loop, 1, 2.4), 0), (0.1 * wave(t, loop, 1, 0.4), 0.3 * wave(t, loop, 1, 1.0), 0.08 * wave(t, loop, 2, 0.2)))
	for b in range(4):
		# Cada elo atrasa em relação ao de baixo: a ponta solta chicoteia mais (peso no mar).
		amp = 0.05 + 0.04 * b
		fns["Broken%d" % b] = (lambda b, amp: lambda t: ((0, 0, 0), (amp * wave(t, loop, 1, -0.7 * b), 0.0, amp * 0.7 * wave(t, loop, 2, 1.3 - 0.6 * b))))(b, amp)
	bone_keys(arm, loop, fns)
	print("ANIM correntes: rig com %d ossos" % len(bones))
	return loop


def cloth_flag(mesh, box_min, box_max, rig_name, loop, bones_n=4, amp=0.55, palette=("blue", "dark")):
	"""Bandeira tremulando SÓ no tecido (Tools/cloth_select.py: faces de pano pela cor da textura e
	pedaços ligados; peso 0 em tudo que encosta na madeira). Ossos: "Rigid" parado (mastro, verga,
	cordas, casco: 100%) e uma cadeia do ponto onde o pano prende até a ponta solta; a onda corre da
	prisão para a ponta (cada osso atrasa) e o pano torce um pouco (tremular)."""
	import numpy as np
	sys.path.insert(0, os.path.join(PROJECT_ROOT, "Tools"))
	import cloth_select as cs
	cloth, _rigid = cs.cloth_faces(mesh, box_min, box_max, palette)
	mw = mesh.matrix_world
	verts = set()
	for i in cloth:
		verts.update(mesh.data.polygons[i].vertices)
	pts = np.array([list(mw @ mesh.data.vertices[i].co) for i in verts])
	span = float(np.max(np.linalg.norm(pts - pts.mean(axis=0), axis=1))) * 2.0
	cw = cs.cloth_vertex_weights(mesh, cloth, span * 0.18, box_min, box_max)
	# Prisão = média do pano colado na madeira; ponta = vértice de pano mais longe dela.
	fixed = [mw @ mesh.data.vertices[i].co for i in verts if cw.get(i, 0.0) < 0.05]
	attach = sum(fixed, Vector()) / len(fixed)
	tip = max((mw @ mesh.data.vertices[i].co for i in verts), key=lambda q: (q - attach).length)
	along = (tip - attach).normalized()
	length = (tip - attach).length
	# Normal do pano (menor variação) e eixo da batida (no plano do pano, perpendicular à cadeia).
	cov = np.cov((pts - pts.mean(axis=0)).T)
	normal = Vector(np.linalg.eigh(cov)[1][:, 0]).normalized()
	flap_axis = along.cross(normal).normalized()
	step = length / bones_n
	bones = [("Rigid", attach - Vector((0, 0, step)), attach, None)]
	for i in range(bones_n):
		bones.append(("Flag%d" % i, attach + along * step * i, attach + along * step * (i + 1), "Flag%d" % (i - 1) if i else "Rigid"))
	arm = make_armature(rig_name, bones)

	def weights(i, p):
		w = cw.get(i, 0.0)
		if w <= 0.0:
			return [("Rigid", 1.0)]
		t = min(max((p - attach).dot(along) / length, 0.0), 1.0) * (bones_n - 1)
		out = [("Rigid", 1.0 - w)]
		for k in range(bones_n):
			out.append(("Flag%d" % k, w * max(0.0, 1.0 - abs(t - k))))
		return out

	skin(mesh, arm, weights)
	frames = int(loop * FPS)
	from mathutils import Quaternion
	for pb in arm.pose.bones:
		pb.rotation_mode = "QUATERNION"
	for f in range(0, frames + 1, 2):
		t = f / FPS
		for k in range(bones_n):
			pb = arm.pose.bones["Flag%d" % k]
			rest = pb.bone.matrix_local.to_3x3().inverted()
			a_flap = (amp * (0.6 + 0.4 * k / max(bones_n - 1, 1))) * wave(t, loop, 2, -1.1 * k)
			a_twist = 0.35 * amp * wave(t, loop, 3, 0.7 - 0.9 * k)
			q = Quaternion((rest @ flap_axis).normalized(), a_flap) @ Quaternion((rest @ along).normalized(), a_twist)
			pb.rotation_quaternion = q
			pb.keyframe_insert("rotation_quaternion", frame=f)
	action = arm.animation_data.action
	action.name = "Idle_" + arm.name
	track = arm.animation_data.nla_tracks.new()
	track.name = "Idle"
	track.strips.new("Idle", 0, action)
	arm.animation_data.action = None
	for pb in arm.pose.bones:
		pb.rotation_quaternion = Quaternion()
	print("ANIM bandeira %s: %d faces de pano, %d vértices com peso, comprimento %.3f" % (rig_name, len(cloth), len(cw), length))
	return arm


def animate_ship_graveyard(meshes, draft):
	"""Cemitério de navios (partes da segmentação): a bandeira do mastro principal tremula no vento —
	só o tecido (pela cor da textura); mastro, cordas e casco ficam rígidos."""
	loop = 3.0
	mast = next(o for o in meshes if o.name == "model_part4")
	cloth_flag(mast, Vector((-5.0, -5.0, 0.2)), Vector((5.0, 5.0, 5.0)), "FlagRig", loop, bones_n=5, amp=0.55)
	return loop


def animate_stilt_lookout_post(meshes, draft):
	"""Posto de vigia sobre palafitas (Leste): a bandeira azul do topo do mastro tremula — só o tecido
	(pela cor da textura); o mastro, o telhado e o resto ficam rígidos."""
	loop = 2.5
	mesh = max(meshes, key=lambda o: len(o.data.vertices))
	mn, mx = bounds([mesh])
	top = mn.z + (mx.z - mn.z) * 0.86
	cloth_flag(mesh, Vector((mn.x - 1, mn.y - 1, top)), Vector((mx.x + 1, mx.y + 1, mx.z + 1)), "FlagRig", loop, bones_n=4, amp=0.5,
		palette=("blue",))
	return loop


def animate_waterworks(meshes, draft):
	"""Palafitas com roda d'água (partes da segmentação do Meshy, fatiadas na horizontal): a roda é
	achada pela geometria (disco de frente para +X; eixo e raio medidos no modelo), as faces dela vão
	para um objeto "Wheel" (mesmas faces e material) que gira em volta do eixo. O poste da frente, a
	calha de cima e o resto ficam parados. Empties "WaterSpout" (calha) e "WaterSplash" (pé da roda)
	marcam onde o Godot põe a água caindo e o respingo."""
	import numpy as np
	loop = 8.0
	yc, zc, rim = 0.14, 0.19, 0.48
	wheel_parts = []
	for o in meshes:
		n = len(o.data.polygons)
		c = np.empty(n * 3, dtype=np.float32)
		o.data.polygons.foreach_get("center", c)
		c = c.reshape(-1, 3)
		m = np.array(o.matrix_world)
		c = c @ m[:3, :3].T + m[:3, 3]
		d = np.hypot(c[:, 1] - yc, c[:, 2] - zc)
		post = (np.abs(c[:, 1] - yc) < 0.07) & (d > 0.07) & ((c[:, 0] > 0.49) | ((c[:, 2] < zc - 0.1) & (c[:, 0] > 0.46)))
		sel = (c[:, 0] > 0.30) & (c[:, 0] < 0.62) & (d < rim) & ~post & (c[:, 2] < zc + rim)
		if not sel.any():
			continue
		o.data.polygons.foreach_set("select", sel.astype(bool))
		bpy.ops.object.select_all(action="DESELECT")
		o.select_set(True)
		bpy.context.view_layer.objects.active = o
		bpy.ops.object.mode_set(mode="EDIT")
		bpy.ops.mesh.select_mode(type="FACE")
		bpy.ops.object.mode_set(mode="OBJECT")
		o.data.polygons.foreach_set("select", sel.astype(bool))
		bpy.ops.object.mode_set(mode="EDIT")
		bpy.ops.mesh.separate(type="SELECTED")
		bpy.ops.object.mode_set(mode="OBJECT")
		wheel_parts += [x for x in bpy.context.selected_objects if x != o]
	bpy.ops.object.select_all(action="DESELECT")
	for w in wheel_parts:
		w.select_set(True)
	bpy.context.view_layer.objects.active = wheel_parts[0]
	if len(wheel_parts) > 1:
		bpy.ops.object.join()
	wheel = bpy.context.view_layer.objects.active
	wheel.name = "Wheel"
	bpy.context.view_layer.update()
	co = np.empty(len(wheel.data.vertices) * 3, dtype=np.float32)
	wheel.data.vertices.foreach_get("co", co)
	co = co.reshape(-1, 3) @ np.array(wheel.matrix_world)[:3, :3].T + np.array(wheel.matrix_world)[:3, 3]
	# Meio da espessura do aro (medido no modelo: x de 0,30 a 0,61).
	axle = Vector((0.45, yc, zc))
	pivot = bpy.data.objects.new("WheelAxle", None)
	bpy.context.scene.collection.objects.link(pivot)
	pivot.location = axle
	bpy.context.view_layer.update()
	world = wheel.matrix_world.copy()
	wheel.parent = pivot
	wheel.matrix_world = world
	for name, at in [("WaterSpout", Vector((axle.x, yc - rim * 0.35, zc + rim * 0.95))), ("WaterSplash", Vector((axle.x, yc + rim * 0.2, zc - rim * 0.95)))]:
		e = bpy.data.objects.new(name, None)
		bpy.context.scene.collection.objects.link(e)
		e.location = at
	print("ANIM roda d'água: %d faces, eixo=%s" % (len(wheel.data.polygons), tuple(round(v, 3) for v in axle)))

	def turn(t):
		# Uma volta por loop; a água bate do lado -Y em cima, então gira de cima para +Y.
		return (0, 0, 0), (-math.tau * t / loop, 0, 0)

	keyframes(pivot, loop, turn)
	return loop


def spread_halves(meshes, gap_m, names):
	"""Separa o modelo em duas metades pelo plano x do centro (faces de cada lado vão para um objeto,
	mesmas faces e material) e afasta cada uma gap_m metros para fora: abre um canal navegável."""
	import numpy as np
	mn, mx = bounds(meshes)
	x0 = (mn.x + mx.x) / 2
	model = meshes[0]
	n = len(model.data.polygons)
	c = np.empty(n * 3, dtype=np.float32)
	model.data.polygons.foreach_get("center", c)
	c = c.reshape(-1, 3) @ np.array(model.matrix_world)[:3, :3].T + np.array(model.matrix_world)[:3, 3]
	right = c[:, 0] >= x0
	bpy.ops.object.select_all(action="DESELECT")
	model.select_set(True)
	bpy.context.view_layer.objects.active = model
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_mode(type="FACE")
	bpy.ops.object.mode_set(mode="OBJECT")
	model.data.polygons.foreach_set("select", right.astype(bool))
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.separate(type="SELECTED")
	bpy.ops.object.mode_set(mode="OBJECT")
	other = next(o for o in bpy.context.selected_objects if o != model)
	model.name = names[0]
	other.name = names[1]
	model.location.x -= gap_m * UNIT
	other.location.x += gap_m * UNIT
	print("ANIM %s / %s: separados %.1f m cada (faces %d / %d)" % (names[0], names[1], gap_m, len(model.data.polygons), len(other.data.polygons)))
	return 0.0


def spread_split_monolith(meshes, draft):
	"""Monólito rúnico partido: as duas metades se afastam pela fenda brilhante (plano x = 0, achado
	pelas faces ciano da textura) e o barco passa no meio; o modelo fica bem maior (SOURCES)."""
	return spread_halves(meshes, 6.0, ("MonolithLeft", "MonolithRight"))


def spread_twin_pinnacles(meshes, draft):
	"""Pináculos gêmeos: no original as duas rochas se encostam na linha d'água (não dá para passar
	entre elas). As faces de cada lado do plano do meio (x do centro) vão para um objeto por rocha
	(mesmas faces e material) e cada uma se afasta GAP_M metros para fora: abre o canal navegável.
	Sem animação (loop 0)."""
	import numpy as np
	gap_m = 4.0
	mn, mx = bounds(meshes)
	x0 = (mn.x + mx.x) / 2
	model = meshes[0]
	n = len(model.data.polygons)
	c = np.empty(n * 3, dtype=np.float32)
	model.data.polygons.foreach_get("center", c)
	c = c.reshape(-1, 3) @ np.array(model.matrix_world)[:3, :3].T + np.array(model.matrix_world)[:3, 3]
	right = c[:, 0] >= x0
	bpy.ops.object.select_all(action="DESELECT")
	model.select_set(True)
	bpy.context.view_layer.objects.active = model
	model.data.polygons.foreach_set("select", right.astype(bool))
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_mode(type="FACE")
	bpy.ops.object.mode_set(mode="OBJECT")
	model.data.polygons.foreach_set("select", right.astype(bool))
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.separate(type="SELECTED")
	bpy.ops.object.mode_set(mode="OBJECT")
	other = next(o for o in bpy.context.selected_objects if o != model)
	model.name = "PinnacleLeft"
	other.name = "PinnacleRight"
	model.location.x -= gap_m * UNIT
	other.location.x += gap_m * UNIT
	print("ANIM pináculos: separados %.1f m cada (faces %d / %d)" % (gap_m, len(model.data.polygons), len(other.data.polygons)))
	return 0.0


JOBS = {
	"bell_buoy": animate_bell_buoy,
	"spectral_lantern": animate_lantern,
	"cargo_crates": animate_cargo_crates,
	"floating_basalt_chain": animate_basalt_chain,
	"ship_graveyard": animate_ship_graveyard,
	"stilt_lookout_post": animate_stilt_lookout_post,
	"abandoned_stilt_waterworks": animate_waterworks,
	"twin_sea_pinnacles": spread_twin_pinnacles,
	"split_monolith_runes": spread_split_monolith,
}


# Pasta do projeto (run() define): Tools/cloth_select.py é importado dali.
PROJECT_ROOT = ""


def run(project, names):
	global UNIT, PROJECT_ROOT
	PROJECT_ROOT = project
	window = bpy.context.window
	previous = window.scene if window else bpy.context.scene
	done = {}
	for name in names:
		src, size_m, axis, draft = SOURCES[name]
		path = os.path.join(project, "Assets", *src.split("/"))
		out = os.path.join(project, "Assets", "World", name + ".glb")
		if window:
			scene = bpy.data.scenes.new("anim_" + name)
			window.scene = scene
		else:
			# Blender em lote (sem janela): começa de uma cena vazia a cada modelo.
			bpy.ops.wm.read_factory_settings(use_empty=True)
			scene = bpy.context.scene
		scene.render.fps = FPS
		before = set(bpy.data.objects)
		bpy.ops.import_scene.gltf(filepath=path)
		objs = [o for o in bpy.data.objects if o not in before]
		meshes = [o for o in objs if o.type == "MESH"]
		if any(o.animation_data for o in objs):
			print("ANIM %s já tem animação: pulando" % name)
			done[name] = "skip"
		else:
			mn, mx = bounds(meshes)
			dims = mx - mn
			UNIT = (dims.z if axis == "h" else max(dims)) / size_m
			loop = JOBS[name](meshes, draft)
			scene.frame_start = 0
			scene.frame_end = max(1, int(loop * FPS))
			bpy.ops.object.select_all(action="SELECT")
			# Sem compressão de malha (Draco/meshopt) e com as imagens originais.
			bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_active_scene=True,
				export_image_format="AUTO", export_animation_mode="NLA_TRACKS", export_animations=loop > 0,
				export_draco_mesh_compression_enable=False)
			done[name] = "ok %.1fs" % loop
			print("ANIM %s %s (unidade=%.4f)" % (name, done[name], UNIT))
		for obj_name in {o.name for o in scene.objects}:
			obj = bpy.data.objects.get(obj_name)
			if obj:
				bpy.data.objects.remove(obj, do_unlink=True)
		for a in [a for a in bpy.data.actions if a.name.startswith("Idle_")]:
			bpy.data.actions.remove(a)
		if window:
			window.scene = previous
			bpy.data.scenes.remove(scene)
	return done


if __name__ == "__main__" and "--" in sys.argv:
	argv = sys.argv[sys.argv.index("--") + 1:]
	run(argv[0], argv[1:] or list(JOBS))
elif "PROJECT" in globals():
	result = run(PROJECT, NAMES if "NAMES" in globals() else list(JOBS))
