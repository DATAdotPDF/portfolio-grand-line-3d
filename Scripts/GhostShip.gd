extends Node3D

## Navio fantasma (Documentation/Plano_Clima_Eventos_Mar.md, item 4). Mora no bioma fantasma
## (WorldDecor: cemitério de navios, vulcão e lanternas no ar): só surge quando o barco está lá,
## a qualquer hora, a 90–200 m dele em mar livre do bioma, cruzando a frente do barco. Se o jogador chega a CHASE_DISTANCE, ele vira e
## PERSEGUE (mais rápido que o cruzeiro de 11 m/s: só o BURST do IMPULSO despista). Se alcança o barco,
## easter egg Red Team: o jogador vai para o "Baú do Davy Jones" (cartão com o tempo de aventura,
## a distância navegada e os dias no mar) e volta ao mar longe dali. Despistou (passou de
## ESCAPE_DISTANCE) ou amanheceu: se desfaz na névoa e volta um tempo depois.
## Modelo: Assets/Optimized/ghost_ship.glb, o original do Meshy inteiro (UVs e texturas) cortado em
## casco/mastros, velas e bandeira (Tools/ghost_ship_from_original.py) para o shader animar; o
## shader pinta a textura em verde espectral (detalhes legíveis, translúcido, brilho nas bordas).
## Nada é criado antes da primeira noite (o shader não pesa no carregamento).

const MODEL := preload("res://Assets/Optimized/ghost_ship.glb")
const GHOST := preload("res://Shaders/ghost_ship_spectral.gdshader")

@export var speed := 3.5
## Distância em que ele começa a perseguir, alcança e desiste (m).
@export var chase_distance := 90.0
@export var catch_distance := 9.0
@export var escape_distance := 120.0
## Quem aguenta isto de perseguição sem ser pego também escapa (contra o vento o impulso rende
## pouco e a distância cresce devagar).
@export var give_up_seconds := 50.0
## Velocidade na perseguição (m/s): x = mínimo (acima do cruzeiro de 11: quem só navega é
## alcançado), y = teto (abaixo do BURST de 32: o impulso, usado cedo, abre a distância de fuga;
## usado tarde, não dá e só volta em 30 s). Entre os dois segue player_ratio da velocidade do jogador.
@export var chase_speed := Vector2(13.5, 15.0)
@export var player_ratio := 1.15
## Aceleração e giro máximos (como um navio: não vira na hora).
@export var acceleration := 4.0
@export var turn_rate_degrees := 18.0
## Testes: distância em que ele some sem perseguir (0 = nunca).
@export var vanish_distance := 0.0
@export var respawn_delay := Vector2(45.0, 90.0)
## Exigir noite também dentro do bioma (false: o bioma é assombrado a qualquer hora).
@export var require_night := false
## Some quando o barco se afasta isto (m) além da borda do bioma (se não estiver perseguindo).
@export var biome_leave_margin := 250.0

var world: Node3D
var ship: Node3D
var ocean: Node
var planet_radius := 800.0
var rng := RandomNumberGenerator.new()
var model: Node3D
var materials: Array[ShaderMaterial] = []
var lantern: OmniLight3D
var active := false
var presence := 0.0
var leaving := false
var timer := 20.0
var heading := Vector3.FORWARD
var bob_time := 0.0
var chasing := false
var chase_time := 0.0
var current_speed := 0.0
## Balanço pelas ondas (igual ao barco: amostra proa, popa e bordos).
var wave_pitch := 0.0
var wave_roll := 0.0
var wave_height := 0.0
## Surgiu sozinho no bioma (os testes que o posicionam à mão não somem pela distância do bioma).
var natural := false

func _ready() -> void:
	rng.randomize()
	visible = false

func _build() -> void:
	model = MODEL.instantiate()
	# No glb a proa (gurupés) aponta para -X; o rumo do script é -Z (Basis.looking_at): gira 90°
	# para a frente do navio bater com a direção em que ele anda (antes andava de lado).
	model.rotation.y = -PI * 0.5
	add_child(model)
	# [nome da peça no glb, tipo no shader]
	for entry in [["GhostHull", 0], ["GhostSails", 1], ["GhostFlag", 2]]:
		var node := model.find_child(entry[0], true, false) as MeshInstance3D
		if node == null:
			push_warning("GhostShip: peça %s não encontrada" % entry[0])
			continue
		var original := node.get_active_material(0) as StandardMaterial3D
		var material := ShaderMaterial.new()
		material.shader = GHOST
		material.set_shader_parameter("part", entry[1])
		if original and original.albedo_texture:
			material.set_shader_parameter("albedo_map", original.albedo_texture)
		material.render_priority = 2
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		materials.append(material)
	lantern = OmniLight3D.new()
	lantern.light_color = Color(0.35, 1.0, 0.6)
	lantern.omni_range = 16.0
	lantern.shadow_enabled = false
	lantern.position = Vector3(0.0, 4.5, 5.0)
	add_child(lantern)

func _decor() -> Node:
	return world.get("world_decor")

func in_biome(margin := 0.0) -> bool:
	var decor := _decor()
	return decor != null and decor.is_in_ghost_biome(ship.global_position, margin)

## Escolhe um ponto de mar livre do bioma a 90–200 m do barco e um rumo que cruza a frente dele.
## force_near (testes): 40–70 m, e fora do bioma usa o mar aberto do clima.
func spawn(force_near := false) -> bool:
	var ship_dir: Vector3 = ship.global_position.normalized()
	var min_d := 40.0 if force_near else 90.0
	var max_d := 70.0 if force_near else 200.0
	var decor := _decor()
	var candidates := _candidates(decor.ghost_points if decor else [], ship_dir, min_d, max_d)
	if candidates.is_empty() and force_near:
		var weather: Node = world.get("weather")
		if weather:
			candidates = _candidates(weather.open_sea, ship_dir, min_d, max_d)
	if candidates.is_empty():
		return false
	if model == null:
		_build()
	var start: Vector3 = candidates[rng.randi() % candidates.size()]
	position = start * planet_radius
	var up := start
	var ahead: Vector3 = (ship.global_position + ship.heading * 60.0).normalized() * planet_radius
	heading = (ahead - position).slide(up).normalized().rotated(up, rng.randf_range(-0.6, 0.6))
	active = true
	natural = not force_near
	leaving = false
	chasing = false
	presence = 0.0
	current_speed = speed
	visible = true
	print("GHOST_SHIP spawn dist=%d bioma=%s" % [int(ship_dir.angle_to(start) * planet_radius), str(in_biome())])
	return true

func _candidates(points: Array, ship_dir: Vector3, min_d: float, max_d: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in points:
		var d: float = ship_dir.angle_to(p) * planet_radius
		if d > min_d and d < max_d:
			out.append(p)
	return out

func _process(delta: float) -> void:
	if world == null or ship == null:
		return
	var night: float = world.clock.night_at(ship.global_position)
	if not active:
		timer -= delta
		if timer <= 0.0:
			timer = 6.0
			if in_biome() and (not require_night or night > 0.65):
				spawn()
		return
	var to_player: float = global_position.distance_to(ship.global_position)
	if (require_night and night < 0.45) or (vanish_distance > 0.0 and to_player < vanish_distance):
		leaving = true
	if natural and not chasing and not in_biome(biome_leave_margin):
		leaving = true
	_chase(delta, to_player)
	presence = move_toward(presence, 0.0 if leaving else 1.0, delta / (2.0 if leaving else 5.0))
	if leaving and presence <= 0.0:
		active = false
		visible = false
		timer = rng.randf_range(respawn_delay.x, respawn_delay.y)
		print("GHOST_SHIP vanished")
		return
	# Navega como o nosso barco: acelera devagar, boia nas ondas (proa/popa/bordos) e balança.
	var up := global_position.normalized()
	heading = heading.slide(up).normalized()
	var wanted_speed := speed
	if chasing:
		wanted_speed = clampf(float(ship.measured_speed) * player_ratio, chase_speed.x, chase_speed.y)
	current_speed = move_toward(current_speed, wanted_speed, acceleration * delta)
	var next := (global_position + heading * current_speed * delta).normalized() * planet_radius
	up = next.normalized()
	var side := heading.cross(up).normalized()
	bob_time += delta
	if ocean:
		var bow: float = ocean.height_at(next + heading * 6.0)
		var stern: float = ocean.height_at(next - heading * 6.0)
		var port: float = ocean.height_at(next - side * 2.6)
		var starboard: float = ocean.height_at(next + side * 2.6)
		var k := 1.0 - exp(-3.0 * delta)
		wave_height = lerpf(wave_height, (bow + stern + port + starboard) * 0.25, k)
		wave_pitch = lerpf(wave_pitch, atan2(bow - stern, 12.0), k)
		wave_roll = lerpf(wave_roll, atan2(port - starboard, 5.2), k)
	var basis := Basis.looking_at(heading, up)
	basis = basis.rotated(basis.x, wave_pitch).rotated(heading, wave_roll)
	global_transform = Transform3D(basis, up * (planet_radius + wave_height - 0.2))
	for material in materials:
		material.set_shader_parameter("presence", presence)
	lantern.light_energy = 2.2 * presence * (0.85 + 0.15 * sin(bob_time * 9.0))

## Persegue o barco: vira para a posição prevista dele; alcança → Baú do Davy Jones.
func _chase(delta: float, to_player: float) -> void:
	if leaving or not ship.enabled:
		return
	if not chasing:
		if presence > 0.9 and to_player < chase_distance:
			chasing = true
			chase_time = 0.0
			world.hud.show_toast("O navio fantasma está atrás de você! Fuja com IMPULSO")
			print("GHOST_SHIP chase")
		return
	chase_time += delta
	var up := global_position.normalized()
	var predicted: Vector3 = ship.global_position + (ship.velocity as Vector3) * 1.5
	var wanted: Vector3 = (predicted - global_position).slide(up).normalized()
	# Giro limitado, como um navio.
	var angle := heading.signed_angle_to(wanted, up)
	var step := clampf(angle, -deg_to_rad(turn_rate_degrees) * delta, deg_to_rad(turn_rate_degrees) * delta)
	heading = heading.rotated(up, step).normalized()
	if to_player < catch_distance:
		_caught()
	elif to_player > escape_distance or chase_time > give_up_seconds:
		chasing = false
		leaving = true
		world.hud.show_toast("Você despistou o navio fantasma")
		print("GHOST_SHIP escaped")

func _caught() -> void:
	chasing = false
	leaving = true
	presence = 0.0
	print("GHOST_SHIP caught")
	var EasterEgg = preload("res://Scripts/UI/EasterEggScreen.gd")
	var days: float = world.adventure_seconds / maxf(float(world.clock.day_duration_seconds), 1.0)
	world.easter_egg.show_card(
		"Easter egg · Red Team",
		"Bem-vindo ao Baú do Davy Jones",
		[
			"O navio fantasma te alcançou e a sua aventura parou aqui.",
			"Na vida real também tem pirata do além: gente atrás de dados, senhas e acessos, a qualquer hora. É por isso que times de cibersegurança (Red Team atacando de propósito para achar as falhas antes, Blue Team defendendo) trabalham todo dia para que pessoas e empresas não tenham suas aventuras na rede interrompidas.",
		],
		[["Aventura", EasterEgg.format_duration(world.adventure_seconds)], ["Navegou", EasterEgg.format_distance(world.distance_sailed)], ["Dias no mar", "%.1f" % days]],
		"Voltar ao mar",
		_respawn_player)

## Do Baú de volta ao mar: longe do fantasma, de proa para fora.
func _respawn_player() -> void:
	var up := global_position.normalized()
	var out: Vector3 = (ship.global_position - global_position).slide(up)
	out = out.normalized() if out.length() > 0.1 else heading
	var pos: Vector3 = ocean.surface_at((ship.global_position + out * 200.0).normalized() * planet_radius)
	var new_up := pos.normalized()
	var forward := out.slide(new_up).normalized()
	ship.heading = forward
	ship.drive_speed = 0.0
	ship.global_transform = Transform3D(Basis(forward.cross(new_up).normalized(), new_up, -forward), pos)
