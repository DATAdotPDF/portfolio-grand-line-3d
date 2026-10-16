extends SceneTree

## Nuvem do tornado vista de baixo (onde aparecia uma linha na costura do disco, em 0°/360°):
## quatro vistas olhando para cima em volta do funil.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/tornado_cloud_seam_probe.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var cyclone: Node3D = world.weather.cyclones[0]
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.make_current()
	for i in 4:
		var up: Vector3 = cyclone.center.normalized()
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized().rotated(up, i * PI * 0.5)
		var base: Vector3 = cyclone.global_position
		var top: Vector3 = cyclone.axis_point(1.0) + up * 10.0
		cam.look_at_from_position(base + side * 70.0 + up * 25.0, top, up)
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/Encounters/seam_%d.jpg" % i), 0.85)
		print("PRINT seam_", i)
	quit()
