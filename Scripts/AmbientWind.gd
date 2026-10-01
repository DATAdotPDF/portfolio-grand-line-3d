@tool
extends Node3D

const RIBBON_SHADER = preload("res://Shaders/WindRibbon.gdshader")
var boat: Node3D
@export var wind_direction := Vector3(0.9, 0.15, 0.3):
	set(value):
		wind_direction = value.normalized() if value.length_squared() > 0.0001 else Vector3.FORWARD
		if Engine.is_editor_hint() and is_inside_tree():
			_update_editor_preview()
var gusts: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 1041
	for i in range(5):
		var mesh := get_node_or_null("WorldGust_%d" % i) as MeshInstance3D
		if mesh == null:
			mesh = MeshInstance3D.new()
			mesh.name = "WorldGust_%d" % i
			var strip := PlaneMesh.new()
			strip.subdivide_width = 47
			strip.subdivide_depth = 1
			mesh.mesh = strip
			add_child(mesh)
		mesh.custom_aabb = AABB(Vector3(-14,-5,-5), Vector3(42,18,10))
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not (mesh.material_override is ShaderMaterial):
			var material := ShaderMaterial.new()
			material.shader = RIBBON_SHADER
			mesh.material_override = material
		mesh.visible = false
		gusts.append({"mesh":mesh,"age":5.0,"delay":float(i)*1.1,"life":4.0})
	if Engine.is_editor_hint():
		_update_editor_preview()
		set_process(false)

func _update_editor_preview() -> void:
	if gusts.is_empty():
		return
	var ship := get_node_or_null("../PlayerShip") as Node3D
	if ship == null:
		return
	var up := ship.global_position.normalized()
	var wind := wind_direction.slide(up)
	if wind.length_squared() < 0.0001:
		wind = Vector3.FORWARD.slide(up)
	wind = wind.normalized()
	var sideways := wind.cross(up).normalized()
	var preview := gusts[0].mesh as MeshInstance3D
	preview.global_position = ship.global_position - wind * 5.0 + up * 3.0
	preview.global_basis = Basis(wind, up, sideways).orthonormalized()
	preview.material_override.set_shader_parameter("age", 0.55)
	preview.material_override.set_shader_parameter("loop_style", 0.0)
	preview.visible = true

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if not is_instance_valid(boat): return
	for gust in gusts:
		gust.age += delta
		if gust.age >= gust.life:
			gust.mesh.visible = false
			gust.delay -= delta
			if gust.delay <= 0.0: _spawn(gust)
		else:
			gust.mesh.material_override.set_shader_parameter("age", gust.age/gust.life)

func _spawn(gust: Dictionary) -> void:
	var up := boat.global_position.normalized()
	var manager := get_node_or_null("/root/WindManager")
	var wind: Vector3 = manager.wind_at(boat.global_position) if manager else wind_direction.slide(up)
	# Calm Belt: sem vento, sem fitas.
	if wind.length_squared() < 0.04:
		gust.delay = 1.5
		return
	wind = wind.normalized()
	var sideways := wind.cross(up).normalized()
	# Only the birth position follows the sailor. Existing gusts stay in world space.
	gust.mesh.global_position = boat.global_position - wind*rng.randf_range(7.0,15.0) + sideways*rng.randf_range(-14.0,14.0) + up*rng.randf_range(3.0,8.0)
	gust.mesh.global_basis = Basis(wind,up,sideways).orthonormalized()
	gust.age = 0.0
	gust.life = rng.randf_range(3.6,4.6)
	gust.delay = rng.randf_range(1.5,4.0)
	gust.mesh.visible = true
	gust.mesh.material_override.set_shader_parameter("age",0.0)
	gust.mesh.material_override.set_shader_parameter("loop_style",1.0 if rng.randf()<0.3 else 0.0)
	gust.mesh.material_override.set_shader_parameter("phase_offset",rng.randf())
