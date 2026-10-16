"""Ilhas animadas no Blender (rodar pela conexão MCP do Blender ou com blender -b -P).

Para cada ilha: importa a ilha texturizada do jogo (Assets/Optimized/island_<nome>.glb: malha, UVs e os
3 mapas do Meshy, sem bake) e a segmentação do Meshy (só para saber quais triângulos são de cada peça).
As peças que se mexem são recortadas da malha original (cada triângulo vai para a parte segmentada
mais próxima), ganham origem no pivô certo e nomes legíveis; o resto da ilha fica uma malha só.
As animações viram faixas NLA (mesmo nome em vários objetos = uma animação no glTF) e o GLB sai
com elas: no Godot viram um AnimationPlayer; o IslandEffects só dispara/repete.

Animações (24 fps). Terminadas em _loop o Godot importa em loop:
  sobre:       chimney_puff (squash antes da baforada, stretch quando ela sai)
  experiencia: cannon_fire_0..7 (coice para dentro do forte + squash & stretch)
  formacao:    idle_loop (poneglyph flutua e gira; palmeiras, copa e folhas balançam)
  projetos:    chest_open (tampa da posição fechada até a aberta) e idle_loop (palmeiras)
  contato:     idle_loop (antenas balançam) e shell_ring (concha vibra); a sala da lanterna fica parada

Uso no Blender: exec(open(r"<repo>/Tools/animate_islands_blender.py").read()); build_all()
"""
import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree

REPO = r"D:\Godot\Projects\portifolio-pedro-ferreira-3d-2026"
FPS = 24
SEGMENTS = {
	"sobre": "Meshy_AI_export_1791510731_part-segmentation.glb",
	"experiencia": "Meshy_AI_export_1791515145_part-segmentation.glb",
	"formacao": "Meshy_AI_export_1791510364_part-segmentation.glb",
	"projetos": "Meshy_AI_export_1791510578_part-segmentation.glb",
	"contato": "Meshy_AI_export_1791508651_part-segmentation.glb",
}
# Peças que se mexem: nome no GLB → parte da segmentação.
MOVING = {
	"sobre": {"Chimney": "model_part8"},
	"experiencia": {"Cannon_%d" % i: "model_part%d" % p for i, p in enumerate([0, 1, 3, 4, 5, 6, 7, 8])},
	"formacao": {"Poneglyph": "model_part6", "Palm_0": "model_part0", "Palm_1": "model_part12",
		"PalmCrown": "model_part15", "Frond_0": "model_part16", "Frond_1": "model_part17"},
	"projetos": {"ChestLid": "model_part17", "Palm_0": "model_part3", "Palm_1": "model_part9", "Palm_2": "model_part10"},
	"contato": {"LanternRoom": "model_part3", "SnailShell": "model_part5", "Antenna_0": "model_part2", "Antenna_1": "model_part6"},
}


def clear_scene():
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o, do_unlink=True)
	for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.actions):
		for d in list(coll):
			if d.users == 0:
				coll.remove(d)


def bounds(objs):
	vs = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
	return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
		Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def vert_bounds(o):
	vs = [o.matrix_world @ v.co for v in o.data.vertices]
	return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
		Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def select_only(objs, active=None):
	for o in bpy.context.scene.objects:
		o.select_set(False)
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = active or objs[0]


def split_moving(name):
	"""Importa a ilha + segmentação; devolve (ilha estática, {nome: objeto}, caixas das partes)."""
	clear_scene()
	bpy.ops.import_scene.gltf(filepath=os.path.join(REPO, "Assets", "Optimized", "island_%s.glb" % name))
	source = [o for o in bpy.context.scene.objects if o.type == "MESH"]
	select_only(source)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	if len(source) > 1:
		bpy.ops.object.join()
	island = bpy.context.view_layer.objects.active
	island.name = "Island"
	s_mn, s_mx = bounds([island])
	before = set(bpy.context.scene.objects)
	bpy.ops.import_scene.gltf(filepath=os.path.join(REPO, "Assets", SEGMENTS[name]))
	parts = [o for o in bpy.context.scene.objects if o not in before and o.type == "MESH"]
	select_only(parts)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	p_mn, p_mx = bounds(parts)
	scale = max(s_mx - s_mn) / max(p_mx - p_mn)
	xf = Matrix.Translation((s_mn + s_mx) / 2) @ Matrix.Scale(scale, 4) @ Matrix.Translation(-(p_mn + p_mx) / 2)
	verts, polys, owner = [], [], []
	part_names = [o.name for o in parts]
	part_boxes = {}
	for index, o in enumerate(parts):
		base = len(verts)
		moved = [xf @ v.co for v in o.data.vertices]
		verts.extend(moved)
		part_boxes[o.name] = (Vector((min(v.x for v in moved), min(v.y for v in moved), min(v.z for v in moved))),
			Vector((max(v.x for v in moved), max(v.y for v in moved), max(v.z for v in moved))))
		for p in o.data.polygons:
			polys.append([base + i for i in p.vertices])
			owner.append(index)
	tree = BVHTree.FromPolygons(verts, polys)
	assign = [part_names[owner[tree.find_nearest(p.center)[2]]] for p in island.data.polygons]
	for o in parts:
		bpy.data.objects.remove(o, do_unlink=True)
	pieces = {}
	for label, part in MOVING[name].items():
		select_only([island])
		bpy.ops.object.mode_set(mode="EDIT")
		bpy.ops.mesh.select_mode(type="FACE")
		bpy.ops.mesh.select_all(action="DESELECT")
		edit = bmesh.from_edit_mesh(island.data)
		edit.faces.ensure_lookup_table()
		count = 0
		for face, a in zip(edit.faces, assign):
			if a == part:
				face.select_set(True)
				count += 1
		edit.select_flush_mode()
		bmesh.update_edit_mesh(island.data)
		if count == 0:
			bpy.ops.object.mode_set(mode="OBJECT")
			print("WARN no faces for", label, part)
			continue
		bpy.ops.mesh.separate(type="SELECTED")
		bpy.ops.object.mode_set(mode="OBJECT")
		piece = [o for o in bpy.context.selected_objects if o != island][0]
		piece.name = label
		piece.data.name = label
		# O importador de glTF deixa em quaternion; as rotações abaixo são em Euler (a tampa volta a quaternion).
		piece.rotation_mode = "XYZ"
		pieces[label] = piece
		assign = [a for a in assign if a != part]
	return island, pieces, part_boxes


def set_origin(obj, point):
	"""Origem (pivô) em `point` sem mexer na malha no mundo."""
	offset = point - obj.matrix_world.translation
	obj.data.transform(Matrix.Translation(-offset))
	obj.matrix_world.translation = point


def base_point(obj):
	mn, mx = vert_bounds(obj)
	return Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))


def center_point(obj):
	mn, mx = vert_bounds(obj)
	return (mn + mx) / 2


def key(obj, frame, location=None, scale=None, rotation=None):
	if location is not None:
		obj.location = location
		obj.keyframe_insert("location", frame=frame)
	if scale is not None:
		obj.scale = scale
		obj.keyframe_insert("scale", frame=frame)
	if rotation is not None:
		if obj.rotation_mode == "QUATERNION":
			obj.rotation_quaternion = rotation
			obj.keyframe_insert("rotation_quaternion", frame=frame)
		else:
			obj.rotation_euler = rotation
			obj.keyframe_insert("rotation_euler", frame=frame)


def push(obj, anim_name):
	"""Guarda a ação ativa do objeto numa faixa NLA com o nome da animação e volta ao repouso."""
	ad = obj.animation_data
	action = ad.action
	action.name = "%s_%s" % (obj.name, anim_name)
	track = ad.nla_tracks.new()
	track.name = anim_name
	start = int(action.frame_range[0])
	track.strips.new(anim_name, start, action)
	ad.action = None


def rest(obj, location, rotation=None):
	obj.location = location
	obj.scale = (1, 1, 1)
	if obj.rotation_mode == "QUATERNION":
		obj.rotation_quaternion = rotation or Quaternion()
	else:
		obj.rotation_euler = rotation or (0, 0, 0)


def sway(obj, anim_name, seconds, amp, periods, phase):
	"""Balanço em X e Y com períodos que fecham o loop (seconds múltiplo dos períodos)."""
	base = obj.location.copy()
	frames = int(seconds * FPS)
	for f in range(0, frames + 1, 3):
		t = f / FPS
		rx = amp * math.sin(2 * math.pi * t / periods[0] + phase)
		ry = amp * 0.8 * math.sin(2 * math.pi * t / periods[1] + phase * 1.7)
		key(obj, f, rotation=(rx, ry, 0.0))
	push(obj, anim_name)
	rest(obj, base)


def build(name):
	prefs = bpy.context.preferences.edit
	old_interp = prefs.keyframe_new_interpolation_type
	prefs.keyframe_new_interpolation_type = "LINEAR"
	bpy.context.scene.render.fps = FPS
	island, pieces, boxes = split_moving(name)
	island_mn, island_mx = bounds([island] + list(pieces.values()))
	center = (island_mn + island_mx) / 2
	size = max(island_mx - island_mn)
	# Escala do jogo (m por unidade da ilha) só para os números abaixo em metros.
	game_width = {"sobre": 28.0, "experiencia": 32.0, "formacao": 30.0, "projetos": 32.0, "contato": 26.0}[name]
	meter = size / game_width
	log = []
	if name == "sobre":
		chimney = pieces["Chimney"]
		set_origin(chimney, base_point(chimney))
		p = chimney.location.copy()
		for f, s in [(0, (1, 1, 1)), (4, (1.22, 1.22, 0.78)), (6, (0.88, 0.88, 1.16)), (10, (1.06, 1.06, 0.95)),
				(14, (0.97, 0.97, 1.02)), (20, (1, 1, 1))]:
			key(chimney, f, scale=s)
		push(chimney, "chimney_puff")
		rest(chimney, p)
	elif name == "experiencia":
		fort = center
		for label, cannon in sorted(pieces.items()):
			set_origin(cannon, base_point(cannon))
			p = cannon.location.copy()
			out = Vector((p.x - fort.x, p.y - fort.y, 0)).normalized()
			back = p - out * 0.3 * meter
			key(cannon, 0, location=p, scale=(1, 1, 1))
			key(cannon, 2, location=back, scale=(1.2, 1.2, 0.8))
			key(cannon, 5, scale=(0.9, 0.9, 1.12))
			key(cannon, 8, scale=(1.05, 1.05, 0.96))
			key(cannon, 12, scale=(1, 1, 1))
			key(cannon, 16, location=p.lerp(back, 0.35))
			key(cannon, 20, location=p)
			push(cannon, "cannon_fire_" + label.split("_")[1])
			rest(cannon, p)
	elif name == "formacao":
		stone = pieces["Poneglyph"]
		set_origin(stone, center_point(stone))
		p = stone.location.copy()
		lift = 0.2 * meter
		frames = 24 * FPS
		for f in range(0, frames + 1, 6):
			t = f / FPS
			z = lift + 0.12 * meter * math.sin(2 * math.pi * t / 4.0)
			key(stone, f, location=p + Vector((0, 0, z)), rotation=(0, 0, -2 * math.pi * f / frames))
		push(stone, "idle_loop")
		rest(stone, p + Vector((0, 0, lift)))
		for i, label in enumerate(["Palm_0", "Palm_1", "PalmCrown", "Frond_0", "Frond_1"]):
			if label in pieces:
				obj = pieces[label]
				set_origin(obj, base_point(obj))
				amp = 0.07 if label.startswith("Palm_") else 0.12
				sway(obj, "idle_loop", 24, amp, [(6.0, 8.0), (8.0, 6.0), (4.8, 6.0), (4.0, 3.0), (3.0, 4.0)][i], i * 1.3)
	elif name == "projetos":
		lid = pieces["ChestLid"]
		lmn, lmx = vert_bounds(lid)
		bmn, bmx = boxes["model_part18"]
		lc, bc = (lmn + lmx) / 2, (bmn + bmx) / 2
		t = Vector((lc.x - bc.x, lc.y - bc.y, 0)).normalized()
		reach = abs(t.x) * (bmx.x - bmn.x) / 2 + abs(t.y) * (bmx.y - bmn.y) / 2
		# Dobradiça e ângulo achados por busca (fica reta sobre o baú quando fechada).
		hinge = Vector((bc.x, bc.y, lmn.z + (bmx.z - lmn.z) * 0.67)) + t * reach * 0.4
		axis = (Matrix.Rotation(math.radians(5), 3, "Z") @ t.cross(Vector((0, 0, 1)))).normalized()
		set_origin(lid, hinge)
		lid.rotation_mode = "QUATERNION"
		p = lid.location.copy()
		for f, deg in [(0, 95.0), (8, 40.0), (12, -6.0), (16, 2.0), (18, 0.0)]:
			key(lid, f, rotation=Quaternion(axis, math.radians(deg)))
		push(lid, "chest_open")
		rest(lid, p, Quaternion(axis, math.radians(95.0)))
		for i, label in enumerate(["Palm_0", "Palm_1", "Palm_2"]):
			if label in pieces:
				obj = pieces[label]
				set_origin(obj, base_point(obj))
				sway(obj, "idle_loop", 24, 0.07, [(6.0, 8.0), (8.0, 4.8), (4.8, 6.0)][i], i * 2.1)
	elif name == "contato":
		# O topo do farol fica parado (quem gira é a luz lá dentro, no Godot): a sala da lanterna só sai
		# separada para o Godot saber onde ela está.
		room = pieces["LanternRoom"]
		set_origin(room, center_point(room))
		for i, label in enumerate(["Antenna_0", "Antenna_1"]):
			obj = pieces[label]
			set_origin(obj, base_point(obj))
			sway(obj, "idle_loop", 20, 0.1, [(5.0, 4.0), (4.0, 5.0)][i], i * 1.9)
		shell = pieces["SnailShell"]
		set_origin(shell, center_point(shell))
		p = shell.location.copy()
		for f in range(0, 30):
			s = 1.0 + (0.05 if f % 2 else -0.04) * (1.0 - f / 30.0)
			key(shell, f, scale=(s, s, s))
		key(shell, 30, scale=(1, 1, 1))
		push(shell, "shell_ring")
		rest(shell, p)
	bpy.context.scene.frame_set(0)
	out = os.path.join(REPO, "Assets", "Optimized", "Islands", "island_%s_parts.glb" % name)
	select_only(list(bpy.context.scene.objects))
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_image_format="AUTO",
		export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True)
	prefs.keyframe_new_interpolation_type = old_interp
	tracks = sorted({t.name for o in bpy.context.scene.objects if o.animation_data for t in o.animation_data.nla_tracks})
	tris = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH"}
	return {"island": name, "pieces": sorted(pieces), "animations": tracks, "tris": tris, "file": out}


def build_all():
	return [build(n) for n in SEGMENTS]
