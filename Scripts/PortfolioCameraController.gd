@tool
extends Camera3D

signal island_visit_started(index: int)

const Scale = preload("res://Scripts/WorldScale.gd")
enum CameraState { BOAT_FOLLOW, FLYING, ISLAND_ORBIT, PLANET_OVERVIEW }

const ORBIT_PITCHES := [10.0, 12.0, 10.0, 12.0, 16.0]
## Fator de enquadramento do brief (distância mínima = altura total × fator).
const FRAMING_FACTOR := 1.6

@export_group("Navegação")
@export_range(6.0, 30.0, 0.5) var follow_distance := 12.0
@export_range(2.0, 15.0, 0.5) var follow_height := 5.0

var boat: Node3D
var islands: Array[Node3D] = []
var target_island: Node3D
var active_island_idx := -1
var framed_focus_height := 8.0
var framed_orbit_distance := 40.0
var state := CameraState.BOAT_FOLLOW
var destination := CameraState.BOAT_FOLLOW
var yaw := 0.0
var pitch := 0.0
var orbit_angle := 0.0
var overview_direction := Vector3(0.4, 0.48, 0.78).normalized()
var transition_start := Vector3.ZERO
var transition_progress := 1.0
var transition_duration := 2.2
var transition_tween: Tween
var plate_tweens: Array[Tween] = []
var elapsed := 0.0
var overview_dragged := false
var overview_up := Vector3.UP

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var key_event := event as InputEventKey
	if not key_event or not key_event.pressed:
		return
	
	var key := key_event.physical_keycode
	if key >= KEY_1 and key <= KEY_5:
		var index := int(key) - int(KEY_1)

		if index < islands.size():
			focus_island(islands[index])
			get_viewport().set_input_as_handled()
	elif key == KEY_0 or key == KEY_ESCAPE:
		return_to_boat()
		get_viewport().set_input_as_handled()

func snap_to_boat() -> void:
	if not is_instance_valid(boat):
		return
	global_position = _boat_position()
	_face(_boat_focus(), boat.global_position.normalized())

func focus_island(island: Node3D) -> void:
	if not is_instance_valid(island):
		return
	var index := islands.find(island)
	if index < 0 or index >= 5:
		return
	island_visit_started.emit(index)
	target_island = island
	active_island_idx = index
	_frame_island_geometry(island, index)
	var up := island.global_position.normalized()
	var east := _island_east(island, up)
	var north := up.cross(east)
	var offset := global_position - island.global_position
	orbit_angle = atan2(offset.dot(north), offset.dot(east))
	_animate_titles(index)
	_begin_transition(CameraState.ISLAND_ORBIT)

func return_to_boat() -> void:
	if not is_instance_valid(boat):
		return
	active_island_idx = -1
	target_island = null
	_animate_titles(-1)
	_begin_transition(CameraState.BOAT_FOLLOW)

func show_overview() -> void:
	overview_dragged = false
	overview_up = Vector3.UP
	active_island_idx = -1
	target_island = null
	overview_direction = global_position.normalized()
	_animate_titles(-1)
	_begin_transition(CameraState.PLANET_OVERVIEW)

func drag_orbit(relative: Vector2) -> void:
	if state == CameraState.BOAT_FOLLOW:
		yaw -= relative.x * 0.004
		pitch = clampf(pitch + relative.y * 0.035, -2.0, 8.0)
	elif state == CameraState.ISLAND_ORBIT:
		orbit_angle -= relative.x * 0.005
	elif state == CameraState.PLANET_OVERVIEW:
		# Giro do globo (trackball). Com o fundo fixo na tela, girar a vista equivale a girar o planeta.
		overview_dragged = true
		overview_direction = overview_direction.rotated(global_basis.y.normalized(), -relative.x * 0.004)
		overview_direction = overview_direction.rotated(global_basis.x.normalized(), -relative.y * 0.004).normalized()
		overview_up = overview_up.rotated(global_basis.x.normalized(), -relative.y * 0.004)

func _begin_transition(next_state: CameraState) -> void:
	if transition_tween and transition_tween.is_running():
		transition_tween.kill()
	transition_start = global_position
	transition_progress = 0.0
	destination = next_state
	state = CameraState.FLYING
	transition_tween = create_tween()
	transition_tween.set_trans(Tween.TRANS_SINE)
	transition_tween.set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_property(
		self, "transition_progress", 1.0, transition_duration
	)
	transition_tween.finished.connect(_finish_transition)

func _finish_transition() -> void:
	if state == CameraState.FLYING:
		state = destination

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	elapsed += delta
	match state:
		CameraState.BOAT_FOLLOW:
			if not is_instance_valid(boat):
				return
			global_position = global_position.lerp(
				_boat_position(), 1.0 - exp(-5.0 * delta)
			)
			_face(_boat_focus(), _boat_xform().origin.normalized())
		CameraState.FLYING:
			var target := _destination_position()
			var direction := transition_start.normalized().slerp(
				target.normalized(), transition_progress
			).normalized()
			var radius := lerpf(
				transition_start.length(),
				target.length(),
				transition_progress
			)
			radius += sin(transition_progress * PI) * 12.0
			global_position = direction * maxf(
				Scale.radius() + Scale.max_wave_height() + 4.0, radius
			)
			_face(_destination_focus(), direction)
		CameraState.ISLAND_ORBIT:
			if not is_instance_valid(target_island):
				return_to_boat()
				return
			orbit_angle += 0.12 * delta
			global_position = _island_position()
			_face(_island_focus(), target_island.global_position.normalized())
		CameraState.PLANET_OVERVIEW:
			if not overview_dragged:
				overview_direction = overview_direction.rotated(overview_up.normalized(), delta * 0.055).normalized()
			global_position = overview_direction * _overview_distance()
			_face(Vector3.ZERO, overview_up.slide(overview_direction).normalized() if overview_up.slide(overview_direction).length_squared() > 0.001 else _fallback_tangent(overview_direction))
	if active_island_idx >= 0 and state in [
		CameraState.FLYING, CameraState.ISLAND_ORBIT
	]:
		_update_active_title()

func _overview_distance() -> float:
	return Scale.radius() * 2.6

## Transform interpolado do barco: usar a posição física (60 Hz) fazia a tela tremer.
func _boat_xform() -> Transform3D:
	return boat.get_global_transform_interpolated() if boat.has_method("get_global_transform_interpolated") else boat.global_transform

func _boat_position() -> Vector3:
	var xform := _boat_xform()
	var up := xform.origin.normalized()
	var forward := (-xform.basis.z).slide(up).normalized().rotated(up, yaw)
	return xform.origin - forward * follow_distance + up * (follow_height + pitch)

func _boat_focus() -> Vector3:
	var origin := _boat_xform().origin
	return origin + origin.normalized() * 1.5

func _bounds_in_island(island: Node3D, visual: Node3D) -> AABB:
	var total := AABB()
	var found := false
	for candidate in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := candidate as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var relative: Transform3D = island.global_transform.affine_inverse() * mesh.global_transform
		var part: AABB = relative * mesh.get_aabb()
		total = total.merge(part) if found else part
		found = true
	return total

## Enquadramento por ilha a partir dos valores MEDIDOS pelo IslandDistributor:
## chão = base real da ilha (floor_offset), teto = topo da placa de título daquela ilha.
func frame_island(island_floor_y: float, plate_ceiling_y: float, horizontal_width: float) -> void:
	var total_height := plate_ceiling_y - island_floor_y
	framed_focus_height = (island_floor_y + plate_ceiling_y) * 0.5
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var half_fov_tangent := tan(deg_to_rad(fov) * 0.5)
	# FOV vertical fixo: em telas em pé (mobile, aspect < 1) a largura passa a limitar.
	var vertical_distance := (total_height * 0.5 + 3.0) / half_fov_tangent
	var horizontal_distance := (horizontal_width * 0.5 + 3.0) / (half_fov_tangent * aspect)
	framed_orbit_distance = maxf(total_height * FRAMING_FACTOR, maxf(vertical_distance, horizontal_distance) * 1.1)

func _frame_island_geometry(island: Node3D, _index: int) -> void:
	var model := island.get_node_or_null("IslandModel") as Node3D
	if model == null:
		return
	var island_bounds := _bounds_in_island(island, model)
	var horizontal_width := maxf(island_bounds.size.x, island_bounds.size.z)
	var island_floor := float(island.get_meta("island_floor", island_bounds.position.y))
	var plate_ceiling := float(island.get_meta("plate_ceiling", island_bounds.end.y))
	frame_island(island_floor, plate_ceiling, maxf(horizontal_width, 8.0))

func _island_focus() -> Vector3:
	var up := target_island.global_position.normalized()
	return target_island.global_position + up * framed_focus_height

func _island_position() -> Vector3:
	var up := target_island.global_position.normalized()
	var east := _island_east(target_island, up)
	var north := up.cross(east)
	var distance := framed_orbit_distance
	var elevation := deg_to_rad(float(ORBIT_PITCHES[active_island_idx]))
	var around := east * cos(orbit_angle) + north * sin(orbit_angle)
	return _island_focus() + around * distance * cos(elevation) + up * distance * sin(elevation)

func _island_east(island: Node3D, up: Vector3) -> Vector3:
	var east := island.global_transform.basis.x.slide(up)
	if east.length_squared() < 0.0001:
		east = _fallback_tangent(up)
	return east.normalized()

func _fallback_tangent(up: Vector3) -> Vector3:
	var tangent := Vector3.UP.slide(up)
	if tangent.length_squared() < 0.0001:
		tangent = Vector3.FORWARD.slide(up)
	return tangent.normalized()

func _destination_position() -> Vector3:
	match destination:
		CameraState.ISLAND_ORBIT:
			return _island_position()
		CameraState.PLANET_OVERVIEW:
			return overview_direction * _overview_distance()
		_:
			return _boat_position()

func _destination_focus() -> Vector3:
	match destination:
		CameraState.ISLAND_ORBIT:
			return _island_focus()
		CameraState.PLANET_OVERVIEW:
			return Vector3.ZERO
		_:
			return _boat_focus()

func _find_title(index: int) -> Node3D:
	if index < 0 or index >= islands.size():
		return null
	return islands[index].get_node_or_null("IslandTitleSign") as Node3D

func _animate_titles(selected_index: int) -> void:
	plate_tweens.resize(islands.size())
	for index in range(islands.size()):
		var title_node := _find_title(index)
		if not is_instance_valid(title_node):
			continue
		if plate_tweens[index] and plate_tweens[index].is_running():
			plate_tweens[index].kill()
		title_node.set_process(false)
		if index == selected_index:
			title_node.visible = true
			title_node.scale = Vector3.ZERO
			title_node.set("reveal_amount", 1.0)
			for mesh in title_node.get("meshes"):
				mesh.transparency = 0.0
			var light := title_node.get("title_light") as OmniLight3D
			if light:
				light.light_energy = 0.55
		var target_scale := Vector3.ONE if index == selected_index else Vector3.ZERO
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(
			title_node,
			"scale",
			target_scale,
			0.6 if index == selected_index else 0.35
		)
		if index != selected_index:
			tween.finished.connect(_finish_title_hide.bind(title_node, selected_index))
		plate_tweens[index] = tween

func _finish_title_hide(title_node: Node3D, selected_index: int) -> void:
	if not is_instance_valid(title_node):
		return
	title_node.visible = false
	if selected_index == -1:
		title_node.set("reveal_amount", 0.0)
		title_node.set("revealed", false)
		title_node.set_process(true)

func _update_active_title() -> void:
	var title_node := _find_title(active_island_idx)
	if not is_instance_valid(title_node) or title_node.scale.length_squared() < 0.0001:
		return
	var island := islands[active_island_idx]
	var base: Vector3 = title_node.get("base_position")
	title_node.position = base + Vector3.UP * sin(elapsed * 1.2 + active_island_idx) * 0.22
	title_node.look_at(global_position, island.global_position.normalized(), true)
	var night: float = get_node("/root/DayNightCycle").night_at(island.global_position)
	for material in title_node.get("title_materials"):
		material.emission_energy_multiplier = lerpf(0.04, 0.24, night)
	var light := title_node.get("title_light") as OmniLight3D
	if light:
		light.light_energy = lerpf(0.15, 0.55, night)

func _face(point: Vector3, preferred_up: Vector3) -> void:
	var view_direction := (point - global_position).normalized()
	var camera_up := preferred_up.slide(view_direction)
	if camera_up.length_squared() < 0.0001:
		camera_up = _fallback_tangent(view_direction)
	look_at(point, camera_up.normalized())
