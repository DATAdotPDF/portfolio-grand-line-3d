extends Node3D

## Gaivotas individuais (modelo de comportamento estudado no Wind Waker, código nosso):
## - cada gaivota tem um "ponto de casa" FIXO no mundo (não segue o barco nem a proa dele);
## - a cada 2–7 s sorteia um alvo a até ~10 m da casa (e 0–5 m acima da altura dela);
## - vira até o alvo com giro limitado, e o giro "acorda" devagar depois de trocar de alvo
##   (curvas largas); inclina as asas proporcional à curva;
## - abaixo do alvo sobe batendo asa devagar (6 m/s); acima, plana mais rápido (11 m/s);
## - de vez em quando grita; quando o barco se afasta, a casa dela some e ela vai embora subindo.
## Aparecem 1 a 3 por vez, sozinhas, mais vezes perto das ilhas. Só de dia.
## Um único MultiMesh; batida/planada e fase vão na cor da instância (custom data chegava
## corrompido no Compatibility).

## Gaivota do Meshy riggada/animada no Blender (Tools/rig_creatures_blender.py): frente = -Z,
## 2,6 m de envergadura, clipe Fly_Flap (3 batidas suaves com a ponta dobrando + 20 quadros planando).
const GULL_SCENE := preload("res://Assets/Optimized/Creatures/gull.glb")
const GULL_CALL := preload("res://Assets/Sound/SFX/SEAGULLS OPEN SEA SFX 1.mp3")
const MAX_GULLS := 16
## Com 2,6 m de envergadura (tamanho real) elas viravam pontinhos na câmera do jogo: 1,5× (estilizado).
const GULL_SCALE := 1.5

@export var first_spawn_delay := 6.0
@export var min_interval := 14.0
@export var max_interval := 32.0
@export var wingspan := 2.6

var world: Node3D
var ship: Node3D
var planet_radius := 800.0
var gulls: Array[Dictionary] = []
var timer := 0.0
var rng := RandomNumberGenerator.new()
## Cada gaivota usa um nó fixo do conjunto (a animação não pula quando outra vai embora).
var free_birds: Array[Node3D] = []
var call_player: AudioStreamPlayer3D

func _ready() -> void:
	rng.randomize()
	timer = first_spawn_delay
	for i in MAX_GULLS:
		var bird := GULL_SCENE.instantiate() as Node3D
		bird.name = "Gull%d" % i
		bird.top_level = true
		bird.visible = false
		bird.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		for mesh in bird.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var player := _player(bird)
		player.get_animation("Fly_Flap").loop_mode = Animation.LOOP_LINEAR
		add_child(bird)
		free_birds.append(bird)
	call_player = AudioStreamPlayer3D.new()
	call_player.stream = GULL_CALL
	call_player.volume_db = -14.0
	call_player.unit_size = 18.0
	add_child(call_player)

func _process(delta: float) -> void:
	if not is_instance_valid(ship) or world == null:
		return
	# Só depois de zarpar (na abertura o barco está parado atrás do cartão).
	if "enabled" in ship and not ship.enabled:
		return
	timer -= delta
	if timer <= 0.0:
		var near_island := _nearest_island_distance(ship.global_position) < 260.0
		timer = rng.randf_range(min_interval, max_interval) * (0.5 if near_island else 1.0)
		var daylight: float = world.sun.light_energy / 1.15 if world.sun else 1.0
		if daylight > 0.35 and gulls.size() < MAX_GULLS - 3:
			spawn_gulls(rng.randi_range(1, 3))
	for i in range(gulls.size() - 1, -1, -1):
		if not _update_gull(gulls[i], delta):
			var gone: Node3D = gulls[i].bird
			gone.visible = false
			free_birds.append(gone)
			gulls.remove_at(i)
	for g in gulls:
		var bird: Node3D = g.bird
		bird.global_transform = Transform3D((g.basis as Basis).scaled(Vector3.ONE * GULL_SCALE), g.position)
		# O clipe já alterna batidas e planeio; subindo ou indo embora ele roda mais rápido.
		_player(bird).speed_scale = lerpf(0.8, 1.25, float(g.flap))

func _player(node: Node) -> AnimationPlayer:
	return node.find_child("AnimationPlayer", true, false) as AnimationPlayer

func _nearest_island_distance(point: Vector3) -> float:
	var best := INF
	if "islands" in world:
		for island in world.islands:
			best = minf(best, point.distance_to(island.global_position))
	return best

## Novas gaivotas soltas: a casa delas fica fixa no mundo, à frente da câmera (onde dá pra ver),
## e cada uma chega voando de longe até a casa.
func spawn_gulls(count: int) -> void:
	var up := ship.global_position.normalized()
	var camera := get_viewport().get_camera_3d()
	var look := (-camera.global_basis.z if camera else -ship.global_basis.z).slide(up).normalized()
	var right := look.cross(up).normalized()
	var home := ship.global_position + look * rng.randf_range(25.0, 50.0) + right * rng.randf_range(-20.0, 20.0)
	var home_altitude := rng.randf_range(6.0, 9.0)
	for n in count:
		# Cada uma com casa própria (perto das outras, mas sem formação).
		var own_home := home + right * rng.randf_range(-12.0, 12.0) + look * rng.randf_range(-10.0, 10.0)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var start := own_home + right * side * rng.randf_range(60.0, 90.0) + look * rng.randf_range(-30.0, 30.0)
		var start_up := start.normalized()
		var g := {
			"home": own_home.normalized() * planet_radius,
			"home_altitude": home_altitude + rng.randf_range(-1.0, 1.5),
			"position": start_up * (planet_radius + home_altitude + rng.randf_range(3.0, 8.0)),
			"heading": (own_home - start).slide(start_up).normalized(),
			"speed": 9.0, "target_speed": 9.0, "accel": 2.0,
			"turn_rate": deg_to_rad(60.0), "turn_wake": 1.0,
			"pitch": 0.0, "bank": 0.0, "flap": 1.0, "phase": rng.randf(),
			"retarget": 0.0, "target": own_home, "age": 0.0,
			"leaving": false, "called": false,
		}
		g.basis = Basis.looking_at(g.heading, start_up)
		if free_birds.is_empty():
			return
		g.bird = free_birds.pop_back()
		(g.bird as Node3D).visible = true
		var player := _player(g.bird)
		player.play("Fly_Flap")
		player.seek(rng.randf() * player.current_animation_length, true)
		gulls.append(g)

func _pick_target(g: Dictionary) -> void:
	var home: Vector3 = g.home
	var up := home.normalized()
	var t1 := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var t2 := up.cross(t1).normalized()
	var offset := t1 * rng.randf_range(-10.0, 10.0) + t2 * rng.randf_range(-10.0, 10.0)
	g.target = (home + offset).normalized() * (planet_radius + g.home_altitude + rng.randf_range(0.0, 5.0))
	g.retarget = rng.randf_range(1.7, 6.7)
	g.turn_rate = deg_to_rad(rng.randf_range(35.0, 80.0))
	g.turn_wake = 0.0
	# Abaixo do alvo: sobe batendo asa devagar. Acima: plana e ganha velocidade.
	if (g.position as Vector3).length() < (g.target as Vector3).length():
		g.target_speed = 6.0
		g.accel = 1.8
	else:
		g.target_speed = 10.8
		g.accel = 4.5

func _update_gull(g: Dictionary, delta: float) -> bool:
	g.age += delta
	var pos: Vector3 = g.position
	var up := pos.normalized()
	# O barco foi embora: a casa some e ela segue reto, subindo, até sumir.
	if not g.leaving and ship.global_position.distance_to(g.home) > 140.0:
		g.leaving = true
		g.target = (pos + (g.heading as Vector3) * 400.0).normalized() * (planet_radius + 40.0)
		g.target_speed = 10.8
		g.retarget = 999.0
	g.retarget -= delta
	if g.retarget <= 0.0 and not g.leaving:
		_pick_target(g)
	var to_target: Vector3 = g.target - pos
	var flat := to_target.slide(up)
	var heading: Vector3 = (g.heading as Vector3).slide(up).normalized()
	# Giro limitado que "acorda" em ~1 s depois de trocar de alvo (curvas largas, não em quina).
	g.turn_wake = minf(1.0, g.turn_wake + delta * 1.2)
	var yaw_change := 0.0
	if flat.length() > 0.5:
		var want := flat.normalized()
		var angle := heading.signed_angle_to(want, up)
		yaw_change = clampf(angle, -g.turn_rate * g.turn_wake * delta, g.turn_rate * g.turn_wake * delta)
		heading = heading.rotated(up, yaw_change).normalized()
	g.heading = heading
	# Inclina na curva (até 30°) e aponta o bico para o alvo na vertical.
	var bank_target := clampf(-yaw_change / maxf(delta, 0.0001) * 0.55, -0.52, 0.52)
	g.bank = lerpf(g.bank, bank_target, 1.0 - exp(-4.0 * delta))
	var climb := atan2(to_target.dot(up), maxf(flat.length(), 0.1))
	g.pitch = lerpf(g.pitch, clampf(climb, -0.5, 0.5), 1.0 - exp(-3.0 * delta))
	g.speed = move_toward(g.speed, g.target_speed, g.accel * delta)
	var forward := heading.rotated(heading.cross(up).normalized(), g.pitch)
	pos += forward * g.speed * delta
	g.position = pos
	g.flap = lerpf(g.flap, 1.0 if to_target.dot(up) > 0.5 or g.leaving else 0.0, 1.0 - exp(-3.0 * delta))
	g.basis = Basis.looking_at(forward, up).rotated(forward, g.bank)
	var distance := ship.global_position.distance_to(pos)
	if not g.called and distance < 35.0 and rng.randf() < 0.4 * delta:
		g.called = true
		call_player.global_position = pos
		call_player.pitch_scale = rng.randf_range(0.95, 1.1)
		call_player.play()
	return distance < 300.0 or g.age < 4.0
