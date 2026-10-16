extends Node

## Física do ciclone sobre a chalupa (ideia estudada no Wind Waker, números e código nossos).
## Fases:
## 1. PUXÃO (dá para fugir): a menos de pull_radius o ciclone empurra o barco para dentro e
##    em volta, mais forte quanto mais perto, e vira a proa para a tangente. Com o turbo e a proa
##    para fora o barco escapa; o céu vai escurecendo conforme chega perto (Weather.gd).
## 2. ESPIRAL: passou do ponto sem volta (capture_radius, bem perto do eixo): o barco orbita
##    com a proa forçada ~22° para dentro e o raio fecha até a base.
## 3. SUBIDA: perto da base, o barco é levado pelo eixo (que serpenteia) girando rápido; a
##    câmera se afasta e fica fixa em relação ao ciclone (não gira junto).
## 4. TELEPORTE: no topo, clarão branco curto e o barco aparece no alto sobre outro ponto de
##    mar aberto, longe das tempestades, e desce girando devagar com um mini ciclone que some.
## Durante as fases o sloop.gd fica desligado (enabled = false) e esta classe move o barco.

enum Phase { FREE, SPIRAL, LIFT, DROP }

const CycloneScript := preload("res://Scripts/Cyclone.gd")
const WHOOSH := preload("res://Assets/Sound/SFX/Cuts/cyclone_lift.ogg")

## Começa logo fora do anel de água visível do ciclone (swirl_radius 30 m): antes era 80 m, número
## do tornado antigo, e o barco era puxado sem ver nada por perto.
@export var pull_radius := 48.0
@export var capture_radius := 12.0
@export var pull_in := 7.0
@export var pull_swirl := 6.0
@export var base_radius := 11.0
@export var tangential_speed := 9.0
@export var shrink_speed := 6.0
@export var shrink_resisting := 1.2
@export var spin_speed := deg_to_rad(540.0)
@export var drop_height := 45.0
@export var cooldown := 25.0

var weather: Node
var phase := Phase.FREE
var cyclone: Node3D
var radius := 0.0
var angle := 0.0
var lift_height := 0.0
var lift_speed := 0.0
var spin := 0.0
var cooldown_left := 0.0
var mini: Node3D
var drop_center := Vector3.UP
var flash_layer: CanvasLayer
var flash_rect: ColorRect
var flash := 0.0
var camera_offset := Vector3.ZERO

func _ready() -> void:
	flash_layer = CanvasLayer.new()
	flash_layer.layer = 6
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1, 1, 1, 0)
	flash_layer.add_child(flash_rect)
	add_child(flash_layer)

func is_riding() -> bool:
	return phase != Phase.FREE

func _ship() -> Node3D:
	return weather.ship

func _physics_process(delta: float) -> void:
	if weather == null or not is_instance_valid(_ship()):
		return
	flash = maxf(0.0, flash - delta * 1.6)
	flash_rect.color = Color(1, 1, 1, clampf(flash, 0.0, 1.0))
	match phase:
		Phase.FREE:
			cooldown_left = maxf(0.0, cooldown_left - delta)
			if cooldown_left <= 0.0 and _ship().enabled:
				_pull(delta)
			else:
				_ship().external_velocity = Vector3.ZERO
		Phase.SPIRAL:
			_spiral(delta)
		Phase.LIFT:
			_lift(delta)
		Phase.DROP:
			_drop(delta)

## Fase 1: empurrão crescente perto do ciclone; passou do ponto sem volta, vira espiral.
func _pull(delta: float) -> void:
	var ship := _ship()
	var push := Vector3.ZERO
	for candidate in weather.cyclones:
		var axis: Vector3 = candidate.axis_point(0.0)
		var up := axis.normalized()
		var flat := (ship.global_position - axis).slide(up)
		var d := flat.length()
		if d >= pull_radius or d < 0.01:
			continue
		if d < capture_radius:
			cyclone = candidate
			cyclone.captured = true
			phase = Phase.SPIRAL
			radius = d
			var frame := _frame(axis)
			angle = atan2(flat.dot(frame[2]), flat.dot(frame[0]))
			ship.enabled = false
			ship.external_velocity = Vector3.ZERO
			print("CYCLONE_RIDE capture radius=%.1f" % radius)
			return
		var out := flat / d
		var tangent := up.cross(out).normalized()
		var f := 1.0 - d / pull_radius
		push += -out * pull_in * pow(f, 1.6) + tangent * pull_swirl * f
		# A proa é puxada para a tangente (o jogador sente o leme brigando).
		var heading: Vector3 = ship.heading
		var want := tangent.rotated(up, deg_to_rad(22.5))
		var turn := heading.signed_angle_to(want, up)
		ship.heading = heading.rotated(up, clampf(turn, -1.0, 1.0) * deg_to_rad(28.0) * f * delta).normalized()
	# Entra e sai suave (antes ligava de uma vez a 80 m e soltava de uma vez: puxão irregular).
	ship.external_velocity = ship.external_velocity.lerp(push, 1.0 - exp(-2.5 * delta))

## Base local do ciclone no ponto: [tangente1, cima, tangente2].
func _frame(at: Vector3) -> Array:
	var up := at.normalized()
	var t1 := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	return [t1, up, up.cross(t1).normalized()]

func _input_axes() -> Vector2:
	var ship := _ship()
	var throttle := clampf(float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)) + ship.virtual_throttle, -1.0, 1.0)
	var steering := clampf(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)) + ship.virtual_steering, -1.0, 1.0)
	if ship.controls_override:
		throttle = ship.test_controls.x
		steering = ship.test_controls.y
	return Vector2(throttle, steering)

func _spiral(delta: float) -> void:
	var ship := _ship()
	var axis: Vector3 = cyclone.axis_point(0.0)
	var frame := _frame(axis)
	var controls := _input_axes()
	# Orbita (sentido anti-horário visto de cima) cada vez mais rápido perto do eixo.
	var omega := tangential_speed / maxf(radius, 4.0)
	angle += omega * delta
	var out: Vector3 = (frame[0] * cos(angle) + frame[2] * sin(angle)).normalized()
	var tangent: Vector3 = frame[1].cross(out).normalized()
	# A proa do jogador conta: virar para fora (A/D) e acelerar segura o barco.
	var heading: Vector3 = tangent.rotated(frame[1], deg_to_rad(22.5) + controls.y * deg_to_rad(-35.0))
	var resisting := heading.dot(out) > 0.15 and controls.x > 0.0
	radius = maxf(base_radius, radius - (shrink_resisting if resisting else shrink_speed) * delta)
	var position: Vector3 = axis + out * radius
	var surface: Vector3 = weather.ocean.surface_at(position)
	ship.heading = heading.slide(surface.normalized()).normalized()
	_place_ship(surface, ship.heading)
	ship.drive_speed = tangential_speed
	if radius <= base_radius + 0.01:
		phase = Phase.LIFT
		lift_height = 0.0
		lift_speed = 2.0
		spin = 0.0
		var camera := _camera()
		if camera:
			camera.set_process(false)
			camera_offset = camera.global_position - axis
		print("CYCLONE_RIDE lift")
		_play(WHOOSH, -3.0)

func _lift(delta: float) -> void:
	var ship := _ship()
	lift_speed = minf(lift_speed + 6.0 * delta, 15.0)
	lift_height += lift_speed * delta
	spin += spin_speed * delta
	var h := clampf(lift_height / cyclone.height, 0.0, 1.0)
	var axis_here: Vector3 = cyclone.axis_point(h)
	var frame := _frame(axis_here)
	# Sobe colado na parede de fora do funil (por dentro ficaria escondido pelas cascas).
	var orbit: float = cyclone.radius_at(h) * cyclone.grow * 1.07 + 2.5
	var out: Vector3 = (frame[0] * cos(angle + spin * 0.3) + frame[2] * sin(angle + spin * 0.3)).normalized()
	var position: Vector3 = axis_here + out * orbit
	var heading: Vector3 = frame[0].rotated(frame[1], spin)
	ship.heading = heading
	_place_ship(position, heading)
	_camera_follow(cyclone.axis_point(0.0), position, 1.6)
	if h >= 0.98:
		_teleport()

func _teleport() -> void:
	var ship := _ship()
	flash = 1.4
	cyclone.captured = false
	drop_center = _pick_destination(cyclone.center)
	var up := drop_center
	var frame := _frame(up * weather.planet_radius)
	var position: Vector3 = up * (weather.planet_radius + drop_height)
	_place_ship(position, frame[0])
	# Mini ciclone que desce junto e some ao tocar o mar.
	mini = CycloneScript.new()
	mini.name = "MiniCyclone"
	mini.weather = weather
	mini.planet_radius = weather.planet_radius
	mini.height = drop_height + 6.0
	mini.radius_scale = 0.14
	mini.swirl_radius = 7.0
	mini.setup(up, 991)
	weather.add_child(mini)
	mini.grow = 1.0
	lift_height = drop_height
	var camera := _camera()
	if camera:
		camera.global_position = position + frame[2] * 22.0 + up * 6.0
		camera_offset = camera.global_position - up * weather.planet_radius
	phase = Phase.DROP
	_play(WHOOSH, -6.0)
	print("CYCLONE_RIDE teleport to %.0f m away" % (cyclone.center.angle_to(drop_center) * weather.planet_radius))

func _drop(delta: float) -> void:
	var ship := _ship()
	lift_height = maxf(0.0, lift_height - 9.0 * delta)
	spin += spin_speed * 0.25 * delta
	var up := drop_center
	var frame := _frame(up * weather.planet_radius)
	var heading: Vector3 = frame[0].rotated(frame[1], spin)
	var sea: Vector3 = weather.ocean.surface_at(up * weather.planet_radius)
	var position: Vector3 = sea + up * lift_height
	ship.heading = heading
	_place_ship(position, heading)
	_camera_follow(up * weather.planet_radius, position, 0.9)
	if is_instance_valid(mini):
		mini.grow = clampf(lift_height / drop_height, 0.0, 1.0) * 0.9 + 0.1
	if lift_height <= 0.0:
		if is_instance_valid(mini):
			mini.queue_free()
		ship.drive_speed = 0.0
		ship.enabled = true
		ship.reset_physics_interpolation()
		var camera := _camera()
		if camera:
			camera.set_process(true)
			camera.snap_to_boat()
		phase = Phase.FREE
		cooldown_left = cooldown
		cyclone = null
		print("CYCLONE_RIDE landed")

## Ponto de mar aberto longe do ciclone (>400 m) e das tempestades (>180 m).
func _play(stream: AudioStream, volume: float) -> void:
	var sound := AudioStreamPlayer.new()
	sound.stream = stream
	sound.volume_db = volume
	add_child(sound)
	sound.play()
	sound.finished.connect(sound.queue_free)

func _pick_destination(from: Vector3) -> Vector3:
	var options: Array = weather.open_sea
	var best: Vector3 = options[0]
	var best_score := -INF
	for attempt in 80:
		var p: Vector3 = options[randi() % options.size()]
		var far: float = from.angle_to(p) * weather.planet_radius
		if far < 400.0:
			continue
		var clear := INF
		for storm in weather.storms:
			clear = minf(clear, p.angle_to(storm.center) * weather.planet_radius)
		if clear > 180.0:
			return p
		if clear > best_score:
			best_score = clear
			best = p
	return best

func _place_ship(position: Vector3, heading: Vector3) -> void:
	var ship := _ship()
	var up := position.normalized()
	var forward := heading.slide(up).normalized()
	ship.global_transform = Transform3D(Basis(forward.cross(up).normalized(), up, -forward), position)

func _camera() -> Camera3D:
	return weather.world.camera if weather.world and "camera" in weather.world else null

## Câmera presa ao ciclone (não gira com o barco): afastada e olhando para o barco.
func _camera_follow(anchor: Vector3, target: Vector3, rise: float) -> void:
	var camera := _camera()
	if camera == null:
		return
	var up := anchor.normalized()
	var flat := camera_offset.slide(up)
	if flat.length() < 1.0:
		flat = _frame(anchor)[2]
	var wanted := anchor + flat.normalized() * 36.0 + up * ((target - anchor).dot(up) * rise * 0.6 + 8.0)
	camera.global_position = camera.global_position.lerp(wanted, 0.08)
	camera.look_at(target, up)
