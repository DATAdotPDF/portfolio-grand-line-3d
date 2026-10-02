@tool
extends CharacterBody3D

const Scale = preload("res://Scripts/WorldScale.gd")

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
	var target_speed := throttle * (boost_speed if boost else cruise_speed)
	if throttle > 0.0:
		var wind_tangent := _wind_at(global_position)
		if wind_tangent.length_squared() > 0.0001:
			var wind_alignment := heading.dot(wind_tangent.normalized())
			var local_strength := clampf(wind_tangent.length(), 0.0, 1.0)
			var sail_factor := lerpf(1.0, 0.72 + 0.28 * wind_alignment, wind_strength * local_strength)
			target_speed *= sail_factor
	if throttle < 0.0:
		target_speed = -reverse_speed
	if is_zero_approx(throttle):
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
	velocity = heading * drive_speed
	shore_blocked = false
	move_and_slide()
	var moved_up := global_position.normalized()
	var center: Vector3 = ocean.surface_at(global_position)
	# A altura segue o ponto mais alto entre o centro e a média do casco: nas cristas
	# a média dos pontos baixava o barco ('afundava'). draft_offset ajusta a linha d'água.
	var hull_mean: float = (front.length() + rear.length() + port.length() + starboard.length()) * 0.25
	var target_radius: float = maxf(center.length(), hull_mean) + draft_offset
	var current := global_position.length()
	var radius := lerpf(current, target_radius, 1.0 - exp(-14.0 * delta))
	radial_speed = (radius - current) / maxf(delta, 0.00001)
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
		wave_basis = wave_basis.slerp(desired_local, 1.0 - exp(-wave_follow_rate * delta)).orthonormalized()
		update_attitude(delta,acceleration)
		float_visual.basis = wave_basis * Basis.from_euler(Vector3(acceleration_pitch,0,bank_roll))
	ocean.wake_head = global_position - heading * 1.9
	ocean.wake_head_active = measured_speed > 0.3
	if measured_speed > 0.3 and global_position.distance_to(last_wake) > 2.0:
		ocean.add_wake(global_position - heading * 1.7)
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
