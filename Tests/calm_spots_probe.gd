extends SceneTree

## Mar calmo em volta das ilhas/rochas do mapa (calm_spots): mede a variação da altura do mar na borda
## de um POI fixo e a 120 m dele, e tira um print de lado com o mar mais agitado.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/calm_spots_probe.gd [-- <tipo>]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var kind := "stepped_basalt_reef"
	for arg in OS.get_cmdline_user_args():
		kind = arg
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	var target: Dictionary = {}
	for item in world.world_decor.items:
		if item.kind == kind:
			target = item
			break
	if target.is_empty():
		print("CALM no item ", kind)
		quit()
		return
	var root_node: Node3D = target.root
	var up := root_node.global_position.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var ship_pos: Vector3 = world.ocean.surface_at(root_node.global_position + side * 70.0)
	var fwd := side.cross(ship_pos.normalized()).normalized()
	world.ship.heading = fwd
	world.ship.global_transform = Transform3D(Basis(fwd.cross(ship_pos.normalized()).normalized(), ship_pos.normalized(), -fwd), ship_pos)
	await create_timer(1.5).timeout
	print("CALM spots=%d radius=%.1f" % [world.ocean.calm_spots.size(), float(target.radius)])
	var r := float(target.radius)
	var rim := root_node.global_position + side.rotated(up, 1.0) * (r * 1.05)
	var far := root_node.global_position + side.rotated(up, 1.0) * (r + 120.0)
	var rim_h: Array[float] = []
	var far_h: Array[float] = []
	for i in 40:
		rim_h.append(float(world.ocean.height_at(rim)))
		far_h.append(float(world.ocean.height_at(far)))
		await create_timer(0.1).timeout
	print("CALM rim range=%.2f m  far range=%.2f m  coast(rim)=%.2f" % [rim_h.max() - rim_h.min(), far_h.max() - far_h.min(), world.ocean._coast_factor(rim.normalized() * world.planet_radius)])
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.make_current()
	cam.look_at_from_position(root_node.global_position + side.rotated(up, -0.6) * (r * 3.0 + 25.0) + up * 8.0, root_node.global_position + up * 3.0, up)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/Encounters/calm_%s.jpg" % kind), 0.85)
	print("PRINT calm_", kind)
	quit()
