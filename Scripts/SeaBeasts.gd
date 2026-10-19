extends Node3D

## Bestas do mar (colossos): baleia de madeira (Leste), caranguejo de granito com runas e colosso de
## obsidiana e ossos (Sul).
## Modelos com o rig do Meshy e o clipe contínuo feito no Blender (Tools/animate_meshy_rigs_blender.py).
## Cada uma dá a volta DEVAGAR no circuito do seu setor, que o WorldDecor traça e deixa livre de
## pontos de interesse (world_decor.patrol_paths[nome], velocidade em world_decor.beast_info[nome]).
## O barco bate nelas (corpo animável na camada 1, a mesma das rochas). Som de água empurrada em loop
## e, de tempos em tempos, o som próprio de cada uma (gravações reais, Tools/cut_beast_sfx.sh).
## A tartaruga (WorldDecor) ganha aqui só o som: água em loop e o chamado.

const CUTS := "res://Assets/Sound/SFX/Cuts/"
## nome do circuito → modelo, tamanho (m), "max" = maior lado | "h" = altura, calado (fração da altura
## embaixo d'água), colisor, sons próprios.
## stride/loop (quem anda): quanto o corpo anda por volta do clipe (unidades do modelo, medido no
## Blender por Tools/animate_meshy_rigs_blender.py) e a duração do clipe (s): a velocidade sai daí, para
## o pé de apoio não escorregar. splash: [osso da ponta, osso de antes] que solta borrifo ao sair da água
## e pancada ao bater. glow: runas acesas à noite (Shaders/rune_glow).
## Colossos (sensação Shadow of the Colossus): bem maiores que o barco (5 m), lentos e graves.
const KINDS := {
	# Baleia de madeira: metade do corpo para fora (linha d'água na metade entre a barriga e o dorso,
	# medida no Blender), torre em cima; a cauda bate de -45° a +45° (sai e volta para a água).
	"timber_whale": {"model": "res://Assets/Optimized/Creatures/whale.glb", "size": 320.0, "axis": "max", "draft": 0.35,
		"collider": "capsule", "calls": ["whale_call", "whale_creak"], "call_db": 0.0,
		"splash": [["Bone_014", "Bone_015"]]},
	# Caranguejo de granito com runas: pernas embaixo, carapaça na linha da água e a torre para fora.
	"abyssal_behemoth": {"model": "res://Assets/Optimized/Creatures/behemoth.glb", "size": 220.0, "axis": "max", "draft": 0.4,
		"collider": "outline", "calls": ["behemoth_roar", "behemoth_clack"], "call_db": -1.0,
		"stride": 0.3136, "loop": 10.0, "tempo": 0.6, "glow": true},
	# Colosso de obsidiana e ossos: anda como gorila (nos nós dos dedos), água pela cintura.
	"abyssal_obsidian": {"model": "res://Assets/Optimized/Creatures/obsidian.glb", "size": 190.0, "axis": "h", "draft": 0.44,
		"collider": "cylinder", "calls": ["obsidian_roar", "obsidian_rumble"], "call_db": -1.0,
		"stride": 0.1966, "loop": 10.0, "tempo": 0.6, "spectral": true},
}
const RUNE_GLOW := preload("res://Shaders/rune_glow.gdshader")
const BeastOutline := preload("res://Scripts/BeastOutline.gd")
const BEAST_WATER := preload("res://Shaders/beast_water.gdshader")
const BEAST_WAKE := preload("res://Shaders/beast_wake.gdshader")
## Rastro: quanto tempo um trecho dura (s) e de quantos em quantos metros guarda um ponto (fração da
## largura). O comprimento sai da velocidade (mais rápido = mais longo) e a largura do tamanho.
const WAKE_SECONDS := 60.0
const WAKE_STEP := 0.06
## Tamanho da célula da malha do rastro (m).
const WAKE_CELL := 3.0
## Cor espectral (a do navio fantasma e das boias do Mar Sombrio).
const SPECTRAL := Color(0.35, 1.0, 0.68)
const DROP_SHADER := preload("res://Shaders/water_drop.gdshader")
## Até onde anima e faz onda (m do barco); o planeta esconde o resto.
const ACTIVE_DISTANCE := 1100.0
const DRAW_DISTANCE := 1500.0
## Sons próprios: só de vez em quando (s), graves (tom abaixado) e de longe (m).
const CALL_INTERVAL := Vector2(50.0, 120.0)
const CALL_PITCH := Vector2(0.72, 0.85)
const CALL_RANGE := 800.0

var world: Node3D
var ship: Node3D
var ocean: Node
var planet_radius := 800.0
var beasts: Array[Dictionary] = []
var turtle_sound: Dictionary = {}
var rng := RandomNumberGenerator.new()
var streams := {}
var ripple_timer := 0.0
var drop_material: ShaderMaterial
var rune_materials: Array[ShaderMaterial] = []

func _ready() -> void:
	rng.seed = 20261015
	drop_material = ShaderMaterial.new()
	drop_material.shader = DROP_SHADER
	var decor: Node = world.get("world_decor")
	if decor == null:
		return
	for name in KINDS:
		if not (decor.patrol_paths as Dictionary).has(name):
			push_warning("SeaBeasts: WorldDecor sem circuito para %s" % name)
			continue
		var spec: Dictionary = KINDS[name]
		if not ResourceLoader.exists(spec.model):
			push_warning("SeaBeasts: falta %s" % spec.model)
			continue
		var info: Dictionary = (decor.beast_info as Dictionary).get(name, {})
		_spawn(name, spec, decor.patrol_paths[name], float(info.get("speed", 1.0)))
	_add_turtle_sound(decor)
	print("SEA_BEASTS %s" % [beasts.map(func(b: Dictionary) -> String: return "%s %.0fm %.1fm/s" % [b.name, b.length, b.speed])])

func _stream(name: String) -> AudioStream:
	if not streams.has(name):
		var path := CUTS + name + ".ogg"
		streams[name] = load(path) if ResourceLoader.exists(path) else null
	return streams[name]

func _spawn(name: String, spec: Dictionary, path: Array, speed: float) -> void:
	var root := Node3D.new()
	root.name = name
	add_child(root)
	var model: Node3D = (load(spec.model) as PackedScene).instantiate()
	root.add_child(model)
	var raw := _bounds(model)
	var measure := raw.size.y if spec.axis == "h" else maxf(raw.size.x, raw.size.z)
	var k: float = float(spec.size) / measure
	model.scale = Vector3.ONE * k
	var water := raw.position.y + raw.size.y * float(spec.draft)
	model.position = -Vector3(raw.get_center().x, water, raw.get_center().z) * k
	var size := raw.size * k
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var gi := mesh as GeometryInstance3D
		gi.visibility_range_end = DRAW_DISTANCE
		gi.visibility_range_end_margin = 60.0
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		# A malha deformada sai da caixa de repouso (cauda, pernas): margem para não sumir na borda da tela.
		gi.extra_cull_margin = size.length() * 0.25
	# Colisão: o barco (CharacterBody3D, máscara 1) para no corpo da besta.
	var body := AnimatableBody3D.new()
	body.name = "Body"
	body.sync_to_physics = false
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	if spec.collider == "capsule":
		var capsule := CapsuleShape3D.new()
		capsule.radius = size.x * 0.24
		capsule.height = size.z * 0.86
		shape.shape = capsule
		shape.rotation.x = PI * 0.5
	else:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = minf(size.x, size.z) * 0.36
		cylinder.height = maxf(18.0, size.y * 0.6)
		shape.shape = cylinder
	body.add_child(shape)
	root.add_child(body)
	if spec.collider == "outline":
		# Contorno real na linha d'água (BeastOutline.gd), medido já na pose da animação; até lá, o cilindro.
		get_tree().create_timer(0.6).timeout.connect(func():
			if is_instance_valid(body) and is_instance_valid(model):
				BeastOutline.fill(body, BeastOutline.radii(model, root), -4.0, 16.0))
	# Água empurrada (loop) e os sons próprios.
	var wake := AudioStreamPlayer3D.new()
	wake.name = "Wake"
	wake.stream = _stream("beast_wake_loop")
	wake.volume_db = -4.0
	wake.unit_size = size.z * 0.4
	wake.max_distance = 600.0
	wake.pitch_scale = 0.8
	root.add_child(wake)
	var call_player := AudioStreamPlayer3D.new()
	call_player.name = "Call"
	call_player.volume_db = float(spec.call_db)
	call_player.unit_size = 140.0
	call_player.max_distance = CALL_RANGE + 300.0
	call_player.position = Vector3(0.0, size.y * 0.3, -size.z * 0.3)
	root.add_child(call_player)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player and not player.get_animation_list().is_empty():
		var clip: String = player.get_animation_list()[0]
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		player.play(clip)
		# tempo < 1: o clipe toca mais devagar (passo pesado de colosso) e o corpo anda na mesma proporção.
		player.speed_scale = float(spec.get("tempo", 1.0))
		player.seek(rng.randf() * player.current_animation_length, true)
	# Quem anda: a velocidade é a passada do clipe (sem o pé escorregar), não a do circuito.
	if spec.has("stride"):
		speed = float(spec.stride) * k / float(spec.loop) * float(spec.get("tempo", 1.0))
	# Água em volta (toque na água como nas ilhas; espectral no colosso de ossos) e o rastro.
	var fx := _water_fx(root, size.x, size.z, speed, bool(spec.get("spectral", false)))
	if spec.get("spectral", false):
		root.add_child(_spirit_wisps(size))
	if spec.get("glow", false):
		_add_rune_glow(model)
	var splashes := []
	for pair in spec.get("splash", []):
		splashes.append({"tip": pair[0], "base": pair[1], "out": false, "emitter": _splash_emitter(root, size.z)})
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	# Circuito em metros (fechado): comprimento acumulado de cada ponto.
	var cumulative := PackedFloat32Array([0.0])
	for i in path.size():
		var a: Vector3 = path[i]
		var b: Vector3 = path[(i + 1) % path.size()]
		cumulative.append(cumulative[i] + a.angle_to(b) * planet_radius)
	beasts.append({"name": name, "root": root, "model": model, "player": player, "path": path, "cumulative": cumulative,
		"distance": rng.randf() * cumulative[cumulative.size() - 1], "speed": speed, "length": size.z, "width": size.x, "height": size.y,
		"wake": wake, "call": call_player, "calls": spec.calls, "call_timer": rng.randf_range(4.0, CALL_INTERVAL.y),
		"time": rng.randf() * 100.0, "dir": Vector3.UP, "skeleton": skeleton, "splashes": splashes,
		"rise": _stream("whale_tail_rise"), "slap": _stream("whale_tail_slap"), "fx": fx})
	_place(beasts[beasts.size() - 1], 0.0)

func _bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != node and n is Node3D:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		var box: AABB = t * mi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

## Ponto do circuito a d metros do começo (direção normalizada).
func _point(beast: Dictionary, d: float) -> Vector3:
	var cumulative: PackedFloat32Array = beast.cumulative
	var path: Array = beast.path
	var total := cumulative[cumulative.size() - 1]
	d = fposmod(d, total)
	var i := cumulative.bsearch(d, true) - 1
	i = clampi(i, 0, path.size() - 1)
	var span := maxf(cumulative[i + 1] - cumulative[i], 0.001)
	var a: Vector3 = path[i]
	var b: Vector3 = path[(i + 1) % path.size()]
	return a.slerp(b, (d - cumulative[i]) / span).normalized()

func _place(beast: Dictionary, delta: float) -> void:
	beast.time = float(beast.time) + delta
	beast.distance = float(beast.distance) + float(beast.speed) * delta
	var d := float(beast.distance)
	var dir := _point(beast, d)
	# A frente olha uns metros adiante (curva suave).
	var ahead := _point(beast, d + maxf(6.0, float(beast.length) * 0.3))
	var forward := (ahead - dir).slide(dir).normalized()
	if forward.length() < 0.5:
		return
	var t := float(beast.time)
	var bob := sin(t * 0.4) * 0.3
	var basis := Basis.looking_at(forward, dir).rotated(forward, sin(t * 0.27) * 0.015)
	(beast.root as Node3D).global_transform = Transform3D(basis, dir * (planet_radius + bob))
	beast.dir = dir
	beast.forward = forward

func _process(delta: float) -> void:
	if ship == null:
		return
	var eye: Vector3 = ship.global_position
	ripple_timer -= delta
	var ripple := ripple_timer <= 0.0
	if ripple:
		ripple_timer = 0.3
	for beast in beasts:
		_place(beast, delta)
		var root: Node3D = beast.root
		var dist := root.global_position.distance_to(eye)
		var near := dist < ACTIVE_DISTANCE
		_update_water_fx(beast.fx, root, near)
		var player: AnimationPlayer = beast.player
		if player:
			player.active = near
		var wake: AudioStreamPlayer3D = beast.wake
		if dist < wake.max_distance and not wake.playing and wake.stream:
			wake.play(rng.randf() * 5.0)
		elif dist >= wake.max_distance + 20.0 and wake.playing:
			wake.stop()
		# Onda na proa e nos lados enquanto anda (o mar mexe em volta do corpo).
		if ripple and dist < 300.0 and ocean and ocean.has_method("touch"):
			var forward: Vector3 = beast.get("forward", Vector3.FORWARD)
			var side := forward.cross(beast.dir as Vector3).normalized()
			var flip := 1.0 if Engine.get_process_frames() % 2 == 0 else -1.0
			ocean.touch(root.global_position + forward * float(beast.length) * 0.42, 0.35, float(beast.width) * 0.12)
			ocean.touch(root.global_position + side * flip * float(beast.width) * 0.45, 0.2, float(beast.width) * 0.08)
		if near and not (beast.splashes as Array).is_empty():
			_update_splashes(beast)
		beast.call_timer = float(beast.call_timer) - delta
		if float(beast.call_timer) <= 0.0:
			beast.call_timer = rng.randf_range(CALL_INTERVAL.x, CALL_INTERVAL.y)
			if dist < CALL_RANGE:
				_call(beast["call"], beast["calls"])
	_update_turtle_sound(eye, delta)
	if turtle_sound.has("fx"):
		var t_root: Node3D = turtle_sound.root
		_update_water_fx(turtle_sound.fx, t_root, t_root.global_position.distance_to(eye) < ACTIVE_DISTANCE)
	if world.get("clock"):
		var night_now: float = world.clock.night_at(eye)
		for beast in beasts:
			var ring: ShaderMaterial = beast.fx.ring_material
			ring.set_shader_parameter("night", night_now)
	if world.get("clock"):
		var night: float = world.clock.night_at(eye)
		for material in rune_materials:
			material.set_shader_parameter("night", night)
		drop_material.set_shader_parameter("daylight", 1.0 - night)

## Runas do caranguejo: o brilho da própria textura (pixels claros e saturados, faixa ciano) acende à
## noite, por cima do material original (mesmo shader das runas do WorldDecor).
func _add_rune_glow(model: Node3D) -> void:
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var source := mi.get_active_material(0) as BaseMaterial3D
		if source == null or source.albedo_texture == null:
			continue
		var overlay := ShaderMaterial.new()
		overlay.shader = RUNE_GLOW
		overlay.set_shader_parameter("albedo_map", source.albedo_texture)
		overlay.set_shader_parameter("phase", rng.randf() * TAU)
		overlay.set_shader_parameter("day_strength", 0.1)
		overlay.set_shader_parameter("night_strength", 2.0)
		mi.material_overlay = overlay
		rune_materials.append(overlay)

## Borrifo grande (gotas do barco, water_drop) para a ponta da cauda saindo/batendo na água.
func _splash_emitter(root: Node3D, length: float) -> GPUParticles3D:
	var unit := length / 90.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 2.6 * unit
	quad.material = drop_material
	var emitter := GPUParticles3D.new()
	emitter.name = "TailSplash"
	emitter.top_level = true
	emitter.amount = 90
	emitter.lifetime = 2.6
	emitter.one_shot = true
	emitter.explosiveness = 0.8
	emitter.emitting = false
	emitter.local_coords = false
	emitter.visibility_aabb = AABB(Vector3(-40, -20, -40) * unit, Vector3(80, 70, 80) * unit)
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 5.0 * unit
	motion.direction = Vector3.UP
	motion.spread = 35.0
	motion.initial_velocity_min = 7.0 * sqrt(unit)
	motion.initial_velocity_max = 14.0 * sqrt(unit)
	motion.gravity = Vector3(0, -9.8, 0)
	motion.scale_min = 0.6
	motion.scale_max = 1.6
	emitter.process_material = motion
	emitter.draw_pass_1 = quad
	root.add_child(emitter)
	return emitter

## Ponta da cauda cruzando a linha da água: saindo = borrifo escorrendo + som de água; entrando =
## pancada (borrifo maior, onda no mar e o impacto molhado grave).
func _update_splashes(beast: Dictionary) -> void:
	var skeleton := beast.skeleton as Skeleton3D
	if skeleton == null:
		return
	var root: Node3D = beast.root
	var up: Vector3 = beast.dir
	for s in beast.splashes:
		var tip_i := skeleton.find_bone(s.tip)
		var base_i := skeleton.find_bone(s.base)
		if tip_i < 0 or base_i < 0:
			continue
		var tip_o := skeleton.global_transform * skeleton.get_bone_global_pose(tip_i).origin
		var base_o := skeleton.global_transform * skeleton.get_bone_global_pose(base_i).origin
		var tip := tip_o + (tip_o - base_o)
		var water := float(ocean.height_at(tip)) if ocean else 0.0
		var out := tip.length() - planet_radius > water + 1.0
		if out == bool(s.out):
			continue
		s.out = out
		var emitter := s.emitter as GPUParticles3D
		var surface := tip.normalized() * (planet_radius + water + 0.5)
		emitter.global_position = surface
		var motion := emitter.process_material as ParticleProcessMaterial
		motion.gravity = -up * 9.8
		motion.direction = up
		emitter.amount_ratio = 0.6 if out else 1.0
		emitter.restart()
		if ocean and ocean.has_method("touch"):
			ocean.touch(surface, 0.5 if out else 1.2, float(beast.width) * (0.15 if out else 0.3))
		print("SEA_BEASTS %s cauda %s" % [beast.name, "sai" if out else "bate"])
		var sound := AudioStreamPlayer3D.new()
		sound.stream = beast.rise if out else beast.slap
		sound.volume_db = -2.0 if out else 2.0
		sound.unit_size = 120.0
		sound.max_distance = 900.0
		sound.pitch_scale = rng.randf_range(0.85, 0.95)
		root.add_child(sound)
		sound.global_position = surface
		sound.play()
		sound.finished.connect(sound.queue_free)

func _call(player: AudioStreamPlayer3D, names: Array) -> void:
	var stream := _stream(String(names[rng.randi() % names.size()]))
	if stream == null or player.playing:
		return
	player.stream = stream
	player.pitch_scale = rng.randf_range(CALL_PITCH.x, CALL_PITCH.y)
	player.play()

## Tartaruga (WorldDecor): água em loop e o chamado de vez em quando, presos na raiz dela.
func _add_turtle_sound(decor: Node) -> void:
	var turtle: Dictionary = decor.get("turtle")
	if turtle.is_empty():
		return
	var root: Node3D = (turtle.item as Dictionary).root
	var wake := AudioStreamPlayer3D.new()
	wake.name = "TurtleWake"
	wake.stream = _stream("beast_wake_loop")
	wake.volume_db = -6.0
	wake.unit_size = 70.0
	wake.max_distance = 600.0
	wake.pitch_scale = 0.8
	root.add_child(wake)
	var call_player := AudioStreamPlayer3D.new()
	call_player.name = "TurtleCall"
	call_player.volume_db = -3.0
	call_player.unit_size = 140.0
	call_player.max_distance = CALL_RANGE + 300.0
	call_player.position = Vector3(0.0, 12.0, -60.0)
	root.add_child(call_player)
	turtle_sound = {"root": root, "wake": wake, "call": call_player, "timer": rng.randf_range(6.0, CALL_INTERVAL.y)}
	# A tartaruga também ganha o toque na água e o rastro (anda a TURTLE_SPEED do WorldDecor).
	var item: Dictionary = turtle.item
	var width := float(item.get("radius", 40.0)) * 2.0
	turtle_sound.fx = _water_fx(root, width * 0.62, width * 0.75, float(decor.TURTLE_SPEED), false)

func _update_turtle_sound(eye: Vector3, delta: float) -> void:
	if turtle_sound.is_empty():
		return
	var dist := (turtle_sound.root as Node3D).global_position.distance_to(eye)
	var wake: AudioStreamPlayer3D = turtle_sound.wake
	if dist < wake.max_distance and not wake.playing and wake.stream:
		wake.play()
	elif dist >= wake.max_distance + 20.0 and wake.playing:
		wake.stop()
	turtle_sound.timer = float(turtle_sound.timer) - delta
	if float(turtle_sound.timer) <= 0.0:
		turtle_sound.timer = rng.randf_range(CALL_INTERVAL.x, CALL_INTERVAL.y)
		if dist < CALL_RANGE:
			_call(turtle_sound["call"], ["turtle_call"])

# --- Água em volta e rastro ------------------------------------------------------------

## Disco elíptico em volta do corpo (Shaders/beast_water) e a fita do rastro (Shaders/beast_wake).
## width/length em metros (corpo na linha da água), speed em m/s.
func _water_fx(root: Node3D, width: float, length: float, speed: float, spectral: bool) -> Dictionary:
	var spread := 2.2 if spectral else 1.6
	var ring_material := ShaderMaterial.new()
	ring_material.shader = BEAST_WATER
	ring_material.render_priority = 1
	ring_material.set_shader_parameter("ring_radius", (width + length) * 0.25 * spread)
	ring_material.set_shader_parameter("contact", 1.0 / spread)
	ring_material.set_shader_parameter("push", clampf(speed / 2.0, 0.2, 1.0))
	ring_material.set_shader_parameter("ring_speed", 0.12 + 0.08 * speed)
	ring_material.set_shader_parameter("spectral", 1.0 if spectral else 0.0)
	ring_material.set_shader_parameter("spectral_glow", Vector3(SPECTRAL.r, SPECTRAL.g, SPECTRAL.b))
	var ring := MeshInstance3D.new()
	ring.name = "BeastWater"
	ring.mesh = _ring_mesh(24, 72)
	ring.scale = Vector3(width * 0.5 * spread, 1.0, length * 0.5 * spread)
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.extra_cull_margin = 20.0
	ring.visibility_range_end = DRAW_DISTANCE
	root.add_child(ring)
	var wake_material := ShaderMaterial.new()
	wake_material.shader = BEAST_WAKE
	wake_material.render_priority = 1
	wake_material.set_shader_parameter("strength", clampf(0.45 + speed / 2.5, 0.45, 1.2))
	wake_material.set_shader_parameter("scale_m", width)
	var wake_mesh := ImmediateMesh.new()
	var wake := MeshInstance3D.new()
	wake.name = "BeastWake"
	wake.top_level = true
	wake.mesh = wake_mesh
	wake.material_override = wake_material
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wake.custom_aabb = AABB(Vector3.ONE * -2000.0, Vector3.ONE * 4000.0)
	root.add_child(wake)
	wake.global_transform = Transform3D.IDENTITY
	for material in [ring_material, wake_material]:
		if ocean and ocean.has_method("register_material"):
			ocean.register_material(material)
	return {"ring": ring, "ring_material": ring_material, "wake": wake, "wake_mesh": wake_mesh, "points": [],
		"width": width, "length": length, "max_points": int(maxf(speed * WAKE_SECONDS, length * 0.9) / maxf(width * WAKE_STEP, 1.0)) + 2}

## Guarda por onde a popa passou e refaz a fita: abre com a idade (V do rastro) e some no fim.
func _update_water_fx(fx: Dictionary, root: Node3D, near: bool) -> void:
	var wake: MeshInstance3D = fx.wake
	(fx.ring as Node3D).visible = near
	wake.visible = near
	var up := root.global_position.normalized()
	var forward := (-root.global_basis.z).slide(up).normalized()
	var stern: Vector3 = root.global_position - forward * float(fx.length) * 0.45
	var points: Array = fx.points
	var step := maxf(float(fx.width) * WAKE_STEP, 1.0)
	if points.is_empty():
		# Ao nascer, o rastro já vem inteiro atrás dele (em linha reta), sem esperar ele andar tudo.
		for i in range(int(fx.max_points) - 1, 0, -1):
			points.append(stern - forward * step * i)
	var changed := false
	if (points[points.size() - 1] as Vector3).distance_to(stern) >= step:
		changed = true
		points.append(stern)
		while points.size() > int(fx.max_points):
			points.pop_front()
	if not near or points.size() < 2:
		return
	# A fita só é refeita quando ganha um ponto ou a cada segundo (as ondas mexem nela no shader).
	var now := Time.get_ticks_msec() * 0.001
	if not changed and now - float(fx.get("built", -10.0)) < 1.0:
		return
	fx.built = now
	# Mais novo primeiro: a popa agora, depois os pontos guardados do mais recente ao mais velho.
	var trail: Array = [stern]
	for i in range(points.size() - 1, -1, -1):
		trail.append(points[i])
	# Linhas da fita a cada ~WAKE_CELL m (ao longo e de lado): a fita é colada nas ondas vértice a
	# vértice, então precisa ser fina o bastante para as ondas não a cobrirem entre um vértice e outro.
	var rows: Array = []
	var total := 0.0
	for i in trail.size() - 1:
		total += (trail[i] as Vector3).distance_to(trail[i + 1])
	var walked := 0.0
	for i in trail.size() - 1:
		var p0: Vector3 = trail[i]
		var p1: Vector3 = trail[i + 1]
		var seg := p0.distance_to(p1)
		var parts := maxi(1, int(ceil(seg / WAKE_CELL)))
		var along := (p0 - p1).slide(p0.normalized()).normalized()
		if along.length() < 0.5:
			along = forward
		for k in parts:
			var t := float(k) / parts
			rows.append([p0.lerp(p1, t), along, (walked + seg * t) / maxf(total, 0.001)])
		walked += seg
	rows.append([trail[trail.size() - 1], forward, 1.0])
	var cols := clampi(int(float(fx.width) * 0.64 * 2.6 / WAKE_CELL), 6, 24)
	var mesh: ImmediateMesh = fx.wake_mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rows.size() - 1:
		for c in cols:
			for corner in [[r, c], [r + 1, c], [r, c + 1], [r, c + 1], [r + 1, c], [r + 1, c + 1]]:
				var row: Array = rows[corner[0]]
				var p: Vector3 = row[0]
				var age: float = row[2]
				var side := (row[1] as Vector3).cross(p.normalized()).normalized()
				var half := float(fx.width) * 0.32 * (1.0 + 1.6 * age)
				var v := -1.0 + 2.0 * float(corner[1]) / cols
				mesh.surface_set_uv(Vector2(age, v))
				mesh.surface_add_vertex(p + side * half * v)
	mesh.surface_end()

func _ring_mesh(rings: int, segments: int) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rings + 1:
		var r := float(j) / rings
		for i in segments + 1:
			var a := TAU * i / segments
			tool.set_uv(Vector2(float(i) / segments, r))
			tool.set_normal(Vector3.UP)
			tool.add_vertex(Vector3(cos(a) * r, 0.0, sin(a) * r))
	var row := segments + 1
	for j in rings:
		for i in segments:
			var v := j * row + i
			for k in [v, v + 1, v + row, v + 1, v + row + 1, v + row]:
				tool.add_index(k)
	return tool.commit()

## Fogos-fátuos em volta do colosso de ossos: luzinhas verde-espectrais girando devagar em volta do
## corpo, da água até a cintura, como espíritos (o Mar Sombrio é assombrado a qualquer hora).
func _spirit_wisps(size: Vector3) -> CPUParticles3D:
	var wisps := CPUParticles3D.new()
	wisps.name = "SpiritWisps"
	wisps.amount = 46
	wisps.lifetime = 9.0
	wisps.preprocess = 9.0
	wisps.local_coords = true
	wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	wisps.emission_ring_axis = Vector3.UP
	wisps.emission_ring_radius = maxf(size.x, size.z) * 0.62
	wisps.emission_ring_inner_radius = maxf(size.x, size.z) * 0.35
	wisps.emission_ring_height = size.y * 0.3
	wisps.position = Vector3(0.0, size.y * 0.12, 0.0)
	wisps.direction = Vector3.UP
	wisps.spread = 60.0
	wisps.initial_velocity_min = 0.6
	wisps.initial_velocity_max = 1.8
	wisps.gravity = Vector3(0.0, 0.15, 0.0)
	wisps.orbit_velocity_min = 0.015
	wisps.orbit_velocity_max = 0.04
	wisps.damping_min = 0.05
	wisps.damping_max = 0.2
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.45, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(0.4, 1.0, 0.7, 0.0), Color(0.45, 1.0, 0.72, 0.95), Color(0.3, 0.9, 0.8, 0.45),
		Color(0.55, 1.0, 0.75, 0.9), Color(0.3, 0.8, 0.7, 0.0)])
	wisps.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * maxf(2.5, size.y * 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Mistura normal (não aditiva): de dia um brilho aditivo some no céu claro e vira branco.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	soft.gradient = g
	mat.albedo_texture = soft
	quad.material = mat
	wisps.mesh = quad
	var light := OmniLight3D.new()
	light.light_color = SPECTRAL
	light.light_energy = 1.4
	light.omni_range = maxf(size.x, size.z) * 0.9
	light.shadow_enabled = false
	light.position = Vector3(0.0, size.y * 0.1, 0.0)
	wisps.add_child(light)
	return wisps
