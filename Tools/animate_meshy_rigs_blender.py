"""Animações no Blender para os modelos que o Pedro riggou no Meshy ("(WITH RIG) Meshy_AI_…" em Assets/).

Uso (sem interface; malhas grandes):
	blender -b --factory-startup -P Tools/animate_meshy_rigs_blender.py -- gull tentacle flyfish turtle whale behemoth obsidian
	(o golfinho NÃO sai daqui: o rig do Meshy dele é o modelo antigo; o golfinho reto é de Tools/rig_creatures_blender.py)
ou pela conexão MCP do Blender:
	exec(open(r"<repo>/Tools/animate_meshy_rigs_blender.py", encoding="utf-8").read()); build("whale")

- Esqueleto e pesos são os do Meshy (SmartRig): nada de ossos nossos nem pesos refeitos.
- Malha ORIGINAL (sem decimar), materiais/texturas como vieram; só sai a esfera solta ("Icosphere")
  que o Meshy deixa no arquivo.
- Pose de repouso no espaço do jogo: frente = +Y do Blender (= -Z no Godot), tamanho e origem iguais
  aos dos GLBs anteriores (o jogo usa as mesmas medidas). O Meshy entrega tudo com a frente em -Y e
  1,7 de altura; o giro/escala vão para o esqueleto e a malha (transform_apply), sem mexer nos pesos.
- Rotações dadas em eixos do MUNDO, convertidas para o espaço de cada osso (key_world). Para as
  colunas (golfinho, baleia), o corpo é um "campo" de ângulo ao longo do comprimento: cada osso recebe
  o ângulo do seu trecho menos o do pai.

Saída: Assets/Optimized/Creatures/<nome>.glb e renders de conferência em Builds/Creatures/meshy_<nome>_*.png.
"""
import bpy
import math
import os
import sys
from mathutils import Vector, Matrix, Quaternion

REPO = r"D:\Godot\Projects\portifolio-pedro-ferreira-3d-2026"
OUT_DIR = os.path.join(REPO, "Assets", "Optimized", "Creatures")
CHECK_DIR = os.path.join(REPO, "Builds", "Creatures")
FPS = 30
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)

# arquivo em Assets/, tamanho no jogo (eixo, medida), origem ("center" = centro da caixa, "base" = centro
# embaixo). Mesmas medidas dos GLBs anteriores (Tools/rig_creatures_blender.py, turtle_solid_blender.py).
SPECS = {
	"gull": {"file": "(WITH RIG) Meshy_AI_flying_seagull_glidin_1009235109_image-to-3d-texture.glb", "size": ("x", 2.6), "origin": "center"},
	"tentacle": {"file": "(WITH RIG) Meshy_AI_epic_kraken_tentacle__1009235502_image-to-3d-texture.glb", "size": ("z", 1.0), "origin": "base"},
	"flyfish": {"file": "(WITH RIG) Meshy_AI_straight_flying_fish__1009234142_image-to-3d-texture.glb", "size": ("y", 0.5), "origin": "center"},
	# Mesma tartaruga do modelo sem rig (×2): 1,904 de largura e origem no centro da caixa, como antes —
	# a linha d'água e os efeitos do WorldDecor continuam valendo.
	"turtle": {"file": "(WITH RIG) Meshy_AI_swimming_stone_turtle_1010000522_image-to-3d-texture (1).glb", "size": ("x", 1.904), "origin": "center"},
	# Bestas (o WorldDecor escala para metros pelo maior lado).
	"whale": {"file": "(WITH RIG)Meshy_AI_east_timber_whale_col_1010232033_image-to-3d-texture.glb", "size": ("y", 2.0), "origin": "center"},
	"behemoth": {"file": "(WITH RIG) Meshy_AI_south_abyssal_behemot_1010232020_image-to-3d-texture.glb", "size": ("y", 2.0), "origin": "center"},
	"obsidian": {"file": "(WITH RIG) Meshy_AI_south_abyssal_obsidia_1011002022_image-to-3d-texture.glb", "size": ("z", 2.0), "origin": "center"},
}


def _smooth(x):
	x = min(max(x, 0.0), 1.0)
	return x * x * (3 - 2 * x)


def select_only(objs, active=None):
	for o in bpy.context.scene.objects:
		o.select_set(False)
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = active or objs[0]


def load(spec):
	"""Importa o GLB riggado, tira a esfera solta e põe frente/tamanho/origem no esqueleto e na malha."""
	if bpy.app.background:
		bpy.ops.wm.read_factory_settings(use_empty=True)
	else:
		# Pela conexão MCP: não reinicia o Blender (o complemento do MCP cairia); só esvazia a cena.
		for o in list(bpy.data.objects):
			bpy.data.objects.remove(o, do_unlink=True)
		for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.actions, bpy.data.armatures,
				bpy.data.cameras):
			for d in list(coll):
				if d.users == 0:
					coll.remove(d)
	bpy.context.scene.render.fps = FPS
	bpy.ops.import_scene.gltf(filepath=os.path.join(REPO, "Assets", spec["file"]))
	for o in list(bpy.context.scene.objects):
		if o.type == "MESH" and not o.vertex_groups:
			bpy.data.objects.remove(o, do_unlink=True)
	rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
	mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
	# Solta a malha (mantendo a posição) para aplicar o transform em cada um sem confusão de pai.
	select_only([mesh])
	bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
	turn = Matrix.Rotation(math.pi, 4, "Z")                # frente do Meshy (-Y) → +Y
	cos = [turn @ mesh.matrix_world @ v.co for v in mesh.data.vertices]
	mn = Vector((min(c.x for c in cos), min(c.y for c in cos), min(c.z for c in cos)))
	mx = Vector((max(c.x for c in cos), max(c.y for c in cos), max(c.z for c in cos)))
	axis = "xyz".index(spec["size"][0])
	k = spec["size"][1] / (mx[axis] - mn[axis])
	c = (mn + mx) / 2
	pivot = c if spec["origin"] == "center" else Vector((c.x, c.y, mn.z))
	m = Matrix.Scale(k, 4) @ Matrix.Translation(-pivot) @ turn
	for o in (rig, mesh):
		o.matrix_world = m @ o.matrix_world
	bpy.context.view_layer.update()
	select_only([rig, mesh], rig)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	select_only([mesh, rig], rig)
	bpy.ops.object.parent_set(type="OBJECT", keep_transform=True)
	for mod in mesh.modifiers:
		if mod.type == "ARMATURE":
			mod.object = rig
	rig.data.pose_position = "POSE"
	for pb in rig.pose.bones:
		pb.rotation_mode = "QUATERNION"
	return rig, mesh


def key_world(rig, frame, pose):
	"""pose: {osso: [(eixo_mundo, graus), ...]}; ossos fora da lista voltam ao repouso."""
	for pb in rig.pose.bones:
		q = Quaternion()
		rest = pb.bone.matrix_local.to_3x3()
		for axis, deg in pose.get(pb.name, []):
			local = (rest.inverted() @ Vector(axis)).normalized()
			q = Quaternion(local, math.radians(deg)) @ q
		pb.rotation_quaternion = q
		pb.keyframe_insert("rotation_quaternion", frame=frame)


def push(rig, name):
	ad = rig.animation_data
	action = ad.action
	action.name = name
	track = ad.nla_tracks.new()
	track.name = name
	track.strips.new(name, int(action.frame_range[0]), action)
	ad.action = None
	for pb in rig.pose.bones:
		pb.rotation_quaternion = Quaternion()


def bone(rig, name):
	return rig.data.bones[name]


def side(rig, name):
	"""+1 se o osso fica do lado +X (direita), -1 se do lado -X."""
	b = bone(rig, name)
	return 1.0 if (b.head_local.x + b.tail_local.x) > 0 else -1.0


def spine_pose(rig, spine, field, axis, s_of, ref=None):
	"""Coluna como campo de ângulo: field(s) = inclinação do trecho em s (0 cauda … 1 cabeça). Cada
	osso da lista recebe field(s do meio dele) menos o ângulo absoluto do pai (na lista ou não)."""
	absolute = {}
	pose = {}
	base = field(ref) if ref is not None else 0.0
	order = sorted(spine, key=lambda n: len(bone(rig, n).parent_recursive))
	for name in order:
		b = bone(rig, name)
		mid = (b.head_local + b.tail_local) / 2
		absolute[name] = field(s_of(mid)) - base
		parent = b.parent
		parent_abs = 0.0
		while parent is not None:
			if parent.name in absolute:
				parent_abs = absolute[parent.name]
				break
			parent = parent.parent
		pose[name] = [(axis, absolute[name] - parent_abs)]
	return pose


def body_s(rig):
	ys = [p for b in rig.data.bones for p in (b.head_local.y, b.tail_local.y)]
	lo, hi = min(ys), max(ys)
	return lambda p: (p.y - lo) / (hi - lo)


def anim_gull(rig):
	"""Fly_Flap (4,5 s, loop): 5 batidas de verdade (ombro ±42° em volta de um centro um pouco acima da
	pose de planeio, mão/primárias atrasadas: dobram na subida e abrem na descida) e 1,5 s planando."""
	shoulders = ["Bone_019", "Bone_021"]
	hands = ["Bone_025", "Bone_029"]
	tips = ["Bone_031", "Bone_034", "Bone_037", "Bone_039", "Bone_042", "Bone_045"]
	beat, beats, glide = 18, 5, 45
	for f in range(beats * beat + 1):
		ph = 2 * math.pi * f / beat
		down = -4 + 42 * math.sin(ph)               # + abaixa a asa
		hand = 26 * math.sin(ph - 1.0)
		tip = 14 * math.sin(ph - 1.6)
		body = -4 * math.sin(ph)                    # peito sobe quando as asas descem
		pose = {"Bone_004": [(X, body)], "Bone_017": [(X, -body * 0.6)], "Bone_003": [(X, 3 * math.sin(ph - 0.5))]}
		for b in shoulders:
			pose[b] = [(Y, side(rig, b) * down)]
		for b in hands:
			pose[b] = [(Y, side(rig, b) * hand)]
		for b in tips:
			pose[b] = [(Y, side(rig, b) * tip)]
		key_world(rig, f, pose)
	start = beats * beat
	for f in range(start + 3, start + glide + 1, 3):
		g = (f - start) / glide
		ease = _smooth(min(g * 4.0, 1.0)) * _smooth(min((1.0 - g) * 4.0, 1.0))
		pose = {"Bone_004": [(Y, 6 * math.sin(2 * math.pi * g) * ease)], "Bone_003": [(Z, 4 * math.sin(2 * math.pi * g) * ease)]}
		for b in shoulders:
			pose[b] = [(Y, side(rig, b) * -4 * (1.0 - ease))]
		key_world(rig, f, pose)
	push(rig, "Fly_Flap")


def anim_tentacle(rig):
	"""Thrash (4 s, loop): arcos sinuosos para fora e de volta (onda subindo da base à ponta), balanço
	de lado e a ponta enrolando."""
	names = ["Bone_000", "Bone_012", "Bone_011", "Bone_010", "Bone_009", "Bone_008", "Bone_007", "Bone_006",
		"Bone_005", "Bone_004", "Bone_003", "Bone_002", "Bone_001"]
	frames = 120
	n = len(names)
	for f in range(0, frames + 1, 2):
		t = f / frames
		pose = {}
		for i, name in enumerate(names):
			k = i / (n - 1)
			out = (5 + 8 * k) * math.sin(2 * math.pi * t - k * 2.6)
			sway = (3 + 6 * k) * math.sin(2 * math.pi * 2 * t - k * 3.4 + 1.0)
			curl = 12 * k * k * (0.6 + 0.4 * math.sin(2 * math.pi * 2 * t - 1.2)) if k > 0.5 else 0.0
			pose[name] = [(X, out + curl), (Y, sway)]
		key_world(rig, f, pose)
	push(rig, "Thrash")


def anim_flyfish(rig):
	"""As nadadeiras-asa vêm em pé no Meshy (uma para cima, outra para baixo, no plano do corpo):
	girar -90° em volta do eixo do corpo deita a de cima para um lado e a de baixo para o outro.
	Takeoff (0,6 s): cauda em S rápido (de lado) e as asas abrindo. Glide (1 s, loop): asas abertas
	paradas com um tremor leve."""
	up = ["Bone_007", "Bone_009", "Bone_017"]
	down = ["Bone_011", "Bone_013", "Bone_019"]
	tail = ["Bone_015", "Bone_014", "Bone_028", "Bone_027", "Bone_026"]
	takeoff = 18
	for f in range(takeoff + 1):
		t = f / takeoff
		ph = 2 * math.pi * 6.0 * f / FPS
		fade = 1.0 - _smooth((t - 0.6) / 0.4)
		spread = -90 + 55 * (1.0 - _smooth(t / 0.8))
		pose = {b: [(Y, spread)] for b in up + down}
		for i, b in enumerate(tail):
			pose[b] = [(Z, (8 + 6 * i) * math.sin(ph - 0.7 * i) * fade)]
		key_world(rig, f, pose)
	push(rig, "Takeoff")
	for f in range(0, 31, 2):
		tremble = 2.0 * math.sin(f / 30 * 2 * math.pi * 9)
		pose = {b: [(Y, -90 + tremble)] for b in up}
		pose.update({b: [(Y, -90 - tremble)] for b in down})
		key_world(rig, f, pose)
	push(rig, "Glide")


# Tartaruga: casco e ilha são estrutura RÍGIDA (como o caranguejo). Disco do casco no espaço do modelo
# (mesmas medidas da tartaruga anterior): centro (0, -0,19), raio 0,50; a transição para os membros
# acontece numa faixa estreita fora dele.
TURTLE_SHELL_CENTER = (0.0, -0.19)
TURTLE_SHELL_R = 0.50
TURTLE_SHELL_BLEND = 0.06
# Altura (z do modelo) da borda de baixo do casco: acima disso é casco, mesmo fora do disco.
TURTLE_RIM_Z = -0.19
# Só estes ossos deformam: nadadeiras (raiz e ponta), pescoço e cabeça. O resto vai para o osso raiz.
TURTLE_LIMBS = ["Bone_012", "Bone_013", "Bone_014", "Bone_015", "Bone_016", "Bone_017", "Bone_018", "Bone_019",
	"Bone_010", "Bone_011"]
TURTLE_ROOT = "Bone_001"


def turtle_rigid_shell(rig):
	"""Refaz só a divisão dos pesos do Meshy: dentro do disco do casco tudo 100% no osso raiz (casco e
	ilha não deformam nunca); fora, o peso dos ossos que não são membro (cauda, barriga, topo, coluna)
	passa para a raiz e os membros entram suavemente na faixa da borda. Devolve contagens."""
	mesh = next(o for o in rig.children if o.type == "MESH")
	groups = {g.name: g for g in mesh.vertex_groups}
	root = groups[TURTLE_ROOT]
	index_name = {g.index: g.name for g in mesh.vertex_groups}
	counts = {"rigid": 0, "blend": 0, "limb": 0}
	cx, cy = TURTLE_SHELL_CENTER
	for v in mesh.data.vertices:
		r = math.hypot(v.co.x - cx, v.co.y - cy)
		u = _smooth((r - TURTLE_SHELL_R) / TURTLE_SHELL_BLEND)
		# A borda do casco passa do disco atrás e dos lados (o Meshy pôs ela nas traseiras): nadadeira só
		# abaixo da borda (z < TURTLE_RIM_Z); pescoço e cabeça só pelo disco.
		under_rim = _smooth((TURTLE_RIM_Z - v.co.z) / TURTLE_SHELL_BLEND)
		limb = {}
		for g in v.groups:
			name = index_name[g.group]
			if name in TURTLE_LIMBS and g.weight > 0.0:
				limb[name] = g.weight * u * (1.0 if name in ("Bone_010", "Bone_011") else under_rim)
		total = sum(limb.values())
		if total > 1.0:
			limb = {k: w / total for k, w in limb.items()}
			total = 1.0
		for g in list(v.groups):
			mesh.vertex_groups[g.group].remove([v.index])
		for name, w in limb.items():
			if w > 1e-4:
				groups[name].add([v.index], w, "REPLACE")
		root.add([v.index], max(0.0, 1.0 - total), "REPLACE")
		counts["rigid" if total < 1e-4 else ("limb" if u >= 1.0 else "blend")] += 1
	return counts


def anim_turtle(rig):
	"""Swim (7 s, loop; colossal e lento), como a tartaruga anterior: dianteiras em remada longa (desce varrendo para trás
	com a lâmina chapada, volta emplumada, a ponta atrasada), traseiras de leme, pescoço balançando e a
	cabeça olhando em volta, corpo rolando de leve. Ossos do Meshy: dianteiras Bone_013→012 e
	Bone_015→014, traseiras Bone_017→016 e Bone_019→018, pescoço Bone_011 → cabeça Bone_010."""
	counts = turtle_rigid_shell(rig)
	fronts = ["Bone_013", "Bone_015"]
	rears = ["Bone_017", "Bone_019"]
	frames = 210
	for f in range(0, frames + 1, 2):
		s = f / frames
		if s < 0.55:
			u = 0.5 - 0.5 * math.cos(math.pi * s / 0.55)
			flap, sweep, feather = -38 + 62 * u, 14 - 36 * u, 0.0
		else:
			u = 0.5 - 0.5 * math.cos(math.pi * (s - 0.55) / 0.45)
			flap, sweep = 24 - 62 * u, -22 + 36 * u
			feather = 32 * math.sin(math.pi * (s - 0.55) / 0.45)
		lag = math.sin(2 * math.pi * s - 0.9)
		pose = {}
		for b in fronts:
			sd = side(rig, b)
			bb = bone(rig, b)
			along = (bb.tail_local - bb.head_local).normalized()
			tip = bb.children[0].name
			pose[b] = [(along, -feather * sd), (Z, sweep * sd), (Y, flap * sd)]
			pose[tip] = [(Y, 10 * lag * sd), (Z, -6 * lag * sd)]
		paddle = 9 * math.sin(2 * math.pi * s - 1.2)
		for b in rears:
			sd = side(rig, b)
			# Traseiras: leme logo abaixo da superfície (caídas ~35° para baixo; só as dianteiras sobem ao remar).
			pose[b] = [(Z, paddle * sd), (Y, (34 + 3 * math.sin(2 * math.pi * s)) * sd)]
			pose[bone(rig, b).children[0].name] = [(Z, 5 * math.sin(2 * math.pi * s - 2.0) * sd), (Y, 12 * sd)]
		pose["Bone_011"] = [(Z, 5 * math.sin(2 * math.pi * s)), (X, 2 * math.sin(4 * math.pi * s))]
		pose["Bone_010"] = [(Z, 14 * math.sin(2 * math.pi * s + 1.3)), (X, 4 * math.sin(4 * math.pi * s + 0.5))]
		pose["Bone_001"] = [(Y, 1.5 * math.sin(2 * math.pi * s)), (X, 1.0 * math.sin(2 * math.pi * s - 0.6))]
		key_world(rig, f, pose)
	push(rig, "Swim")
	return {"weights": counts}


def anim_whale(rig):
	"""Swim (12 s, loop), baleia colossal: o RABO fica dentro d'água (o modelo vem com a cauda subindo
	para fora; os últimos ossos baixam no repouso) com uma ondulação vertical lenta e pequena. Uma vez
	por ciclo vem a propulsão: a cauda sobe devagar para fora d'água (~4 s), segura no alto e desce
	numa pancada (~0,6 s), depois volta ao nado. O jogo solta o borrifo quando a ponta sai da água e a
	pancada quando ela bate (SeaBeasts, osso da ponta Bone_014)."""
	spine = ["Bone_009", "Bone_008", "Bone_018", "Bone_017", "Bone_016", "Bone_015", "Bone_014"]
	rest_down = {"Bone_017": 10.0, "Bone_016": 26.0, "Bone_015": 24.0, "Bone_014": 14.0}
	s_of = body_s(rig)
	frames = 360
	for f in range(0, frames + 1, 2):
		t = f / frames
		# Propulsão: sobe 0,45→0,78 (devagar), segura até 0,82, desce na pancada até 0,87, assenta até 0,95.
		if t < 0.45:
			big = 0.0
		elif t < 0.78:
			big = _smooth((t - 0.45) / 0.33)
		elif t < 0.82:
			big = 1.0
		elif t < 0.87:
			u = (t - 0.82) / 0.05
			big = 1.0 - 1.25 * u * u
		else:
			big = -0.25 * (1.0 - _smooth((t - 0.87) / 0.08))

		def field(s):
			tail = (1.0 - s) ** 1.7
			swim = 5.0 * tail * math.sin(2 * math.pi * 2 * t - 2.4 * (1.0 - s))
			return swim - 62.0 * big * tail

		pose = spine_pose(rig, spine, field, X, s_of, ref=s_of(bone(rig, "Bone_009").head_local))
		for name, deg in rest_down.items():
			pose[name][0] = (X, pose[name][0][1] + deg)
		pose["Bone_001"] = [(X, 1.0 * math.sin(2 * math.pi * 2 * t + 0.8) + 2.0 * big)]
		for b in ("Bone_005", "Bone_007"):
			sd = side(rig, b)
			pose[b] = [(Y, sd * 8 * math.sin(2 * math.pi * 2 * t)), (Z, sd * 6 * math.sin(2 * math.pi * 2 * t - 1.0))]
			pose[bone(rig, b).children[0].name] = [(Y, sd * 6 * math.sin(2 * math.pi * 2 * t - 0.8))]
		for b in ("Bone_011", "Bone_013"):
			sd = side(rig, b)
			pose[b] = [(Y, sd * 5 * math.sin(2 * math.pi * 2 * t - 1.5))]
		key_world(rig, f, pose)
	push(rig, "Swim")


def gait(p, duty, amp):
	"""Ciclo de um membro (p de 0 a 1): apoio = fração duty, o pé vai da frente (+amp) para trás (-amp)
	em velocidade CONSTANTE (o corpo passa por cima, sem vai-e-volta); balanço = levanta (lift 0→1→0) e
	volta para a frente. Devolve (ângulo, lift)."""
	p = p % 1.0
	if p < duty:
		return amp * (1.0 - 2.0 * p / duty), 0.0
	u = (p - duty) / (1.0 - duty)
	return -amp + 2.0 * amp * _smooth(u), math.sin(math.pi * u)


def _legs(rig, roots):
	"""Pernas ordenadas da frente (+Y) para trás, por lado."""
	by_side = {1.0: [], -1.0: []}
	for r in roots:
		by_side[side(rig, r)].append(r)
	for sd in by_side:
		by_side[sd].sort(key=lambda r: -bone(rig, r).head_local.y)
	return by_side


def anim_behemoth(rig):
	"""Walk (10 s, loop = 2 passadas), caranguejo de granito: a carapaça (corpo e torre) fica RÍGIDA,
	só pernas, braços e garras se mexem. Marcha alternada em dois grupos (perna 1 e 3 de um lado com 2
	e 4 do outro), apoio de 65% com o pé indo para trás em velocidade constante e balanço levantando a
	perna (quadril sobe, joelho abre). Braços: sobem e baixam devagar, um de cada vez, o punho gira e
	a pinça abre e fecha."""
	legs = _legs(rig, ["Bone_023", "Bone_028", "Bone_033", "Bone_048", "Bone_038", "Bone_043", "Bone_058", "Bone_053"])
	frames = 300
	for f in range(0, frames + 1, 2):
		t = f / frames
		pose = {}
		for sd, roots in legs.items():
			for i, r in enumerate(roots):
				p = 2 * t + 0.5 * ((i + (0 if sd > 0 else 1)) % 2)
				swing, lift = gait(p, 0.65, 10.0)
				pose[r] = [(Z, swing * sd), (Y, -14 * lift * sd)]
				knee = bone(rig, r).children[0]
				pose[knee.name] = [(Y, 10 * lift * sd)]
				pose[knee.children[0].name] = [(Y, -6 * lift * sd)]
		for k, claw in enumerate(("Bone_012", "Bone_018")):
			sd = side(rig, claw)
			ph = 2 * math.pi * (t + 0.5 * k)
			raise_arm = 8 * (0.5 - 0.5 * math.cos(ph))
			pose[claw] = [(X, raise_arm), (Z, -sd * 5 * math.sin(ph))]
			upper = bone(rig, claw).children[0]
			fore = upper.children[0]
			wrist = fore.children[0]
			pose[upper.name] = [(X, 6 * math.sin(ph - 0.6))]
			pose[fore.name] = [(Z, sd * 7 * math.sin(ph - 1.0))]
			pose[wrist.name] = [(Z, sd * 12 * max(0.0, math.sin(2 * ph + k)))]
		key_world(rig, f, pose)
	push(rig, "Walk")
	return {"loop_s": frames / FPS, "steps": 2}


def anim_obsidian(rig):
	"""Walk (10 s, loop), colosso de obsidiana e ossos andando como um GORILA (knuckle-walking
	quadrúpede): os braços longos chegam no chão e entram na marcha. Sequência lateral, como os gorilas
	andam: pé esquerdo, mão esquerda, pé direito, mão direita (cada membro defasado de 1/4 de ciclo).
	Apoio de 60% com o membro indo para trás em velocidade constante (o corpo passa por cima: marcha
	contínua, não vai-e-volta); no balanço a perna dobra o joelho e o braço dobra o cotovelo para tirar
	a mão do chão e trazer à frente. Ombros e quadril rolam com a passada, o tronco inclina um pouco
	para a frente e a cabeça acompanha."""
	legs = {side(rig, b): b for b in ("Bone_010", "Bone_015")}
	arms = {side(rig, b): b for b in ("Bone_023", "Bone_028")}
	order = {("leg", -1.0): 0.0, ("arm", -1.0): 0.25, ("leg", 1.0): 0.5, ("arm", 1.0): 0.75}
	frames = 300
	for f in range(0, frames + 1, 2):
		t = f / frames
		pose = {}
		for sd, hip in legs.items():
			swing, lift = gait(t + order[("leg", sd)], 0.6, 13.0)
			knee = bone(rig, hip).children[0]
			foot = knee.children[0]
			pose[hip] = [(X, swing + 10 * lift)]
			pose[knee.name] = [(X, -30 * lift)]
			pose[foot.name] = [(X, 16 * lift)]
		for sd, shoulder in arms.items():
			swing, lift = gait(t + order[("arm", sd)], 0.6, 12.0)
			upper = bone(rig, shoulder).children[0]
			fore = upper.children[0]
			hand = fore.children[0]
			pose[shoulder] = [(X, 4.0)]
			pose[upper.name] = [(X, swing + 6 * lift), (Y, sd * -4 * lift)]
			pose[fore.name] = [(X, 22 * lift)]
			pose[hand.name] = [(X, -14 * lift)]
		# Rolar do corpo: o lado que apoia recebe o peso.
		roll = 3.0 * math.sin(2 * math.pi * t)
		pose["Bone_001"] = [(Y, roll)]
		pose["Bone_005"] = [(X, -6.0), (Y, -roll * 0.6), (Z, 3 * math.sin(2 * math.pi * t + 1.2))]
		pose["Bone_002"] = [(X, 1.5 * math.sin(4 * math.pi * t))]
		pose["Bone_018"] = [(X, 4.0 + 2.5 * math.sin(4 * math.pi * t + 0.6)), (Z, 6 * math.sin(2 * math.pi * t * 0.5 + 0.7))]
		key_world(rig, f, pose)
	push(rig, "Walk")
	return {"loop_s": frames / FPS, "steps": 1}


def stride(rig, roots, clip):
	"""Quanto o corpo anda por ciclo do clipe (unidades do modelo): o pé de apoio vai para trás em
	velocidade constante; soma o recuo em Y da ponta do membro nos trechos de apoio de um ciclo."""
	sc = bpy.context.scene
	ad = rig.animation_data
	for track in ad.nla_tracks:
		track.mute = track.name != clip
	end = int(ad.nla_tracks[clip].strips[0].frame_end)

	def tip(name):
		b = rig.pose.bones[name]
		while b.children:
			b = b.children[0]
		return (rig.matrix_world @ b.tail).copy()

	total = 0.0
	for r in roots:
		ys = []
		for f in range(0, end + 1):
			sc.frame_set(f)
			ys.append(tip(r).y)
		total += sum(a - b for a, b in zip(ys, ys[1:]) if b < a)
	for track in ad.nla_tracks:
		track.mute = False
	sc.frame_set(0)
	return total / len(roots)


ANIMS = {"gull": anim_gull, "tentacle": anim_tentacle, "flyfish": anim_flyfish,
	"turtle": anim_turtle, "whale": anim_whale, "behemoth": anim_behemoth, "obsidian": anim_obsidian}

# Membros de apoio para medir a passada (o jogo anda na mesma velocidade para o pé não escorregar).
STRIDE_LIMBS = {"behemoth": ["Bone_023", "Bone_038"], "obsidian": ["Bone_010", "Bone_015"]}


def check_render(name, rig, mesh):
	"""Renders de conferência (Workbench, textura) em 4 quadros de cada clipe, vista 3/4."""
	os.makedirs(CHECK_DIR, exist_ok=True)
	sc = bpy.context.scene
	sc.render.engine = "BLENDER_WORKBENCH"
	sc.display.shading.light = "STUDIO"
	sc.display.shading.color_type = "TEXTURE"
	sc.render.resolution_x = 400
	sc.render.resolution_y = 400
	cos = [v.co for v in mesh.data.vertices]
	mn = Vector((min(c.x for c in cos), min(c.y for c in cos), min(c.z for c in cos)))
	mx = Vector((max(c.x for c in cos), max(c.y for c in cos), max(c.z for c in cos)))
	c = (mn + mx) / 2
	size = max(mx - mn)
	cd = bpy.data.cameras.new("check")
	cam = bpy.data.objects.new("check", cd)
	sc.collection.objects.link(cam)
	sc.camera = cam
	cd.type = "ORTHO"
	cd.ortho_scale = size * 1.45
	d = Vector((1.0, 0.8, 0.45)).normalized() if name not in ("gull", "flyfish") else Vector((0.25, 1.0, 0.35)).normalized()
	cam.location = c + d * size * 3
	cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
	paths = []
	ad = rig.animation_data
	for track in ad.nla_tracks:
		strip = track.strips[0]
		for other in ad.nla_tracks:
			other.mute = other != track
		start, end = int(strip.frame_start), int(strip.frame_end)
		for i in range(4):
			f = start + (end - start) * i // 4
			sc.frame_set(f)
			path = os.path.join(CHECK_DIR, "meshy_%s_%s_%03d.png" % (name, track.name, f))
			sc.render.filepath = path
			bpy.ops.render.render(write_still=True)
			paths.append(path)
	for track in ad.nla_tracks:
		track.mute = False
	sc.frame_set(0)
	bpy.data.objects.remove(cam, do_unlink=True)
	return paths


def build(name, render=True):
	spec = SPECS[name]
	rig, mesh = load(spec)
	mesh.name = name.capitalize()
	extra = ANIMS[name](rig) or {}
	info = {"name": name, "verts": len(mesh.data.vertices), "bones": len(rig.data.bones),
		"animations": [t.name for t in rig.animation_data.nla_tracks], **extra}
	if name in STRIDE_LIMBS:
		info["stride"] = round(stride(rig, STRIDE_LIMBS[name], "Walk"), 4)
		zs = [v.co.z for v in mesh.data.vertices]
		info["height"] = round(max(zs) - min(zs), 4)
	if render:
		info["check"] = len(check_render(name, rig, mesh))
	bpy.context.scene.frame_set(0)
	select_only([mesh, rig], rig)
	os.makedirs(OUT_DIR, exist_ok=True)
	out = os.path.join(OUT_DIR, name + ".glb")
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
		export_apply=False, export_image_format="AUTO", export_animations=True,
		export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_step=1,
		export_skins=True, export_morph=True, export_def_bones=False)
	info["mb"] = round(os.path.getsize(out) / 1e6, 1)
	print("MESHY_RIG_BUILT", info)
	return info


if __name__ == "__main__" and "--" in sys.argv:
	for creature in sys.argv[sys.argv.index("--") + 1:]:
		build(creature)
