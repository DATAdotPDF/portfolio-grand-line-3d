extends Node3D

## Vida no mar (nem o Wind Waker nem o nosso estudo tinham isso; ideia e código nossos):
## - GOLFINHOS: raros (a cada ~3–5 min, e só metade das vezes). Um grupo de 2 a 4 surge atrás
##   do barco, ao lado, com rumo próprio fixo no mundo (o do barco naquela hora), ultrapassa
##   saltando em arco e segue viagem. Eles NÃO seguem as viradas do barco.
## - PEIXES: só em volta das ilhas principais; cardumes pequenos (6–12) pulam de uma vez
##   perto do barco. Arcos curtos, respingo na saída e na entrada.
## Malhas geradas aqui (provisórias): o golfinho será trocado por um modelo do Meshy
## (ver Documentation/Assets_Meshy_Pendentes.md); o nado fica no shader de qualquer forma.

const CREATURE := preload("res://Shaders/sea_creature.gdshader")
const BLOW := preload("res://Assets/Sound/SFX/Generated/whale_blow.wav")
const SeaShadowsScript = preload("res://Scripts/SeaShadows.gd")
const Shore = preload("res://Scripts/Shoreline.gd")
## Peixes só bem no entorno das ilhas: até esta distância da costa medida.
const FISH_COAST_DISTANCE := 70.0
## Célula do atlas com a silhueta do golfinho (sombra embaixo d'água antes do salto).
const DOLPHIN_SHADOW_KIND := 6
## Silhueta do golfinho embaixo d'água (célula 6 do atlas): comprimento e largura (m).
const DOLPHIN_SHADOW_SIZE := Vector2(3.7, 1.5)
const MAX_DOLPHINS := 4
## Golfinho e peixe-voador do Meshy riggados/animados no Blender (Tools/rig_creatures_blender.py):
## frente = -Z, golfinho com 2,8 m (barco: 5,3 m) e clipe "Swim_Leap" (um ciclo do salto: 0-55% no ar, curva suave e
## cabeça entrando primeiro; o resto nadando com ondulação vertical); peixe-voador com 0,5 m e clipes
## "Takeoff" (cauda em S saindo da água) e "Glide" (asas abertas e paradas).
const DOLPHIN_SCENE := preload("res://Assets/Optimized/Creatures/dolphin.glb")
const FLYFISH_SCENE := preload("res://Assets/Optimized/Creatures/flyfish.glb")
const MAX_FLYFISH := 12
## O modelo tem 0,5 m (tamanho real); no jogo, visto do barco, sumia: ~0,9 m, estilizado.
const FLYFISH_SCALE := 1.8
const MAX_FISH := 40

@export var dolphin_min_interval := 240.0
@export var dolphin_max_interval := 420.0
@export var fish_interval_near_island := Vector2(8.0, 20.0)

var world: Node3D
var ship: Node3D
var ocean: Node
var planet_radius := 800.0
var rng := RandomNumberGenerator.new()
var dolphins: Array[Dictionary] = []
var fish: Array[Dictionary] = []
var dolphin_timer := 90.0
var fish_timer := 6.0
var dolphin_pool: Array[Node3D] = []
## Peixes-voadores: cardumes pequenos saltando por cima das cristas (spawn_flying_school).
var flying_fish: Array[Dictionary] = []
var flyfish_pool: Array[Node3D] = []
var fish_node: MultiMeshInstance3D
var fish_material: ShaderMaterial
## Encontros com silhuetas embaixo d'água (grupos, biomas, reações): SeaShadows.gd.
var sea_shadows: Node3D

func _ready() -> void:
	rng.randomize()
	fish_material = ShaderMaterial.new()
	fish_material.shader = CREATURE
	fish_material.set_shader_parameter("lateral", true)
	fish_material.set_shader_parameter("amplitude", 0.05)
	fish_material.set_shader_parameter("frequency", 16.0)
	fish_material.set_shader_parameter("shine", 0.8)
	dolphin_pool = _creature_pool(DOLPHIN_SCENE, MAX_DOLPHINS, "Dolphin")
	flyfish_pool = _creature_pool(FLYFISH_SCENE, MAX_FLYFISH, "FlyingFish")
	for f in flyfish_pool:
		_player(f).get_animation("Glide").loop_mode = Animation.LOOP_LINEAR
	sea_shadows = SeaShadowsScript.new()
	sea_shadows.name = "SeaShadows"
	sea_shadows.world = world
	sea_shadows.ship = ship
	sea_shadows.ocean = ocean
	sea_shadows.planet_radius = planet_radius
	add_child(sea_shadows)
	fish_node = _multimesh_node("Fish", _build_fish_mesh(), fish_material, MAX_FISH)

func _multimesh_node(node_name: String, mesh: ArrayMesh, material: ShaderMaterial, count: int) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	multimesh.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.top_level = true
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(node)
	return node

# --- Malhas ---------------------------------------------------------------------

## Corpo "lofted": anéis ao longo de Z (frente = -Z). profile = [[t, raio, altura_centro], ...].
## Cor por altura: dorso escuro, barriga clara. UV.y = t (para o nado no shader).
func _loft(tool: SurfaceTool, length: float, profile: Array, segments: int, back: Color, belly: Color, width := 1.0) -> void:
	var rings: Array = []
	for p in profile:
		var t: float = p[0]
		var ring: Array = []
		for i in segments + 1:
			var a := TAU * i / segments
			var v := Vector3(cos(a) * float(p[1]) * width, sin(a) * float(p[1]) + float(p[2]), (t - 0.5) * length)
			ring.append(v)
		rings.append(ring)
	for j in rings.size() - 1:
		for i in segments:
			var quad := [rings[j][i], rings[j + 1][i], rings[j + 1][i + 1], rings[j][i + 1]]
			var ts := [profile[j][0], profile[j + 1][0], profile[j + 1][0], profile[j][0]]
			for k in [0, 1, 2, 0, 2, 3]:
				_vertex(tool, quad[k], ts[k], back, belly, float(profile[j][1]) + 0.001)

func _vertex(tool: SurfaceTool, v: Vector3, t: float, back: Color, belly: Color, scale_ref: float) -> void:
	var shade := smoothstep(-0.35, 0.25, v.y / maxf(scale_ref, 0.05))
	tool.set_color(belly.lerp(back, shade))
	tool.set_uv(Vector2(0.0, t))
	tool.add_vertex(v)

func _fin(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, t: float, color: Color) -> void:
	for v in [a, b, c, a, c, b]:  # dois lados
		tool.set_color(color)
		tool.set_uv(Vector2(0.0, t))
		tool.add_vertex(v)

## Golfinho provisório (~2,4 m): rostro, melão, corpo, pedúnculo, nadadeira dorsal, peitorais
## e caudal horizontal.
## Peixe provisório (~0,55 m; um pouco grande de propósito, para ler de longe): fuso prateado com cauda em V.
func _build_fish_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var back := Color(0.22, 0.34, 0.42)
	var belly := Color(0.85, 0.88, 0.9)
	var length := 0.55
	var profile := [[0.0, 0.012, 0.0], [0.12, 0.05, 0.0], [0.35, 0.07, 0.0], [0.7, 0.04, 0.0], [0.88, 0.012, 0.0]]
	_loft(tool, length, profile, 6, back, belly, 0.45)
	var z := func(t: float) -> float: return (t - 0.5) * length
	_fin(tool, Vector3(0, 0, z.call(0.86)), Vector3(0, 0.09, z.call(1.05)), Vector3(0, -0.09, z.call(1.05)), 1.0, back)
	tool.generate_normals()
	return tool.commit()

# --- Comportamento --------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_instance_valid(ship) or ocean == null:
		return
	if "enabled" in ship and not ship.enabled:
		_draw()
		return
	var night: float = 1.0 - clampf(world.sun.light_energy / 1.15, 0.0, 1.0) if world.sun else 0.0
	fish_material.set_shader_parameter("night", night)
	var calm: bool = ocean.badness_at(ship.global_position) < 1.0
	# Na hora marcada, se o barco estiver parado ou numa tempestade, tenta de novo em 5 s
	# (antes esperava o intervalo inteiro de novo e o grupo quase nunca aparecia).
	dolphin_timer -= delta
	if dolphin_timer <= 0.0:
		# Esporádico: mesmo na hora certa, só metade das vezes aparece um grupo.
		# Nunca perto de ciclone (só o kraken aparece lá) nem durante o evento do kraken.
		var kraken_busy: bool = world.get("kraken_event") != null and int(world.kraken_event.get("phase")) != 0
		if dolphins.is_empty() and sea_shadows.groups.is_empty() and calm and not kraken_busy and not sea_shadows.near_cyclone(ship.global_position) and ship.measured_speed > 2.0 and rng.randf() < 0.5:
			spawn_pod(rng.randi_range(2, 4))
			dolphin_timer = rng.randf_range(dolphin_min_interval, dolphin_max_interval)
		else:
			dolphin_timer = 10.0 if dolphins.is_empty() else rng.randf_range(dolphin_min_interval, dolphin_max_interval)
	fish_timer -= delta
	if fish_timer <= 0.0:
		# Peixes só no entorno das ilhas (até 70 m da costa); em mar aberto, nada.
		var near_island := _coast_distance(ship.global_position) < FISH_COAST_DISTANCE
		fish_timer = rng.randf_range(fish_interval_near_island.x, fish_interval_near_island.y) if near_island else 4.0
		if calm and near_island:
			spawn_school(rng.randi_range(6, 12))
	_update_dolphins(delta)
	_update_fish(delta)
	_update_flying_fish(delta)
	_draw()

## Distância até a costa medida da ilha mais próxima (INF longe de todas).
func _coast_distance(point: Vector3) -> float:
	var best := INF
	for island in world.islands:
		if point.distance_to(island.global_position) < 400.0:
			best = minf(best, Shore.distance_to_coast(island, point))
	return best

func _nearest_island_distance(point: Vector3) -> float:
	var best := INF
	for island in world.islands:
		best = minf(best, point.distance_to(island.global_position))
	return best

func _splash(at: Vector3, count: int, strength: float) -> void:
	var weather: Node = world.get("weather")
	if weather and weather.get("spray"):
		weather.spray.burst(at, count, strength)

func _ship_frame() -> Array:
	var up: Vector3 = ship.global_position.normalized()
	var forward: Vector3 = ship.heading.slide(up).normalized()
	return [forward, up, forward.cross(up).normalized()]

## Grupo novo: nasce de um lado, a 30–40 m, já embaixo d'água, e nada até as vagas.
func spawn_pod(count: int) -> void:
	var frame := _ship_frame()
	# Rumo próprio, fixo no mundo: o do barco na hora em que aparecem. Depois eles NÃO seguem
	# as viradas do barco (passam ao lado, ultrapassam e seguem viagem).
	var course: Vector3 = frame[0]
	var speed := maxf(float(ship.drive_speed) + 1.5, 6.0)
	for i in mini(count, MAX_DOLPHINS):
		var side := 1.0 if i % 2 == 0 else -1.0
		dolphins.append({
			"position": ship.global_position + frame[2] * side * rng.randf_range(4.0, 7.5) - frame[0] * rng.randf_range(8.0, 16.0),
			"course": course,
			"speed": speed * rng.randf_range(0.95, 1.08),
			"wander": rng.randf_range(0.0, TAU),
			"cycle": rng.randf_range(0.0, 1.5), "under": rng.randf_range(1.0, 2.0), "air": rng.randf_range(0.9, 1.2),
			"height": rng.randf_range(1.4, 2.4), "depth": -1.4, "pitch": 0.0, "stay": rng.randf_range(25.0, 40.0),
			"age": 0.0, "was_above": false, "heading": course,
		})
		dolphins[dolphins.size() - 1]["shadow"] = sea_shadows.make_plate(DOLPHIN_SHADOW_KIND, DOLPHIN_SHADOW_SIZE.x, DOLPHIN_SHADOW_SIZE.y)
	print("SEALIFE dolphins=%d" % dolphins.size())

func _update_dolphins(delta: float) -> void:
	for i in range(dolphins.size() - 1, -1, -1):
		var d: Dictionary = dolphins[i]
		d.age += delta
		var leaving: bool = d.age > d.stay
		var pos: Vector3 = d.position
		var up := pos.normalized()
		# Rumo transportado pela esfera + um zigue-zague leve de cada golfinho.
		var course: Vector3 = (d.course as Vector3).slide(up).normalized()
		d.course = course
		d.wander += delta * 0.6
		var heading := course.rotated(up, sin(d.wander) * deg_to_rad(10.0))
		d.heading = heading
		pos += heading * float(d.speed) * delta
		pos = _keep_off_hull(pos)
		# Salto: arco acima da água, depois um tempo nadando embaixo (invisível sob o mar).
		d.cycle += delta
		var period: float = d.air + d.under
		if d.cycle > period:
			d.cycle -= period
			d.air = rng.randf_range(0.9, 1.2)
			d.under = rng.randf_range(1.0, 2.2) * (4.0 if leaving else 1.0)
			d.height = rng.randf_range(1.0, 1.8)
		var lift: float = d.depth
		var vertical := 0.0
		if d.cycle < d.air and not leaving:
			var s: float = d.cycle / d.air
			lift = d.depth + (d.height - d.depth) * 4.0 * s * (1.0 - s)
			vertical = (d.height - d.depth) * 4.0 * (1.0 - 2.0 * s) / d.air
		var surface: Vector3 = ocean.surface_at(pos)
		pos = surface + surface.normalized() * lift
		d.position = pos
		d.pitch = lerpf(d.pitch, atan2(vertical, maxf(d.speed, 1.0)), 1.0 - exp(-10.0 * delta))
		var above := lift > 0.0
		if above != d.was_above:
			_splash(surface, 5, 1.0)
		d.was_above = above
		_update_dolphin_shadow(d, surface, heading, lift, delta)
		if (leaving and d.age > d.stay + 6.0) or pos.distance_to(ship.global_position) > 250.0:
			sea_shadows.free_plate(d.get("shadow", []))
			dolphins.remove_at(i)

## Golfinhos nunca atravessam o barco: dentro de uma elipse em volta do casco (um pouco maior
## que a chalupa), são empurrados para o lado mais perto.
func _keep_off_hull(pos: Vector3) -> Vector3:
	var frame := _ship_frame()
	var rel: Vector3 = pos - ship.global_position
	var along: float = rel.dot(frame[0])
	var side: float = rel.dot(frame[2])
	var half_length := 4.2
	var half_width := 2.6
	var e := (along / half_length) * (along / half_length) + (side / half_width) * (side / half_width)
	if e >= 1.0:
		return pos
	var wanted := half_width * sqrt(maxf(0.0, 1.0 - (along / half_length) * (along / half_length)))
	var sign_side := 1.0 if side >= 0.0 else -1.0
	return pos + (frame[2] as Vector3) * sign_side * (wanted - absf(side))

## Silhueta embaixo d'água enquanto o golfinho nada, um pouco atrás dele (o corpo entra na
## água antes da cauda); serpenteia. Aparece/some com fade suave ao mergulhar/saltar.
func _update_dolphin_shadow(d: Dictionary, surface: Vector3, heading: Vector3, lift: float, delta: float) -> void:
	var entry: Array = d.get("shadow", [])
	if entry.is_empty():
		return
	var node: MeshInstance3D = entry[0]
	var material: ShaderMaterial = entry[1]
	var up := surface.normalized()
	var forward := heading.slide(up).normalized()
	var behind := (surface - forward * 1.1).normalized() * planet_radius
	node.global_transform = Transform3D(Basis.looking_at(forward, up), behind)
	var target := smoothstep(0.05, 0.9, -lift)
	var life := smoothstep(0.0, 1.5, float(d.age)) * (1.0 - smoothstep(float(d.stay) + 2.0, float(d.stay) + 6.0, float(d.age)))
	# Fade suave: a opacidade persegue o alvo (~0,25 s para entrar/sair).
	d["shade"] = lerpf(float(d.get("shade", 0.0)), target, 1.0 - exp(-4.0 * delta))
	d["swim"] = float(d.get("swim", 0.0)) + delta * 7.0
	material.set_shader_parameter("swim", d.swim)
	material.set_shader_parameter("wiggle", 1.8)
	material.set_shader_parameter("opacity", float(d.shade) * life * 0.85)
	sea_shadows.push_patch(material)

## Cardume: aparece num ponto a 10–25 m, à frente da câmera, e os peixes pulam escalonados.
func spawn_school(count: int) -> void:
	var frame := _ship_frame()
	var camera := get_viewport().get_camera_3d()
	var look: Vector3 = (-camera.global_basis.z).slide(frame[1]).normalized() if camera else frame[0]
	var right := look.cross(frame[1]).normalized()
	var center: Vector3 = ship.global_position + look * rng.randf_range(10.0, 25.0) + right * rng.randf_range(-12.0, 12.0)
	# O cardume também tem de ficar no entorno da ilha (e não em cima da areia).
	var coast := _coast_distance(center)
	if coast > FISH_COAST_DISTANCE or coast < 4.0:
		return
	var direction: Vector3 = right.rotated(frame[1], rng.randf_range(-0.6, 0.6)) * (1.0 if rng.randf() < 0.5 else -1.0)
	for i in count:
		if fish.size() >= MAX_FISH:
			break
		var start: Vector3 = center + right * rng.randf_range(-3.0, 3.0) + look * rng.randf_range(-3.0, 3.0)
		fish.append({
			"start": start, "direction": direction.rotated(frame[1], rng.randf_range(-0.3, 0.3)),
			"delay": rng.randf_range(0.0, 1.8), "duration": rng.randf_range(0.55, 0.85),
			"distance": rng.randf_range(2.0, 3.5), "height": rng.randf_range(0.7, 1.4), "age": 0.0,
			"splashed_in": false, "splashed_out": false, "position": start, "pitch": 0.0,
		})

func _update_fish(delta: float) -> void:
	for i in range(fish.size() - 1, -1, -1):
		var f: Dictionary = fish[i]
		f.age += delta
		var s: float = (f.age - f.delay) / f.duration
		if s < 0.0:
			f.position = Vector3.ZERO
			continue
		if s > 1.0:
			fish.remove_at(i)
			continue
		var flat: Vector3 = f.start + (f.direction as Vector3) * f.distance * s
		var surface: Vector3 = ocean.surface_at(flat)
		var h: float = -0.2 + (f.height + 0.2) * 4.0 * s * (1.0 - s)
		f.position = surface + surface.normalized() * h
		f.pitch = atan2((f.height + 0.2) * 4.0 * (1.0 - 2.0 * s) / f.duration, f.distance / f.duration)
		if not f.splashed_out and s > 0.08:
			f.splashed_out = true
			_splash(surface, 2, 0.3)
		if not f.splashed_in and s > 0.92:
			f.splashed_in = true
			_splash(surface, 2, 0.3)

func _draw() -> void:
	for i in dolphin_pool.size():
		var node := dolphin_pool[i]
		node.visible = i < dolphins.size()
		if not node.visible:
			continue
		var d: Dictionary = dolphins[i]
		node.global_transform = _creature_transform(d.position, d.heading, d.pitch)
		# Swim_Leap acompanha o salto: o trecho do ar (0-55% do clipe) cobre o tempo no ar e o resto,
		# o tempo nadando embaixo d'água (a ondulação segue sem parar).
		var player := _player(node)
		var length := player.get_animation("Swim_Leap").length
		var in_air: bool = d.cycle < d.air and not (d.age > d.stay)
		var t: float = 0.55 * float(d.cycle) / float(d.air) if in_air else 0.55 + 0.45 * clampf((float(d.cycle) - float(d.air)) / maxf(float(d.under), 0.1), 0.0, 1.0)
		player.seek(clampf(t, 0.0, 0.999) * length, true)
	for i in flyfish_pool.size():
		var node := flyfish_pool[i]
		node.visible = i < flying_fish.size()
		if node.visible:
			var f: Dictionary = flying_fish[i]
			var t := _creature_transform(f.position, f.heading, f.pitch)
			node.global_transform = Transform3D(t.basis.scaled(Vector3.ONE * FLYFISH_SCALE), t.origin)
	var multimesh := fish_node.multimesh
	var shown := 0
	for f in fish:
		if f.position == Vector3.ZERO:
			continue
		multimesh.set_instance_transform(shown, _creature_transform(f.position, f.direction, f.pitch))
		shown += 1
	multimesh.visible_instance_count = shown

## Instâncias escondidas de um bicho animado (o AnimationPlayer vem do GLB).
func _creature_pool(scene: PackedScene, count: int, label: String) -> Array[Node3D]:
	var pool: Array[Node3D] = []
	for i in count:
		var node := scene.instantiate() as Node3D
		node.name = "%s%d" % [label, i]
		node.top_level = true
		node.visible = false
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		pool.append(node)
	return pool

func _player(node: Node) -> AnimationPlayer:
	return node.find_child("AnimationPlayer", true, false) as AnimationPlayer

## Cardume de peixes-voadores (2-6) saltando por cima das cristas, na frente do barco. Público para
## os biomas (WorldDecor) chamarem no setor Oeste; `at` = centro do cardume (padrão: à frente do barco).
func spawn_flying_school(count: int, at := Vector3.ZERO) -> void:
	var frame := _ship_frame()
	var center: Vector3 = at if at != Vector3.ZERO else ship.global_position + frame[0] * rng.randf_range(10.0, 18.0) + frame[2] * rng.randf_range(-8.0, 8.0)
	var course: Vector3 = (frame[0] as Vector3).rotated(center.normalized(), rng.randf_range(-0.6, 0.6))
	for i in mini(count, MAX_FLYFISH - flying_fish.size()):
		var spot: Vector3 = center + (frame[2] as Vector3) * rng.randf_range(-3.0, 3.0) + course * rng.randf_range(-3.0, 3.0)
		flying_fish.append({"position": spot, "heading": course, "pitch": 0.0, "speed": rng.randf_range(10.0, 13.0),
			"cycle": -rng.randf_range(0.0, 0.8), "air": rng.randf_range(1.4, 2.4), "under": rng.randf_range(0.5, 1.0),
			"height": rng.randf_range(0.8, 1.8), "jumps": rng.randi_range(3, 5), "was_above": false})
		_player(flyfish_pool[flying_fish.size() - 1]).play("Glide", -1, rng.randf_range(0.9, 1.15))
	print("SEALIFE flying_fish=%d" % flying_fish.size())

func _update_flying_fish(delta: float) -> void:
	for i in range(flying_fish.size() - 1, -1, -1):
		var f: Dictionary = flying_fish[i]
		var up: Vector3 = (f.position as Vector3).normalized()
		var heading: Vector3 = (f.heading as Vector3).slide(up).normalized()
		f.heading = heading
		var pos: Vector3 = f.position + heading * float(f.speed) * delta
		f.cycle += delta
		var period: float = f.air + f.under
		if f.cycle > period:
			f.cycle -= period
			f.jumps -= 1
			f.air = rng.randf_range(1.4, 2.4)
			f.height = rng.randf_range(0.8, 1.8)
		# Planando: sobe rápido, plana rente às cristas e cai; embaixo d'água fica escondido.
		var lift := -1.2
		var climb := 0.0
		if f.cycle >= 0.0 and f.cycle < f.air:
			var s: float = f.cycle / f.air
			var arc := sin(PI * s)
			lift = float(f.height) * pow(arc, 0.6) - 0.2
			climb = float(f.height) * 0.6 * cos(PI * s) * PI / float(f.air)
		var surface: Vector3 = ocean.surface_at(pos)
		f.position = surface + surface.normalized() * lift
		f.pitch = lerpf(float(f.pitch), atan2(climb, float(f.speed)) * 2.0, 1.0 - exp(-8.0 * delta))
		var above := lift > 0.0
		if above != f.was_above:
			_splash(surface, 3, 0.5)
			# Saindo da água: cauda batendo em S (Takeoff) e depois planando de asas abertas (Glide).
			if above and i < flyfish_pool.size():
				var player := _player(flyfish_pool[i])
				if player.has_animation("Takeoff"):
					player.play("Takeoff")
					player.queue("Glide")
		f.was_above = above
		if f.jumps <= 0 or (f.position as Vector3).distance_to(ship.global_position) > 200.0:
			flying_fish.remove_at(i)

## Frente = -Z; pitch positivo levanta o focinho.
func _creature_transform(position: Vector3, heading: Vector3, pitch: float) -> Transform3D:
	var up := position.normalized()
	var forward := heading.slide(up).normalized()
	var right := forward.cross(up).normalized()
	forward = forward.rotated(right, pitch)
	return Transform3D(Basis.looking_at(forward, up), position)
