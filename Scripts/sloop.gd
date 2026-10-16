@tool
extends CharacterBody3D

const Scale = preload("res://Scripts/WorldScale.gd")
const GRAVITY := 9.8

## Respingo (posição, força 0..~2): a proa batendo numa onda ou o casco caindo de um salto.
## main_world liga isso ao spray do clima.
signal splash(position: Vector3, strength: float)

var islands: Array[Node3D] = []
var shore_blocked := false
var ocean: Node
var heading := Vector3.FORWARD
var drive_speed := 0.0
var measured_speed := 0.0
var radial_speed := 0.0
var turn_input := 0.0
var controls_override := false
var test_controls := Vector3.ZERO
var float_visual: Node3D
var last_wake := Vector3.ZERO
var enabled := true
## Empurrão de fora (o ciclone puxando para dentro e girando), somado à velocidade do barco.
var external_velocity := Vector3.ZERO
## Rajada de vento da tempestade (Weather.gd), somada à velocidade.
var storm_push := Vector3.ZERO
## Eventos (redemoinho do kraken): o vento não segura o barco (fuga com o impulso inteiro).
var ignore_wind := false
## Eventos: preso no lugar (sem avanço, o leme ainda vira) e sem surfe/salto nas cristas.
var held := false
var calm_ride := false
## Surfe: velocidade extra ganha descendo a face de uma onda (perde subindo).
var surf_speed := 0.0
## Entradas dos controles de toque (TouchControls.gd), somadas ao teclado.
var virtual_throttle := 0.0
var virtual_steering := 0.0
var virtual_boost := false
@export_group("Navegação")
@export var cruise_speed := 4.2
@export var boost_speed := 12.5
@export var reverse_speed := 2.0
@export var cruise_acceleration := 2.5
@export var boost_acceleration := 4.0
@export var yaw_speed := 0.72
## Quanto o vento global (WindManager) altera a velocidade: 0 = nada, 1 = 72%–100%.
@export_range(0.0, 1.0, 0.05) var wind_strength := 1.0
@export_group("Flutuação")
## Pontos onde o casco "sente" a água (proa/popa e bordos), em metros.
@export var hull_half_length := 2.0
@export var hull_half_beam := 0.8
## Quão rápido o casco acompanha a inclinação da onda (menor = mais peso/inércia).
@export var wave_follow_rate := 7.0
## Ajuste fino da linha d'água (m): positivo levanta o casco.
@export var draft_offset := 0.05
@export var buoyancy_spring := 46.0
@export var buoyancy_damping := 12.5
@export var max_bank_angle := deg_to_rad(15.0)
@export var bank_spring := 22.0
@export var bank_damping := 6.8
@export_group("Prévia 3D")
@export_range(-16.0, 16.0, 0.5) var preview_bank_degrees := 0.0:
	set(value):
		preview_bank_degrees = value
		_update_editor_attitude()
@export_range(-5.0, 5.0, 0.5) var preview_pitch_degrees := 0.0:
	set(value):
		preview_pitch_degrees = value
		_update_editor_attitude()
var bank_roll := 0.0
var roll_velocity := 0.0
var acceleration_pitch := 0.0
var pitch_velocity := 0.0
var current_turn_rate := 0.0
var wave_basis := Basis.IDENTITY
var turn_bias := 0.0
var idle_time := 0.0
## Flutuação com gravidade (estudo do Sea of Thieves): a água empurra o casco como mola, mas
## não puxa para baixo. Se a superfície desce mais rápido do que a gravidade, o barco decola.
var vertical_speed := 0.0
var last_target_radius := -1.0
var airborne := false
var last_bow_gap := 0.0
var slam_cooldown := 0.0
## Maior subida recente da água sob o casco (m/s), para o "embalo" na crista.
var rise_peak := 0.0
var max_bow_rate := 0.0
var last_surface_speed := 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_attitude()
		set_physics_process(false)
		return
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	safe_margin = 0.03
	collision_layer = 2
	collision_mask = 1 | 8
	last_wake = global_position

func _update_editor_attitude() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var visual := get_node_or_null("HullVisualContainer") as Node3D
	if visual != null:
		visual.rotation = Vector3(deg_to_rad(preview_pitch_degrees), 0.0, deg_to_rad(preview_bank_degrees))

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not enabled:
		return
	var throttle := clampf(float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)) + virtual_throttle, -1.0, 1.0)
	var steering := clampf(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)) + virtual_steering, -1.0, 1.0)
	var boost := Input.is_physical_key_pressed(KEY_SHIFT) or virtual_boost
	if controls_override:
		throttle = test_controls.x
		steering = test_controls.y
		boost = test_controls.z > 0.5
	var up := global_position.normalized()
	var old_up := up
	heading = heading.slide(up).normalized()
	turn_input = lerpf(turn_input,steering,1.0-exp(-4.5*delta))
	current_turn_rate = -turn_input*yaw_speed
	heading = heading.rotated(up, current_turn_rate * delta).normalized()
	var previous_speed := drive_speed
	var target_speed := 0.0 if held else throttle * (boost_speed if boost else cruise_speed)
	if throttle > 0.0 and not ignore_wind:
		var wind_tangent := _wind_at(global_position)
		if wind_tangent.length_squared() > 0.0001:
			var wind_alignment := heading.dot(wind_tangent.normalized())
			var local_strength := clampf(wind_tangent.length(), 0.0, 1.0)
			var sail_factor := lerpf(1.0, 0.72 + 0.28 * wind_alignment, wind_strength * local_strength)
			target_speed *= sail_factor
	if throttle < 0.0:
		target_speed = -reverse_speed
	if held:
		# Preso (kraken): para em ~1 s, sem embalo de surfe.
		drive_speed = move_toward(drive_speed, 0.0, 5.0 * delta)
		surf_speed = move_toward(surf_speed, 0.0, 5.0 * delta)
	elif is_zero_approx(throttle):
		drive_speed *= exp(-0.7 * delta)
	else:
		drive_speed = move_toward(drive_speed, target_speed, (boost_acceleration if boost else cruise_acceleration) * delta)
	var right := heading.cross(up).normalized()
	var front: Vector3 = ocean.surface_at(global_position + heading * hull_half_length)
	var rear: Vector3 = ocean.surface_at(global_position - heading * hull_half_length)
	var port: Vector3 = ocean.surface_at(global_position - right * hull_half_beam)
	var starboard: Vector3 = ocean.surface_at(global_position + right * hull_half_beam)
	var before := global_position
	up_direction = up
	# Movimento só na horizontal; a altura vem direto da superfície (como as boias).
	# Surfe: a gravidade puxa o casco morro abaixo pela inclinação da onda sob ele (proa mais
	# baixa que a popa = descendo a face). Só com o casco na água e andando para a frente.
	var slope := (rear.length() - front.length()) / (2.0 * hull_half_length)
	if not airborne and drive_speed > 1.0 and not calm_ride:
		surf_speed += GRAVITY * slope * 0.9 * delta
	surf_speed *= exp(-0.7 * delta)
	surf_speed = clampf(surf_speed, -3.0, 7.0)
	velocity = heading * (drive_speed + surf_speed) + external_velocity.slide(up) + storm_push.slide(up)
	shore_blocked = false
	move_and_slide()
	var moved_up := global_position.normalized()
	var center: Vector3 = ocean.surface_at(global_position)
	# A altura segue o ponto mais alto entre o centro e a média do casco: nas cristas
	# a média dos pontos baixava o barco ('afundava'). draft_offset ajusta a linha d'água.
	var hull_mean: float = (front.length() + rear.length() + port.length() + starboard.length()) * 0.25
	var target_radius: float = maxf(center.length(), hull_mean) + draft_offset
	var current := global_position.length()
	# Primeiro quadro ou teleporte de verdade (ciclone, testes): recomeça a flutuação parada.
	if last_target_radius < 0.0 or absf(target_radius - current) > 15.0:
		last_target_radius = target_radius
		vertical_speed = 0.0
		current = target_radius
	# Na tempestade a leitura da água sob o casco pode pular de um quadro para o outro (onda curta
	# muito íngreme): limita a 18 m/s para o barco não dar "tranco"/voltar de repente.
	# Nunca desce mais que 9 m abaixo do nível do mar (miolo do redemoinho do kraken).
	target_radius = maxf(target_radius, float(ocean.radius) - 9.0)
	target_radius = last_target_radius + clampf(target_radius - last_target_radius, -18.0 * delta, 18.0 * delta)
	var surface_speed := (target_radius - last_target_radius) / maxf(delta, 0.00001)
	last_target_radius = target_radius
	last_surface_speed = surface_speed
	# Mola só empurra (k·profundidade + g ≥ 0); gravidade sempre. O amortecimento da água cai
	# junto com o quanto o casco está dentro dela: na crista, quando a água "foge" por baixo,
	# o barco segue subindo com a velocidade que tinha e faz um salto curto (v²/2g).
	var depth := target_radius - current
	var buoyancy := buoyancy_spring * depth + GRAVITY
	var in_water := buoyancy > 0.0
	var accel := -GRAVITY
	if in_water:
		var wet := clampf(buoyancy / GRAVITY, 0.0, 1.0)
		accel += buoyancy - buoyancy_damping * wet * wet * (vertical_speed - surface_speed)
	vertical_speed += accel * delta
	var radius := current + vertical_speed * delta
	# Nunca afunda além de 1 m (o casco não mergulha de verdade).
	if radius < target_radius - 1.0:
		radius = target_radius - 1.0
		vertical_speed = maxf(vertical_speed, surface_speed)
	if airborne and in_water:
		var impact := surface_speed - vertical_speed
		if impact > 2.5:
			# Queda de um salto: respingo dos dois lados e a proa "afunda" um instante.
			splash.emit(moved_up * target_radius + heading * hull_half_length * 0.5, clampf(impact / 4.0, 0.6, 2.0))
			pitch_velocity -= clampf(impact * 0.15, 0.0, 0.8)
			drive_speed *= 0.92
	# Embalo na crista (o que faz o barco do Sea of Thieves pular): subindo a face de uma onda
	# rápido e com velocidade, quando a água para de subir o casco segue com parte daquela
	# velocidade vertical e sai da água. Em mar calmo a subida é lenta e o salto some.
	rise_peak = maxf(rise_peak * exp(-0.5 * delta), clampf(surface_speed, 0.0, 6.0))
	var badness: float = ocean.badness_at(global_position) if ocean.has_method("badness_at") else 0.0
	if in_water and not airborne and not calm_ride and rise_peak > 1.2 and measured_speed > 5.0 and surface_speed < rise_peak * 0.35:
		# Ganho cresce com o badness: no calmo não chega ao mínimo (sem salto), na tormenta ~0,5–1 m.
		var launch := clampf(rise_peak * (0.35 + 0.25 * badness), 0.0, 4.5)
		if launch > 1.8:
			vertical_speed = maxf(vertical_speed, launch)
			radius = maxf(radius, target_radius + 0.05)
			in_water = false
			pitch_velocity += 0.35
		rise_peak = 0.0
	airborne = not in_water
	radial_speed = vertical_speed
	global_position = moved_up * radius
	up = global_position.normalized()
	heading = (Quaternion(old_up, up) * heading).slide(up).normalized()
	basis = Basis(heading.cross(up).normalized(), up, -heading)
	measured_speed = (global_position - before).slide(up).length() / maxf(delta, 0.00001)
	var acceleration := (drive_speed-previous_speed)/maxf(delta,0.00001)
	if get_slide_collision_count() > 0 or shore_blocked:
		drive_speed = velocity.slide(up).dot(heading)
	if float_visual:
		var wave_up := (starboard - port).cross(front - rear).normalized()
		if wave_up.dot(up) < 0.0:
			wave_up = -wave_up
		var visual_forward := heading.slide(wave_up).normalized()
		var desired_global := Basis(visual_forward.cross(wave_up), wave_up, -visual_forward).orthonormalized()
		var desired_local := basis.inverse() * desired_global
		# No ar o casco não acompanha a onda (segue a inércia, ajeita devagar).
		var follow := wave_follow_rate * (0.25 if airborne else 1.0)
		wave_basis = wave_basis.slerp(desired_local, 1.0 - exp(-follow * delta)).orthonormalized()
		update_attitude(delta,acceleration)
		float_visual.basis = wave_basis * Basis.from_euler(Vector3(acceleration_pitch,0,bank_roll))
	# Proa batendo: a água sobe na proa mais rápido que o barco (crista chegando) com velocidade.
	slam_cooldown = maxf(0.0, slam_cooldown - delta)
	var bow_point := global_position + heading * hull_half_length
	var bow_gap: float = front.length() - bow_point.length()
	var bow_rate := (bow_gap - last_bow_gap) / maxf(delta, 0.00001)
	last_bow_gap = bow_gap
	max_bow_rate = maxf(max_bow_rate, bow_rate)
	# Batida: a água sobe contra o casco bem mais rápido que ele (face da próxima onda).
	var closing := last_surface_speed - vertical_speed
	if slam_cooldown <= 0.0 and measured_speed > 5.0 and not airborne and closing > 1.4:
		slam_cooldown = 0.8
		splash.emit(front, clampf(closing / 2.0 * measured_speed / 9.0, 0.5, 2.0))
	# Esteira nasce nas madeiras laterais, atrás do meio do barco.
	ocean.wake_head = global_position - heading * 1.6
	# No ar não deixa rastro (a esteira volta quando o casco toca a água).
	ocean.wake_head_active = measured_speed > 0.3 and not airborne
	if airborne:
		last_wake = global_position
	elif measured_speed > 0.3 and global_position.distance_to(last_wake) > 2.0:
		ocean.add_wake(global_position - heading * 1.6)
		last_wake = global_position

func _wind_at(point: Vector3) -> Vector3:
	var manager := get_node_or_null("/root/WindManager")
	if manager != null:
		return manager.wind_at(point)
	return Scale.wind_at(point)

func update_attitude(delta: float, acceleration: float) -> void:
	var speed_ratio := clampf(absf(drive_speed)/maxf(boost_speed, 0.1),0.0,1.0)
	var target_roll := -turn_input*max_bank_angle*speed_ratio
	# Positive X raises the -Z bow in Godot. Braking briefly dips it.
	var target_pitch := deg_to_rad(1.4)*speed_ratio + deg_to_rad(1.1)*clampf(acceleration/3.0,-1.0,1.0)
	var remaining := minf(delta,0.25)
	while remaining>0.0:
		var step := minf(remaining,1.0/120.0)
		roll_velocity += ((target_roll-bank_roll)*bank_spring-roll_velocity*bank_damping)*step
		bank_roll += roll_velocity*step
		pitch_velocity += ((target_pitch-acceleration_pitch)*18.0-pitch_velocity*6.0)*step
		acceleration_pitch += pitch_velocity*step
		remaining -= step
	turn_bias = clampf(bank_roll/max_bank_angle,-1.0,1.0)
