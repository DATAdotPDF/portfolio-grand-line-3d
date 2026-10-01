extends Node3D

const Scale = preload("res://Scripts/WorldScale.gd")

@export var player_sloop: Node3D
@export var islands_parent: Node3D
@export var needle_smoothness := 6.0
@export var wobble_speed := 14.0
@export var wobble_angle_deg := 3.5
@export var check_interval := 0.25

@onready var needle_pivot: Node3D = $Needle_Pivot
var nearest_island: Node3D
var target_angle_rad := 0.0
var current_angle_rad := 0.0
var check_timer := 0.0
var wobble_phase := 0.0
var redraw_timer := 0.0
var compass_viewport: SubViewport
var current_island_idx := -1
var inspection_target := Vector2.ZERO
var inspection_angle := Vector2.ZERO
var inspection_velocity := Vector2.ZERO
var dragging := false
var pointer_over := false
var route_label: Label
var internal_light: OmniLight3D

func _ready() -> void:
	compass_viewport = get_parent() as SubViewport
	_build_models()
	call_deferred("_build_lighting_and_input")
	_update_nearest_island()

func _build_models() -> void:
	var base := (load("res://Assets/Meshy_AI_log_pose_modular_base_1001025605_image-to-3d-texture.glb") as PackedScene).instantiate() as Node3D
	base.name = "Base_Mesh"
	add_child(base)
	base.scale = Vector3.ONE * 0.82
	var needle := (load("res://Assets/Meshy_AI_log_pose_needle_isola_1001025714_image-to-3d-texture.glb") as PackedScene).instantiate() as Node3D
	needle.name = "Needle_Mesh"
	needle_pivot.add_child(needle)
	needle.scale = Vector3.ONE * 0.56
	needle.rotation.x = -PI * 0.5
	needle_pivot.position.y = 0.59
	for mesh in needle.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()):
			var source: Material = mesh.get_active_material(surface)
			if source is StandardMaterial3D:
				var paint := source.duplicate() as StandardMaterial3D
				paint.emission_enabled = true
				paint.emission = Color("ffe4a0")
				paint.emission_texture = paint.albedo_texture
				paint.emission_energy_multiplier = 0.35
				mesh.set_surface_override_material(surface,paint)
	var dome_resource := load("res://Assets/Meshy_AI_log_pose_glass_dome_3_1001030520_image-to-3d-texture.glb") as PackedScene
	if dome_resource:
		var dome := dome_resource.instantiate() as Node3D
		dome.name = "GlassDome_Mesh"
		add_child(dome)
		dome.scale = Vector3.ONE * 0.82
		dome.position.y = 1.02
		var glass := ShaderMaterial.new()
		glass.shader = load("res://Shaders/compass_glass.gdshader")
		for mesh in dome.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = glass

func _process(delta: float) -> void:
	if not is_instance_valid(player_sloop) or not is_instance_valid(needle_pivot):
		return
	check_timer += delta
	if check_timer >= check_interval:
		check_timer = 0.0
		_update_nearest_island()
	if is_instance_valid(nearest_island):
		target_angle_rad = heading_to(nearest_island.global_position)
	_update_inspection(delta)
	wobble_phase += delta * wobble_speed
	current_angle_rad = lerp_angle(current_angle_rad, target_angle_rad, 1.0 - exp(-needle_smoothness * delta))
	needle_pivot.rotation.y = current_angle_rad + sin(wobble_phase) * deg_to_rad(wobble_angle_deg)
	redraw_timer -= delta
	if redraw_timer <= 0.0:
		compass_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		redraw_timer = 1.0 / (30.0 if pointer_over else 20.0)

func _update_nearest_island() -> void:
	if not is_instance_valid(player_sloop) or not is_instance_valid(islands_parent):
		return
	var islands := islands_parent.get_children().filter(func(node): return node is Node3D)
	if islands.is_empty(): return
	var boat_direction := player_sloop.global_position.normalized()
	var nearest_distance := INF
	for index in range(islands.size()):
		var candidate := islands[index] as Node3D
		var arc := boat_direction.angle_to(candidate.global_position.normalized()) * Scale.radius()
		if arc < nearest_distance:
			nearest_distance = arc
			nearest_island = candidate
			current_island_idx = index
	if route_label:
		route_label.text = "MAIS PERTO · " + str(nearest_island.get_meta("section",nearest_island.name)).to_upper()

func heading_to(island_position: Vector3) -> float:
	var boat_up := player_sloop.global_position.normalized()
	var destination := island_position.normalized().slide(boat_up).normalized()
	if destination.is_zero_approx():
		return target_angle_rad
	var forward := (-player_sloop.global_basis.z).slide(boat_up).normalized()
	var right := player_sloop.global_basis.x.slide(boat_up).normalized()
	return atan2(destination.dot(right), destination.dot(forward))

func _build_lighting_and_input() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff0cd")
	env.ambient_light_energy = 0.75
	environment.environment = env
	compass_viewport.add_child(environment)
	internal_light = OmniLight3D.new()
	internal_light.name = "DialAmberLight"
	internal_light.position = Vector3(0,0.9,0.15)
	internal_light.light_color = Color("ffe4a0")
	internal_light.light_energy = 1.7
	internal_light.omni_range = 2.0
	internal_light.shadow_enabled = false
	add_child(internal_light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-55,-30,0)
	fill.light_energy = 1.0
	compass_viewport.add_child(fill)
	var control := compass_viewport.get_parent() as SubViewportContainer
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.tooltip_text = "Log Pose: ilha mais próxima. Arraste com botão direito para examinar."
	control.gui_input.connect(_inspect_input)
	control.mouse_entered.connect(func(): pointer_over = true)
	control.mouse_exited.connect(func(): pointer_over = false; dragging = false; inspection_target = Vector2.ZERO)
	route_label = Label.new()
	route_label.position = Vector2(0,194)
	route_label.size = Vector2(220,24)
	route_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	route_label.add_theme_font_size_override("font_size",13)
	route_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	route_label.add_theme_constant_override("shadow_offset_y",1)
	route_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_child(route_label)

func _inspect_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		dragging = event.pressed
	if event is InputEventMouseMotion:
		if dragging:
			inspection_target += Vector2(event.relative.y,event.relative.x)*0.007
			inspection_target.x = clampf(inspection_target.x,-0.32,0.32)
			inspection_target.y = clampf(inspection_target.y,-0.7,0.7)
		else:
			inspection_target = Vector2((event.position.y-110.0)/110.0,(event.position.x-110.0)/110.0)*0.10
	(compass_viewport.get_parent() as Control).accept_event()

func _update_inspection(delta: float) -> void:
	var remaining := minf(delta,0.15)
	while remaining>0.0:
		var step := minf(remaining,1.0/120.0)
		inspection_velocity += ((inspection_target-inspection_angle)*40.0-inspection_velocity*10.0)*step
		inspection_angle += inspection_velocity*step
		remaining -= step
	rotation = Vector3(inspection_angle.x,inspection_angle.y,0)
