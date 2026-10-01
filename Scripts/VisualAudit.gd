extends Node3D

const WORLD = preload("res://MainWorld.tscn")
const DISTANCES := [38.0, 44.0, 40.0, 42.0, 68.0]
const FOCUS := [10.0, 13.0, 16.0, 14.0, 23.0]

func _ready() -> void:
	var world: Variant = WORLD.instantiate()
	add_child(world)
	await get_tree().create_timer(3.0).timeout
	var camera: Camera3D = world.camera
	camera.snap_to_boat()
	camera.set_process(false)
	world.ship.set_physics_process(false)
	var hud := world.get_node_or_null("NavigationHUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var pose := world.get_node_or_null("LogPose_HUD") as CanvasLayer
	if pose != null:
		pose.visible = false
	await _save_view("boat")
	camera.global_position = Vector3(0.45, 0.62, 0.64).normalized() * 510.0
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await _save_view("globe")
	for index in range(world.islands.size()):
		var island: Node3D = world.islands[index]
		var up := island.global_position.normalized()
		var model := island.get_node_or_null("IslandModel") as Node3D
		print("ISLAND_AXIS ", index + 1, " position=", island.global_position, " anchor_up=", island.global_basis.y, " anchor_dot=", island.global_basis.y.dot(up), " model_up=", model.global_basis.y if model != null else Vector3.ZERO)
		camera.set_process(true)
		camera.focus_island(island)
		await get_tree().create_timer(2.5).timeout
		camera.set_process(false)
		print("ISLAND_FRAME ", index + 1, " focus=", camera.framed_focus_height, " distance=", camera.framed_orbit_distance)
		await _save_view("island_%02d" % (index + 1))
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1.0, 0.0, 1.0)
	world.ship.set_physics_process(true)
	var min_radius := INF
	var max_radius := -INF
	var max_surface_error := 0.0
	for sample in range(20):
		await get_tree().create_timer(0.5).timeout
		var ship_radius: float = world.ship.global_position.length()
		var water_radius: float = world.ocean.surface_at(world.ship.global_position).length()
		min_radius = minf(min_radius, ship_radius)
		max_radius = maxf(max_radius, ship_radius)
		max_surface_error = maxf(max_surface_error, absf(ship_radius - water_radius))
	print("BOAT_WAVE_AUDIT min_radius=", min_radius, " max_radius=", max_radius, " travel=", max_radius - min_radius, " max_surface_error=", max_surface_error, " fps=", Engine.get_frames_per_second())
	var fired: bool = world.naval.fire()
	await get_tree().create_timer(1.5).timeout
	print("CANNON_AUDIT fired=", fired, " shots=", world.naval.shots_fired, " active_balls=", world.naval.balls.size())

func _save_view(view_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := "user://audit_" + view_name + ".png"
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("VISUAL_AUDIT ", view_name, " path=", ProjectSettings.globalize_path(path), " error=", error)
