"""Bichos do Meshy com esqueleto de deformação de verdade, animados no Blender.

Rodar pela conexão MCP do Blender:
	exec(open(r"<repo>/Tools/rig_creatures_blender.py", encoding="utf-8").read()); build("dolphin")
ou sem interface (malhas grandes: o 'bone heat' leva minutos):
	blender -b --factory-startup -P Tools/rig_creatures_blender.py -- dolphin gull tentacle flyfish fin maw

Regras do Pedro: malha ORIGINAL do Meshy (sem decimar/reduzir) e material/texturas intactos
(Principled BSDF e os 3 mapas como vieram). Só muda a pose de repouso no espaço: frente = +Y do
Blender (= -Z no Godot, a frente que os scripts usam), tamanho do jogo e origem. Esqueleto com
ARMATURE_AUTO (pesos automáticos), clipes de esqueleto e GLB com skins/morph/def bones, modificadores
não aplicados. As rotações dos ossos são dadas em eixos do MUNDO (convertidas para o espaço de cada
osso), então "bater asa" dobra a asa de verdade em vez de torcer o osso no próprio eixo.

Saída: Assets/Optimized/Creatures/<nome>.glb e renders de conferência em Builds/Creatures.
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Matrix, Euler, Quaternion

REPO = r"D:\Godot\Projects\portifolio-pedro-ferreira-3d-2026"
OUT_DIR = os.path.join(REPO, "Assets", "Optimized", "Creatures")
CHECK_DIR = os.path.join(REPO, "Builds", "Creatures")
FPS = 30

# fonte, giro em Z (graus) para a frente virar +Y, giro extra (Euler XYZ), tamanho no jogo
# (eixo, metros), origem (centro ou base).
SPECS = {
	# Golfinho de corpo reto que o Pedro refez no Meshy (o anterior vinha enrolado num C de ~260°).
	"dolphin": {"file": "Meshy_AI_straight_dolphin_rigr_1009234130_image-to-3d-texture.glb", "yaw": 180,
		"size": ("y", 2.8), "origin": "center"},
	# Gaivota nova em pose de planeio (asas na horizontal). beat_center: centro da batida (+ abaixa a
	# asa); glide_arm: asa durante o planeio (negativo levanta um pouco, diedro leve).
	"gull": {"file": "Meshy_AI_flying_seagull_glidin_1009235109_image-to-3d-texture.glb", "yaw": 180,
		"size": ("x", 2.6), "origin": "center", "beat_center": 8, "glide_arm": -5},
	# Tentáculo novo (épico): ventosas para -Y no original; girar 180° põe para +Y (= -Z no Godot,
	# para dentro do redemoinho).
	"tentacle": {"file": "Meshy_AI_epic_kraken_tentacle__1009235502_image-to-3d-texture.glb", "yaw": 180,
		"size": ("z", 1.0), "origin": "base"},
	# Peixe-voador reto refeito no Meshy: as nadadeiras-asa vêm em pé (uma para cima, outra para baixo,
	# no plano do corpo); o esqueleto as deita para os lados (rig_flyfish).
	"flyfish": {"file": "Meshy_AI_straight_flying_fish__1009234142_image-to-3d-texture.glb", "yaw": 180,
		"size": ("y", 0.5), "origin": "center"},
	"maw": {"file": "Meshy_AI_kraken_maw_teeth_3d_1009135650_image-to-3d-texture.glb", "yaw": 0,
		"extra": (-90, 0, 0), "size": ("x", 20.0), "origin": "center"},
	# Corte reto na linha d'água: a base da barbatana fica em z 0.
	"fin": {"file": "Meshy_AI_stylized_shark_fin_3d_1009135632_image-to-3d-texture.glb", "yaw": -90,
		"size": ("z", 1.0), "origin": "base"},
}


def clear_scene():
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o, do_unlink=True)
	for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.actions, bpy.data.armatures,
			bpy.data.cameras, bpy.data.lights):
		for d in list(coll):
			if d.users == 0:
				coll.remove(d)


def select_only(objs, active=None):
	for o in bpy.context.scene.objects:
		o.select_set(False)
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = active or objs[0]


def vbounds(obj):
	vs = [v.co for v in obj.data.vertices]
	return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
		Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def import_mesh(spec):
	clear_scene()
	bpy.ops.import_scene.gltf(filepath=os.path.join(REPO, "Assets", spec["file"]))
	meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
	select_only(meshes)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	if len(meshes) > 1:
		bpy.ops.object.join()
	return bpy.context.view_layer.objects.active


def orient(obj, spec):
	"""Frente para +Y, tamanho do jogo e origem (centro ou base). Só transforma; não muda a malha."""
	m = Matrix.Rotation(math.radians(spec.get("yaw", 0)), 4, "Z")
	extra = spec.get("extra")
	if extra:
		m = Euler([math.radians(a) for a in extra], "XYZ").to_matrix().to_4x4() @ m
	obj.data.transform(m)
	if spec.get("straighten"):
		_straighten(obj)
	if spec.get("post_yaw"):
		obj.data.transform(Matrix.Rotation(math.radians(spec["post_yaw"]), 4, "Z"))
	mn, mx = vbounds(obj)
	axis = "xyz".index(spec["size"][0])
	obj.data.transform(Matrix.Scale(spec["size"][1] / (mx[axis] - mn[axis]), 4))
	mn, mx = vbounds(obj)
	c = (mn + mx) / 2
	pivot = c if spec["origin"] == "center" else Vector((c.x, c.y, mn.z))
	obj.data.transform(Matrix.Translation(-pivot))
	obj.data.update()


def _straighten(obj):
	"""Peixe voador vem torto: o eixo do corpo (par mais distante) vai para +Y, as asas para X."""
	import random
	random.seed(7)
	verts = [v.co.copy() for v in obj.data.vertices]
	sample = random.sample(verts, min(1500, len(verts)))
	best = (0.0, None, None)
	for i, p in enumerate(sample):
		for q in sample[i + 1:]:
			d = (p - q).length_squared
			if d > best[0]:
				best = (d, p, q)
	_, p, q = best
	centroid = sum(verts, Vector()) / len(verts)
	head, tail = (p, q) if (p - centroid).length < (q - centroid).length else (q, p)
	body = (head - tail).normalized()
	flat = [v - body * v.dot(body) for v in sample]
	best = (0.0, None, None)
	for i, a in enumerate(flat):
		for b in flat[i + 1:]:
			d = (a - b).length_squared
			if d > best[0]:
				best = (d, a, b)
	wing = (best[1] - best[2]).normalized()
	wing = (wing - body * wing.dot(body)).normalized()
	up = wing.cross(body).normalized()
	obj.data.transform(Matrix((wing, body, up)).to_4x4())
	if sum(v.co.z for v in obj.data.vertices) < 0:
		obj.data.transform(Matrix.Rotation(math.pi, 4, "Y"))


def centerline(obj, axis, count, lo=0.0, hi=1.0):
	"""Pontos da linha central: centro dos vértices em fatias ao longo do eixo."""
	a = "xyz".index(axis)
	mn, mx = vbounds(obj)
	span = mx[a] - mn[a]
	cos = [v.co for v in obj.data.vertices]
	points = []
	for i in range(count):
		t = lo + (hi - lo) * i / (count - 1)
		at = mn[a] + span * t
		near = [v for v in cos if abs(v[a] - at) < span * 0.03]
		if not near:
			near = sorted(cos, key=lambda v: abs(v[a] - at))[:20]
		c = sum(near, Vector()) / len(near)
		c[a] = at
		points.append(c)
	return points


def make_armature(name, bones):
	"""bones: lista de (nome, cabeça, cauda, pai). Ossos de deformação, rotação em quaternion."""
	data = bpy.data.armatures.new(name)
	rig = bpy.data.objects.new(name, data)
	bpy.context.scene.collection.objects.link(rig)
	select_only([rig])
	bpy.ops.object.mode_set(mode="EDIT")
	made = {}
	for bone_name, head, tail, parent in bones:
		eb = data.edit_bones.new(bone_name)
		eb.head = head
		eb.tail = tail
		eb.roll = 0.0
		eb.use_deform = True
		if parent:
			eb.parent = made[parent]
			eb.use_connect = (made[parent].tail - head).length < 1e-4
		made[bone_name] = eb
	bpy.ops.object.mode_set(mode="OBJECT")
	for pb in rig.pose.bones:
		pb.rotation_mode = "QUATERNION"
	return rig


def skin(mesh, rig):
	"""Pesos automáticos (bone heat). Se sobrar vértice sem peso (malha do Meshy com ilhas soltas),
	solda só vértices exatamente sobrepostos (1e-6, não reduz a forma) e tenta de novo."""
	def attempt():
		select_only([mesh, rig], rig)
		bpy.ops.object.parent_set(type="ARMATURE_AUTO")
		return sum(1 for v in mesh.data.vertices if not v.groups or sum(g.weight for g in v.groups) < 1e-4)
	unweighted = attempt()
	welded = False
	if unweighted > len(mesh.data.vertices) * 0.01:
		for g in list(mesh.vertex_groups):
			mesh.vertex_groups.remove(g)
		mesh.parent = None
		for mod in list(mesh.modifiers):
			mesh.modifiers.remove(mod)
		bm = bmesh.new()
		bm.from_mesh(mesh.data)
		bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
		bm.to_mesh(mesh.data)
		bm.free()
		welded = True
		unweighted = attempt()
	filled = 0
	method = "bone_heat"
	if unweighted > len(mesh.data.vertices) * 0.5:
		# O heat falhou de vez (nadadeiras finas, ventosas soltas): pesos suaves pela distância aos ossos.
		_distance_weights(mesh, rig)
		method = "distance_falloff"
	elif unweighted:
		filled = _fill_unweighted(mesh)
	unweighted = sum(1 for v in mesh.data.vertices if not v.groups)
	# Transição suave: vértices com mais de um osso de peso relevante (mistura entre ossos).
	blended = sum(1 for v in mesh.data.vertices if sum(1 for g in v.groups if g.weight > 0.1) > 1)
	return {"unweighted": unweighted, "blended_pct": round(100.0 * blended / max(1, len(mesh.data.vertices)), 1),
		"welded_exact_duplicates": welded, "filled_from_nearest": filled, "method": method}


def _distance_weights(mesh, rig):
	"""Pesos suaves pela distância de cada vértice ao segmento de cada osso (1/d^4, os 3 mais
	perto, normalizados): emenda macia entre ossos vizinhos, como o automático faria."""
	for g in list(mesh.vertex_groups):
		mesh.vertex_groups.remove(g)
	bones = [(b.name, b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones if b.use_deform]
	groups = {name: mesh.vertex_groups.new(name=name) for name, _, _ in bones}
	for v in mesh.data.vertices:
		scores = []
		for name, h, t in bones:
			seg = t - h
			k = max(0.0, min(1.0, (v.co - h).dot(seg) / max(seg.length_squared, 1e-12)))
			d = (v.co - (h + seg * k)).length
			scores.append((1.0 / (d ** 4 + 1e-9), name))
		scores.sort(reverse=True)
		top = scores[:3]
		total = sum(w for w, _ in top)
		for w, name in top:
			if w / total > 0.02:
				groups[name].add([v.index], w / total, "REPLACE")


def _fill_unweighted(mesh):
	"""O 'bone heat' às vezes resolve só uma das cascas da malha do Meshy (a outra fica sem peso e
	ficaria parada, rasgando): cada vértice sem peso copia os pesos do vértice com peso mais perto."""
	from mathutils.kdtree import KDTree
	weighted = [v for v in mesh.data.vertices if v.groups and sum(g.weight for g in v.groups) > 1e-4]
	tree = KDTree(len(weighted))
	for i, v in enumerate(weighted):
		tree.insert(v.co, i)
	tree.balance()
	groups = mesh.vertex_groups
	count = 0
	for v in mesh.data.vertices:
		if v.groups and sum(g.weight for g in v.groups) > 1e-4:
			continue
		_, i, _ = tree.find(v.co)
		if i is None:
			continue
		for g in weighted[i].groups:
			groups[g.group].add([v.index], g.weight, "REPLACE")
		count += 1
	return count


def key_world(rig, frame, pose):
	"""pose: {osso: [(eixo_mundo, graus), ...]}; ossos fora da lista voltam ao repouso.
	A rotação em torno de um eixo do MUNDO vira a rotação local do osso (no repouso)."""
	for pb in rig.pose.bones:
		q = Quaternion()
		rest = pb.bone.matrix_local.to_3x3()
		for axis, deg in pose.get(pb.name, []):
			local_axis = (rest.inverted() @ Vector(axis)).normalized()
			q = Quaternion(local_axis, math.radians(deg)) @ q
		pb.rotation_quaternion = q
		pb.keyframe_insert("rotation_quaternion", frame=frame)


def push(rig, anim_name):
	ad = rig.animation_data
	action = ad.action
	action.name = anim_name
	track = ad.nla_tracks.new()
	track.name = anim_name
	track.strips.new(anim_name, int(action.frame_range[0]), action)
	ad.action = None
	for pb in rig.pose.bones:
		pb.rotation_quaternion = Quaternion()


X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)


def centerline_polar(mesh, cy, cz, count):
	"""Linha central de um corpo curvado em C (o golfinho do Meshy dá ~260° de volta: focinho na
	frente, costas subindo e contornando por trás, cauda descendo e voltando por baixo). Fatiar em Y
	misturava cauda com barriga; aqui as fatias são radiais em volta do centro da curva (no plano YZ).
	Devolve P0 = ponta da cauda … P(count-1) = focinho."""
	cos = [v.co for v in mesh.data.vertices]
	def phi(v):
		a = math.degrees(math.atan2(v.z - cz, v.y - cy))
		return a + 360.0 if a < -60.0 else a
	phis = [phi(v) for v in cos]
	lo, hi = min(phis), max(phis)
	points = []
	for i in range(count):
		target = hi - (hi - lo) * (0.01 + 0.98 * i / (count - 1))
		near = [v for v, a in zip(cos, phis) if abs(a - target) < 4.0]
		c = sum(near, Vector()) / len(near)
		points.append(Vector((0.0, c.y, c.z)))
	return points


def spine_gradient_weights(mesh, pts, order, allowed=None):
	"""Pesos por gradiente ao longo da coluna (o 'bone heat' deixava um osso da cauda sem nenhum
	vértice e outro com 29% da malha: a cauda dobrava em bloco). Cada vértice é projetado na linha
	central P0..Pn; o peso vai suave (smoothstep) entre os centros dos dois ossos vizinhos.
	order[j] = osso do segmento P_j → P_j+1. allowed(co) → índices de segmento permitidos (ou None)."""
	for g in list(mesh.vertex_groups):
		mesh.vertex_groups.remove(g)
	groups = {n: mesh.vertex_groups.new(name=n) for n in order}
	lengths = [(pts[j + 1] - pts[j]).length for j in range(len(order))]
	starts = [sum(lengths[:j]) for j in range(len(order))]
	centers = [starts[j] + lengths[j] / 2 for j in range(len(order))]
	for v in mesh.data.vertices:
		best = (1e9, 0.0)
		segments = allowed(v.co) if allowed else None
		for j in (segments if segments is not None else range(len(order))):
			seg = pts[j + 1] - pts[j]
			k = max(0.0, min(1.0, (v.co - pts[j]).dot(seg) / max(seg.length_squared, 1e-12)))
			d = (v.co - (pts[j] + seg * k)).length
			if d < best[0]:
				best = (d, starts[j] + k * lengths[j])
		sv = best[1]
		if sv <= centers[0]:
			groups[order[0]].add([v.index], 1.0, "REPLACE")
			continue
		if sv >= centers[-1]:
			groups[order[-1]].add([v.index], 1.0, "REPLACE")
			continue
		for j in range(len(order) - 1):
			if centers[j] <= sv <= centers[j + 1]:
				u = (sv - centers[j]) / (centers[j + 1] - centers[j])
				u = u * u * (3 - 2 * u)
				groups[order[j]].add([v.index], 1.0 - u, "REPLACE")
				groups[order[j + 1]].add([v.index], u, "REPLACE")
				break


def _smooth(x):
	x = max(0.0, min(1.0, x))
	return x * x * (3 - 2 * x)


def rig_dolphin(mesh):
	"""Golfinho de corpo RETO em pose neutra (o Pedro está refazendo o modelo no Meshy assim; o atual
	vem enrolado num C de ~260° e nenhuma animação o tira do "camarão").
	Esqueleto: Root no meio, Spine_01→Spine_02→Head para a frente (+Y) e Tail_01→…→Tail_04 para trás,
	pela linha central (fatias em Y: num corpo reto ela acompanha bem). Pesos por gradiente ao longo da
	coluna (cada vértice divide o peso entre os dois ossos vizinhos, transição suave).
	Swim_Leap (2 s = um ciclo do salto; o jogo sincroniza: 0-55% no ar, o resto nadando), resolvido
	como ângulo de cada trecho do corpo e convertido em rotação local pela hierarquia (eixo X do mundo =
	ondulação VERTICAL, para cima e para baixo, nunca de lado):
	  - nadando: corpo quase reto, onda correndo da cabeça para a cauda a 1,35 Hz, amplitude ~0 na cabeça
	    e máxima nas nadadeiras caudais;
	  - no ar: curva suave da trajetória (no máximo ~16° entre cabeça e cauda), batida da cauda forte
	    no começo da subida e amansando no ar; no fim a cabeça desce primeiro e a cauda fecha o
	    movimento na reentrada."""
	pts = centerline(mesh, "y", 9, 0.01, 0.99)  # P0 = ponta da cauda (-Y) … P8 = focinho (+Y)
	order = ["Tail_04", "Tail_03", "Tail_02", "Tail_01", "Root", "Spine_01", "Spine_02", "Head"]
	bones = [("Root", pts[4], pts[5], None), ("Spine_01", pts[5], pts[6], "Root"),
		("Spine_02", pts[6], pts[7], "Spine_01"), ("Head", pts[7], pts[8], "Spine_02"),
		("Tail_01", pts[4], pts[3], "Root"), ("Tail_02", pts[3], pts[2], "Tail_01"),
		("Tail_03", pts[2], pts[1], "Tail_02"), ("Tail_04", pts[1], pts[0], "Tail_03")]
	rig = make_armature("DolphinRig", bones)
	select_only([mesh, rig], rig)
	bpy.ops.object.parent_set(type="ARMATURE_NAME")
	spine_gradient_weights(mesh, pts, order)
	blended = sum(1 for v in mesh.data.vertices if sum(1 for g in v.groups if g.weight > 0.1) > 1)
	info = {"method": "spine_gradient", "blended_pct": round(100.0 * blended / len(mesh.data.vertices), 1),
		"unweighted": sum(1 for v in mesh.data.vertices if not v.groups)}
	n = len(order)
	frames = 60
	seconds = frames / FPS
	freq = 1.35
	tail_amp = 30.0                                  # graus no trecho das nadadeiras caudais
	for f in range(0, frames + 1):
		t = f / frames
		time = t * seconds
		air = t < 0.55
		u = t / 0.55 if air else (t - 0.55) / 0.45
		delta = []
		for j in range(n):
			sj = (j + 0.5) / n                           # 0 = cauda, 1 = focinho
			amp = tail_amp * (1.0 - sj) ** 1.6           # ~0 na cabeça, máxima na cauda
			beat = 1.0
			arc = 0.0
			extra = 0.0
			if air:
				beat = 1.0 - 0.6 * _smooth(u / 0.5)      # batida forte saindo da água, amansa no ar
				arc = 34.0 * math.sin(math.pi * u) * (0.5 - sj)   # corpo acompanha o arco (∩), sem virar C
				extra -= 10.0 * _smooth((u - 0.7) / 0.3) * _smooth((sj - 0.6) / 0.4)   # cabeça desce primeiro
				extra += 12.0 * _smooth((u - 0.85) / 0.15) * (1.0 - sj) ** 2           # cauda fecha na reentrada
			wave = amp * beat * math.sin(2 * math.pi * freq * time - 3.0 * (1.0 - sj))  # cabeça → cauda
			delta.append(wave + arc + extra)
		ref = delta[4]                                   # Root de referência (o pitch é do jogo)
		delta = [d - ref for d in delta]
		local = {"Root": 0.0, "Spine_01": delta[5] - delta[4], "Spine_02": delta[6] - delta[5], "Head": delta[7] - delta[6],
			"Tail_01": delta[3] - delta[4], "Tail_02": delta[2] - delta[3], "Tail_03": delta[1] - delta[2], "Tail_04": delta[0] - delta[1]}
		key_world(rig, f, {name: [(X, deg)] for name, deg in local.items()})
	push(rig, "Swim_Leap")
	return rig, info


def rig_gull(mesh, spec=None):
	"""chest (raiz), head, Wing_L_01/02 e Wing_R_01/02 (01 = braço, 02 = ponta). Fly_Flap (4,5 s, loop):
	5 batidas de verdade (braço 55° para cada lado de um centro 22° abaixo do V do modelo, ponta atrasada
	±40°: dobra na subida, abre na descida) e 1,5 s planando com as asas quase na horizontal e um rolo
	leve, para ler na distância da câmera do jogo."""
	mn, mx = vbounds(mesh)
	span = mx.x - mn.x
	chest = Vector((0, 0, 0))
	bones = [("chest", chest + Vector((0, -0.12 * span, 0)), chest + Vector((0, 0.1 * span, 0)), None),
		("head", chest + Vector((0, 0.1 * span, 0.02 * span)), Vector((0, mx.y * 0.95, 0.05 * span)), "chest")]
	for side, s in (("L", -1), ("R", 1)):
		shoulder = _wing_point(mesh, s * 0.06 * span)
		elbow = _wing_point(mesh, s * 0.27 * span)
		tip = _wing_point(mesh, s * 0.49 * span)
		bones.append(("Wing_%s_01" % side, shoulder, elbow, "chest"))
		bones.append(("Wing_%s_02" % side, elbow, tip, "Wing_%s_01" % side))
	rig = make_armature("GullRig", bones)
	info = skin(mesh, rig)
	beat = 18                                          # 0,6 s por batida
	beats = 5
	for f in range(0, beats * beat + 1):
		ph = 2 * math.pi * f / beat
		# O modelo já vem com as asas em V (~35° para cima): a batida é centrada mais baixo (+22° aqui
		# abaixa a asa) para subir até ~68° sem as asas se cruzarem em cima e descer abaixo da horizontal.
		arm = (spec or {}).get("beat_center", 22) + 55 * math.sin(ph)
		tip = 40 * math.sin(ph - 1.0)                  # ponta atrasada: dobra na subida, abre na descida
		body = -5 * math.sin(ph)                       # o peito sobe quando as asas descem
		key_world(rig, f, {"Wing_L_01": [(Y, -arm)], "Wing_L_02": [(Y, -tip)],
			"Wing_R_01": [(Y, arm)], "Wing_R_02": [(Y, tip)], "chest": [(X, body)], "head": [(X, -body * 0.6)]})
	glide_start = beats * beat
	glide = 45                                         # 1,5 s planando
	for f in range(glide_start + 3, glide_start + glide + 1, 3):
		g = (f - glide_start) / glide
		ease = _smooth(min(g * 4.0, 1.0)) * _smooth(min((1.0 - g) * 4.0, 1.0))
		roll = 6 * math.sin(2 * math.pi * g) * ease    # rolo leve (no jogo a curva soma o resto)
		glide_arm = (spec or {}).get("glide_arm", 24)
		key_world(rig, f, {"chest": [(Y, roll)], "Wing_L_01": [(Y, -glide_arm)], "Wing_R_01": [(Y, glide_arm)],
			"Wing_L_02": [(Y, -3 * ease)], "Wing_R_02": [(Y, 3 * ease)]})
	push(rig, "Fly_Flap")
	return rig, info


def _wing_point(mesh, x):
	near = [v.co for v in mesh.data.vertices if abs(v.co.x - x) < 0.03]
	if not near:
		return Vector((x, 0, 0))
	return Vector((x, sum(v.y for v in near) / len(near), sum(v.z for v in near) / len(near)))


def rig_tentacle(mesh):
	"""8 ossos Bone_Base → Bone_Tip seguindo o S do próprio tentáculo. Thrash (4 s, loop): chicoteia
	em arcos sinuosos para fora e de volta (onda correndo da base à ponta) e a ponta enrola."""
	names = ["Bone_Base"] + ["Bone_%02d" % i for i in range(1, 7)] + ["Bone_Tip"]
	pts = centerline(mesh, "z", len(names) + 1, 0.0, 1.0)
	rig = make_armature("TentacleRig", [(n, pts[i], pts[i + 1], names[i - 1] if i else None) for i, n in enumerate(names)])
	# Pesos por gradiente ao longo da cadeia (base → ponta): cada trecho dobra macio com os vizinhos.
	select_only([mesh, rig], rig)
	bpy.ops.object.parent_set(type="ARMATURE_NAME")
	spine_gradient_weights(mesh, pts, names)
	blended = sum(1 for v in mesh.data.vertices if sum(1 for g in v.groups if g.weight > 0.1) > 1)
	info = {"method": "spine_gradient", "blended_pct": round(100.0 * blended / len(mesh.data.vertices), 1),
		"unweighted": sum(1 for v in mesh.data.vertices if not v.groups)}
	frames = 120
	for f in range(0, frames + 1, 3):
		t = f / frames
		pose = {}
		for i, n in enumerate(names):
			k = i / (len(names) - 1)
			# Para fora (+Y = lado das ventosas, para dentro do redemoinho) e de volta, onda subindo.
			out = (10 + 14 * k) * math.sin(2 * math.pi * t - k * 2.6)
			side = (6 + 10 * k) * math.sin(2 * math.pi * 2 * t - k * 3.4 + 1.0)
			curl = 22 * k * k * (0.6 + 0.4 * math.sin(2 * math.pi * t * 2 - 1.2)) if k > 0.5 else 0.0
			pose[n] = [(X, out + curl), (Y, side)]
		key_world(rig, f, pose)
	push(rig, "Thrash")
	return rig, info


def rig_flyfish(mesh):
	"""Peixe-voador reto (Meshy) com as nadadeiras-asa EM PÉ: a de cima e a de baixo ficam no plano do
	corpo. Ossos: Spine (frente), Tail_01→Tail_02 (cauda) e Left/Right_WingFin; girar as duas 90° em
	volta do eixo do corpo (+Y) deita a de cima para a esquerda e a de baixo para a direita — asas
	abertas para os lados com o dorso para cima.
	Pesos: corpo por gradiente ao longo da coluna; cada asa passa do corpo para o seu osso conforme
	se afasta dele (transição macia na raiz).
	Takeoff (0,6 s): cauda em S rápido (de lado) para sair da água e as asas abrindo.
	Glide (1 s, loop): asas abertas e paradas, só um tremor leve; corpo reto."""
	mn, mx = vbounds(mesh)
	length = mx.y - mn.y
	pts = centerline(mesh, "y", 5, 0.01, 0.99)       # P0 = cauda (-Y) … P4 = focinho (+Y)
	for p in pts:
		p.x = 0.0
		p.z = 0.0
	order = ["Tail_02", "Tail_01", "Spine", "Spine"]
	bones = [("Spine", pts[2], pts[4], None), ("Tail_01", pts[2], pts[1], "Spine"), ("Tail_02", pts[1], pts[0], "Tail_01")]
	body_r = 0.045 * length
	fins = {"Left_WingFin": [], "Right_WingFin": []}
	for v in mesh.data.vertices:
		if abs(v.co.z) > body_r and v.co.y > mn.y + 0.35 * length:
			fins["Left_WingFin" if v.co.z > 0 else "Right_WingFin"].append(v.co.copy())
	for name, cos in fins.items():
		sign = 1 if name == "Left_WingFin" else -1
		root_y = sum(c.y for c in cos) / len(cos)
		root = Vector((0.0, root_y, sign * body_r))
		tip = max(cos, key=lambda c: (c - root).length)
		bones.append((name, root, Vector((0.0, tip.y, tip.z)), "Spine"))
	rig = make_armature("FlyingFishRig", bones)
	select_only([mesh, rig], rig)
	bpy.ops.object.parent_set(type="ARMATURE_NAME")
	spine_gradient_weights(mesh, [pts[0], pts[1], pts[2], pts[3], pts[4]], order)
	groups = {g.name: g for g in mesh.vertex_groups}
	for name in fins:
		groups[name] = mesh.vertex_groups.new(name=name)
	for v in mesh.data.vertices:
		if v.co.y <= mn.y + 0.35 * length or abs(v.co.z) <= body_r * 0.6:
			continue
		w = _smooth((abs(v.co.z) - body_r * 0.6) / (body_r * 0.9))
		fin = "Left_WingFin" if v.co.z > 0 else "Right_WingFin"
		for g in list(v.groups):
			mesh.vertex_groups[g.group].add([v.index], g.weight * (1.0 - w), "REPLACE")
		groups[fin].add([v.index], w, "REPLACE")
	blended = sum(1 for v in mesh.data.vertices if sum(1 for g in v.groups if g.weight > 0.1) > 1)
	info = {"method": "spine_gradient+fins", "blended_pct": round(100.0 * blended / len(mesh.data.vertices), 1),
		"unweighted": sum(1 for v in mesh.data.vertices if not v.groups)}
	takeoff = 18
	for f in range(0, takeoff + 1):
		t = f / takeoff
		ph = 2 * math.pi * 6.0 * f / FPS               # ~6 batidas por segundo
		fade = 1.0 - _smooth((t - 0.6) / 0.4)
		spread = -90 + 55 * (1.0 - _smooth(t / 0.8))   # asas saem quase em pé e deitam para os lados
		key_world(rig, f, {"Tail_01": [(Z, 16 * math.sin(ph) * fade)], "Tail_02": [(Z, 26 * math.sin(ph - 1.2) * fade)],
			"Spine": [(Z, -3 * math.sin(ph) * fade)], "Left_WingFin": [(Y, spread)], "Right_WingFin": [(Y, spread)]})
	push(rig, "Takeoff")
	for f in range(0, 31, 2):
		tremble = 2.0 * math.sin(f / 30 * 2 * math.pi * 9)
		key_world(rig, f, {"Left_WingFin": [(Y, -90 + tremble)], "Right_WingFin": [(Y, -90 - tremble)]})
	push(rig, "Glide")
	return rig, info


RIGS = {"dolphin": rig_dolphin, "gull": rig_gull, "tentacle": rig_tentacle, "flyfish": rig_flyfish}


def check_render(name, rig, mesh, frames):
	"""Renders de conferência da deformação (Workbench, textura) em alguns quadros do clipe."""
	os.makedirs(CHECK_DIR, exist_ok=True)
	sc = bpy.context.scene
	sc.render.engine = "BLENDER_WORKBENCH"
	sc.display.shading.light = "STUDIO"
	sc.display.shading.color_type = "TEXTURE"
	sc.render.resolution_x = 420
	sc.render.resolution_y = 420
	mn, mx = vbounds(mesh)
	c = (mn + mx) / 2
	size = max(mx - mn)
	cd = bpy.data.cameras.new("check")
	cam = bpy.data.objects.new("check", cd)
	sc.collection.objects.link(cam)
	sc.camera = cam
	cd.type = "ORTHO"
	cd.ortho_scale = size * 1.5
	d = Vector((1.0, -0.4, 0.35)).normalized() if name != "gull" else Vector((0.15, -1.0, 0.25)).normalized()
	cam.location = c + d * size * 3
	cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
	paths = []
	for f in frames:
		sc.frame_set(f)
		path = os.path.join(CHECK_DIR, "%s_pose_%03d.png" % (name, f))
		sc.render.filepath = path
		bpy.ops.render.render(write_still=True)
		paths.append(path)
	sc.frame_set(0)
	bpy.data.objects.remove(cam, do_unlink=True)
	return paths


CHECK_FRAMES = {"dolphin": [0, 8, 16, 26, 33, 40, 48, 56], "gull": [0, 4, 9, 13, 120], "tentacle": [0, 30, 60, 90],
	"flyfish": [0, 3, 6]}


def build(name, file=None):
	"""file: outro GLB em Assets/ (ex.: o golfinho reto novo que o Pedro vai gerar no Meshy)."""
	spec = dict(SPECS[name])
	if file:
		spec["file"] = file
	os.makedirs(OUT_DIR, exist_ok=True)
	bpy.context.scene.render.fps = FPS
	mesh = import_mesh(spec)
	orient(mesh, spec)
	mesh.name = name.capitalize()
	info = {"name": name, "tris": sum(len(p.vertices) - 2 for p in mesh.data.polygons)}
	if name in RIGS:
		rig, skin_info = RIGS[name](mesh, spec) if name == "gull" else RIGS[name](mesh)
		info["skin"] = skin_info
		info["bones"] = [b.name for b in rig.data.bones]
		info["animations"] = [t.name for t in rig.animation_data.nla_tracks]
		info["check"] = check_render(name, rig, mesh, CHECK_FRAMES[name])
	bpy.context.scene.frame_set(0)
	select_only(list(o for o in bpy.context.scene.objects if o.type in ("MESH", "ARMATURE")))
	out = os.path.join(OUT_DIR, name + ".glb")
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
		export_apply=False, export_image_format="AUTO", export_animations=name in RIGS,
		export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_step=1,
		export_skins=True, export_morph=True, export_def_bones=True)
	info["mb"] = round(os.path.getsize(out) / 1e6, 2)
	print("CREATURE_BUILT", info)
	return info


if __name__ == "__main__" and "--" in sys.argv:
	# "dolphin=Meshy_AI_novo.glb" usa outro arquivo para o mesmo bicho.
	for creature in sys.argv[sys.argv.index("--") + 1:]:
		name, _, file = creature.partition("=")
		build(name, file or None)
