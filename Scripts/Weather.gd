extends Node3D

## Clima do mar: tempestades locais (StormCell) e ciclones (Cyclone) que andam devagar pelos
## espaços vazios do mapa, longe das ilhas e das rotas entre ilhas seguidas.
## Tudo é comandado por um único "badness" (0 calmo .. 4 tormenta), por tempestade:
## - mar: ondas mais altas e espuma nas cristas que se fecham (oceano recebe o badness);
## - vento: mais forte dentro da tempestade (WindManager pergunta o badness do ponto);
## - céu/luz/névoa (world.storm_gloom), chuva pessoal, véu e clarão dos raios;
## - spray nas cristas perto do barco (SeaSpray).
## Chuva pessoal: técnica do "Easy Particle Rain in Godot 4" (CC0).

const StormCellScript := preload("res://Scripts/StormCell.gd")
const CycloneScript := preload("res://Scripts/Cyclone.gd")
const SeaSprayScript := preload("res://Scripts/SeaSpray.gd")
const CycloneRideScript := preload("res://Scripts/CycloneRide.gd")
const ThunderScript := preload("res://Scripts/Thunder.gd")
const GUST_SOUND := preload("res://Assets/Sound/SFX/Cuts/storm_gust.ogg")
const DROPS := preload("res://Shaders/rain_drops.gdshader")
const VEIL := preload("res://Shaders/rain_screen.gdshader")

@export var storm_count := 3
@export var cyclone_count := 2
## Velocidade de deriva pelo mar aberto (m/s).
@export var storm_speed := 3.2
@export var cyclone_speed := 2.6
## Raio do mar agitado em volta do ciclone (m).
const CYCLONE_SEA_RADIUS := 90.0

var world: Node3D
var ship: Node3D
var ocean: Node
var planet_radius := 800.0
var storms: Array[Node3D] = []
var cyclones: Array[Node3D] = []
## Eventos temporários no mar (kraken): {"center": Vector3 no mundo, "radius": m, "badness": 0..4}.
## Entram nas ondas e na escuridão do céu como uma tempestade sem nuvem.
var sea_events: Array[Dictionary] = []
## Destino atual de cada tempestade/ciclone (direção na esfera), na mesma ordem de movers.
var movers: Array[Node3D] = []
var targets: Array[Vector3] = []
var open_sea: Array[Vector3] = []
var island_dirs: Array[Vector3] = []
var routes: Array = []
var personal_rain: GPUParticles3D
var personal_material: ShaderMaterial
var overlay: CanvasLayer
var overlay_material: ShaderMaterial
var spray: Node3D
var ride: Node
var thunder: MeshInstance3D
var gloom := 0.0
## Badness no barco (0..4).
var badness := 0.0
var rng := RandomNumberGenerator.new()
var move_time := 0.0
## Desafio dentro da tempestade: séries de ondas maiores e rajadas que empurram o barco.
var challenge_timer := 8.0
var gust_vector := Vector3.ZERO
var gust_time := 0.0

func _ready() -> void:
	rng.seed = 7331
	_map_open_sea()
	var homes := pick_homes(storm_count + cyclone_count)
	# Casas espalhadas pelo mar aberto; as últimas ficam para os ciclones (sozinhos, sem nuvem).
	for i in range(storm_count, homes.size()):
		var cyclone := CycloneScript.new()
		cyclone.name = "Cyclone%d" % (i - storm_count)
		cyclone.weather = self
		cyclone.planet_radius = planet_radius
		cyclone.setup(homes[i], 211 + i * 53)
		add_child(cyclone)
		cyclones.append(cyclone)
	for i in mini(storm_count, homes.size()):
		var storm := StormCellScript.new()
		storm.name = "Storm%d" % i
		storm.weather = self
		storm.planet_radius = planet_radius
		storm.setup(homes[i], 101 + i * 37)
		# Uma de cada forma (bigorna, torre inclinada, prateleira com braços).
		storm.shape = ["anvil", "tower", "shelf"][i % 3]
		add_child(storm)
		storms.append(storm)
	for mover in storms + cyclones:
		movers.append(mover)
		targets.append(mover.center)
	for i in movers.size():
		targets[i] = _next_target(i)
	_build_personal_rain()
	_build_overlay()
	thunder = ThunderScript.new()
	thunder.name = "Thunder"
	thunder.weather = self
	add_child(thunder)
	ride = CycloneRideScript.new()
	ride.name = "CycloneRide"
	ride.weather = self
	add_child(ride)
	spray = SeaSprayScript.new()
	spray.name = "SeaSpray"
	spray.weather = self
	add_child(spray)
	var wind_manager := get_node_or_null("/root/WindManager")
	if wind_manager:
		wind_manager.badness_at = badness_at
	print("WEATHER storms=%d cyclones=%d open_sea=%d" % [storms.size(), cyclones.size(), open_sea.size()])

## Badness (0..4) no ponto: a tempestade mais forte que cobre o ponto.
func badness_at(point: Vector3) -> float:
	return ocean.badness_at(point) if ocean else 0.0

# --- Mar aberto -----------------------------------------------------------------

## Amostra a esfera e guarda os pontos onde tempestade pode ficar: entre 230 e 650 m da ilha
## mais próxima (dentro da área navegável) e a 90 m ou mais das rotas entre ilhas seguidas.
func _map_open_sea() -> void:
	for island in world.islands:
		island_dirs.append(island.global_position.normalized())
	for i in island_dirs.size() - 1:
		routes.append([island_dirs[i], island_dirs[i + 1]])
	var samples := 3000
	for i in samples:
		# Esfera de Fibonacci: amostras uniformes e determinísticas.
		var y := 1.0 - 2.0 * (i + 0.5) / samples
		var r := sqrt(1.0 - y * y)
		var phi := i * PI * (3.0 - sqrt(5.0))
		var p := Vector3(cos(phi) * r, y, sin(phi) * r)
		if _is_open(p):
			open_sea.append(p)

func _island_distance(p: Vector3) -> float:
	var d := INF
	for c in island_dirs:
		d = minf(d, p.angle_to(c) * planet_radius)
	return d

func _route_distance(p: Vector3) -> float:
	var d := INF
	for route in routes:
		d = minf(d, _arc_distance(p, route[0], route[1]))
	return d

func _is_open(p: Vector3) -> bool:
	var d_island := _island_distance(p)
	return d_island >= 230.0 and d_island <= 650.0 and _route_distance(p) >= 90.0 and _decor_clear(p)

## Longe das ilhas/rochas do mapa (WorldDecor; a tartaruga anda): um ciclone escondido atrás de
## uma rocha puxava o barco "do nada".
func _decor_clear(p: Vector3) -> bool:
	var decor: Node = world.get("world_decor") if world else null
	if decor == null:
		return true
	var at := p.normalized() * planet_radius
	for item in decor.items:
		var root: Node3D = item.root
		if not is_instance_valid(root):
			continue
		if root.global_position.distance_to(at) < 110.0 + float(item.height):
			return false
	return true

## Quão "vazio" é o ponto (maior = mais longe de ilhas e rotas).
func _openness(p: Vector3) -> float:
	return minf(_island_distance(p) - 120.0, _route_distance(p) * 1.4)

## Casas iniciais espalhadas: começa no ponto mais vazio e depois escolhe sempre o ponto de
## mar aberto mais longe de todas as casas já escolhidas (cobre o mapa todo, sem buracos).
func pick_homes(count: int) -> Array[Vector3]:
	var homes: Array[Vector3] = []
	var best: Vector3 = open_sea[0]
	for p in open_sea:
		if _openness(p) > _openness(best):
			best = p
	homes.append(best)
	while homes.size() < count:
		var far_point: Vector3 = open_sea[0]
		var far_score := -INF
		for p in open_sea:
			var closest := INF
			for h in homes:
				closest = minf(closest, p.angle_to(h))
			if closest > far_score:
				far_score = closest
				far_point = p
		homes.append(far_point)
	return homes

## Próximo destino do mover i: um ponto de mar aberto a 150–400 m, com o caminho inteiro em
## mar aberto e longe das outras tempestades (posição e destino delas).
func _next_target(index: int) -> Vector3:
	# Sorteia candidatos válidos e fica com o mais longe dos outros (mantém tudo espalhado).
	var best := Vector3.ZERO
	var best_score := -INF
	for rule in [[150.0, 400.0, 320.0], [60.0, 400.0, 180.0]]:
		for attempt in 40:
			var p: Vector3 = open_sea[rng.randi() % open_sea.size()]
			if not _valid_target(index, p, rule[0], rule[1], rule[2]) or not _decor_clear(p):
				continue
			var score := INF
			for j in movers.size():
				if j != index:
					score = minf(score, minf(p.angle_to(movers[j].center), p.angle_to(targets[j])))
			if score > best_score:
				best_score = score
				best = p
		if best_score > -INF:
			return best
	return movers[index].center

func _valid_target(index: int, p: Vector3, min_dist: float, max_dist: float, spacing: float) -> bool:
	var from: Vector3 = movers[index].center
	var dist := from.angle_to(p) * planet_radius
	if dist < min_dist or dist > max_dist:
		return false
	for j in movers.size():
		if j == index:
			continue
		if p.angle_to(movers[j].center) * planet_radius < spacing or p.angle_to(targets[j]) * planet_radius < spacing:
			return false
	# Caminho inteiro em mar aberto (amostra a cada ~25 m).
	var steps := maxi(4, int(dist / 25.0))
	for step in range(1, steps):
		if not _is_open(from.slerp(p, float(step) / steps)):
			return false
	return true

## Distância (m, sobre a esfera) do ponto p ao arco de grande círculo entre a e b.
func _arc_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var n := a.cross(b)
	if n.length_squared() < 1e-8:
		return p.angle_to(a) * planet_radius
	n = n.normalized()
	var projected := (p - n * p.dot(n)).normalized()
	if absf(a.angle_to(projected) + projected.angle_to(b) - a.angle_to(b)) < 1e-3:
		return asin(clampf(absf(p.dot(n)), 0.0, 1.0)) * planet_radius
	return minf(p.angle_to(a), p.angle_to(b)) * planet_radius

func _move(delta: float) -> void:
	move_time += delta
	for i in movers.size():
		var mover := movers[i]
		if mover.get("captured"):
			continue
		var is_cyclone: bool = mover in cyclones
		var speed := cyclone_speed if is_cyclone else storm_speed
		# Ritmo que varia (acelera e desacelera) e trajetória sinuosa: não anda em linha reta.
		speed *= 0.7 + 0.5 * (0.5 + 0.5 * sin(move_time * 0.11 + i * 1.9))
		var from: Vector3 = mover.center
		var angle := from.angle_to(targets[i])
		if angle * planet_radius < 8.0:
			targets[i] = _next_target(i)
			continue
		var to_target := (targets[i] - from).slide(from).normalized()
		var weave := sin(move_time * (0.23 if is_cyclone else 0.13) + i * 2.7) * (0.9 if is_cyclone else 0.6)
		var heading := to_target.rotated(from, weave)
		var step := speed * delta / planet_radius
		var next := from.rotated(from.cross(heading).normalized(), step).normalized()
		# Não sai do mar aberto por causa da curva: se sairia, segue reto para o destino.
		if not _is_open(next):
			next = from.rotated(from.cross(to_target).normalized(), step).normalized()
			if not _is_open(next) and is_cyclone:
				# Bloqueado (rocha/ilha do mapa no caminho): troca de destino e espera um passo.
				targets[i] = _next_target(i)
				continue
		mover.center = next

## Dentro de tempestade (não ciclone): a cada 6–14 s sorteia um evento.
## - série de ondas: o badness da tempestade sobe +1,5 e volta em ~12 s (ondas, espuma, chuva);
## - rajada: empurrão lateral de 2–4 m/s por 3–5 s, numa direção sorteada perto do vento.
func _storm_challenge(delta: float) -> void:
	var inside: Node3D = null
	for storm in storms:
		if ship.global_position.distance_to(storm.center * planet_radius) < storm.radius * 1.1:
			inside = storm
	gust_time = maxf(0.0, gust_time - delta)
	var target := gust_vector if gust_time > 0.0 else Vector3.ZERO
	ship.storm_push = ship.storm_push.lerp(target, 1.0 - exp(-1.5 * delta))
	if inside == null or inside.badness < 2.0:
		challenge_timer = minf(challenge_timer, 6.0)
		return
	challenge_timer -= delta
	if challenge_timer > 0.0:
		return
	challenge_timer = rng.randf_range(6.0, 14.0)
	if rng.randf() < 0.5:
		inside.surge = 1.5
		print("STORM_EVENT surge")
	else:
		var up: Vector3 = ship.global_position.normalized()
		var wind: Vector3 = world.wind_at(ship.global_position) if world.has_method("wind_at") else up.cross(Vector3.RIGHT)
		var dir := wind.slide(up).normalized().rotated(up, rng.randf_range(-1.2, 1.2))
		gust_vector = dir * rng.randf_range(2.0, 4.0)
		gust_time = rng.randf_range(3.0, 5.0)
		print("STORM_EVENT gust %.1f m/s" % gust_vector.length())
		var sound := AudioStreamPlayer.new()
		sound.stream = GUST_SOUND
		sound.volume_db = -4.0
		sound.pitch_scale = rng.randf_range(0.9, 1.1)
		add_child(sound)
		sound.play()
		sound.finished.connect(sound.queue_free)

# --- Chuva pessoal e véu ----------------------------------------------------------

func _build_personal_rain() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 18.0
	process.emission_ring_inner_radius = 0.0
	process.emission_ring_height = 4.0
	process.direction = Vector3.DOWN
	process.spread = 3.0
	process.initial_velocity_min = 24.0
	process.initial_velocity_max = 28.0
	process.gravity = Vector3.ZERO
	process.scale_min = 0.7
	process.scale_max = 1.3
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.1, 0.9, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	personal_material = ShaderMaterial.new()
	personal_material.shader = DROPS
	personal_material.set_shader_parameter("streaks", 3)
	personal_material.set_shader_parameter("streak_width", 0.06)
	personal_material.set_shader_parameter("streak_length", 0.45)
	personal_material.set_shader_parameter("opacity", 0.4)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 1.8)
	quad.material = personal_material
	personal_rain = GPUParticles3D.new()
	personal_rain.name = "PersonalRain"
	personal_rain.process_material = process
	personal_rain.draw_pass_1 = quad
	personal_rain.amount = 2200
	personal_rain.lifetime = 1.3
	personal_rain.local_coords = false
	personal_rain.emitting = false
	personal_rain.visibility_aabb = AABB(Vector3(-25, -40, -25), Vector3(50, 50, 50))
	personal_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(personal_rain)

func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 5  # acima do 3D, abaixo do HUD (10)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_material = ShaderMaterial.new()
	overlay_material.shader = VEIL
	rect.material = overlay_material
	overlay.add_child(rect)
	overlay.visible = false
	add_child(overlay)

func _process(delta: float) -> void:
	if world == null or not is_instance_valid(ship):
		return
	_move(delta)
	var camera := get_viewport().get_camera_3d()
	var eye: Vector3 = camera.global_position if camera else ship.global_position
	var data: Array[Vector4] = []
	var badness_list: Array[float] = []
	var flash := 0.0
	for storm in storms:
		var c: Vector3 = storm.center * planet_radius
		data.append(Vector4(c.x, c.y, c.z, storm.radius))
		badness_list.append(storm.badness)
		var influence := 1.0 - smoothstep(storm.radius * 0.95, storm.radius * 1.45, ship.global_position.distance_to(c))
		flash = maxf(flash, storm.flash * influence)
	# Ciclone: mar agitado em volta (sem nuvem) e o céu escurecendo conforme o barco chega perto.
	for cyclone in cyclones:
		var c: Vector3 = cyclone.center * planet_radius
		data.append(Vector4(c.x, c.y, c.z, CYCLONE_SEA_RADIUS))
		badness_list.append(2.6)
	for event in sea_events:
		var c: Vector3 = event.center
		data.append(Vector4(c.x, c.y, c.z, float(event.radius)))
		badness_list.append(float(event.badness))
	ocean.set_storms(data, badness_list)
	badness = 0.0
	for storm in storms:
		var c: Vector3 = storm.center * planet_radius
		var mask := 1.0 - smoothstep(storm.radius * 0.95, storm.radius * 1.45, ship.global_position.distance_to(c))
		badness = maxf(badness, mask * storm.badness)
	for cyclone in cyclones:
		var near := 1.0 - smoothstep(25.0, 160.0, ship.global_position.distance_to(cyclone.center * planet_radius))
		badness = maxf(badness, near * 3.2)
	for event in sea_events:
		var r := float(event.radius)
		var inside := 1.0 - smoothstep(r * 0.95, r * 1.45, ship.global_position.distance_to(event.center))
		badness = maxf(badness, inside * float(event.badness))
	gloom = smoothstep(0.3, 3.2, badness)
	_storm_challenge(delta)
	world.storm_gloom = gloom
	# Clarões: o da nuvem vista de fora + os trovões de dentro (próximo acende tudo; distante, céu).
	thunder.step(delta, gloom)
	world.storm_flash = maxf(flash, thunder.near_flash * 0.8)
	world.sky_flash = maxf(world.storm_flash, thunder.sky_flash * 0.6)
	# Chuva pessoal: um disco de gotas sobre a câmera, mais denso com o badness.
	if eye.length() < planet_radius * 0.5:
		eye = ship.global_position  # câmera ainda no centro do planeta (primeiros quadros)
	var up := eye.normalized()
	var tangent := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	personal_rain.global_transform = Transform3D(Basis(tangent, up, tangent.cross(up)), eye + up * 14.0)
	# Chuva inclinada pelo vento (no Sea of Thieves os riscos vêm de lado na tormenta).
	var wind: Vector3 = world.wind_at(eye) if world.has_method("wind_at") else Vector3.ZERO
	var fall := personal_rain.global_basis.inverse() * (-up + wind * 0.35).normalized()
	(personal_rain.process_material as ParticleProcessMaterial).direction = fall
	# No mapa (câmera no espaço) a chuva pessoal e o véu ficavam colados nela: riscos sobre o globo.
	var in_space := float(world.get("space_view")) > 0.3
	personal_rain.visible = not in_space
	personal_rain.emitting = badness > 0.15 and not in_space
	personal_rain.amount_ratio = clampf(badness / 3.5, 0.0, 1.0)
	var night := 1.0 - clampf(world.sun.light_energy / 1.15, 0.0, 1.0) if world.sun else 0.0
	personal_material.set_shader_parameter("night", night)
	overlay.visible = gloom > 0.01 and not in_space
	if overlay.visible:
		overlay_material.set_shader_parameter("intensity", gloom)
		overlay_material.set_shader_parameter("flash", world.storm_flash)
