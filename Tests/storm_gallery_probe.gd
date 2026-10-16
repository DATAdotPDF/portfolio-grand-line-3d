extends SceneTree

## Cada tempestade (e a nuvem dos ciclones) vista do barco a ~260 m, de dia e à noite.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/storm_gallery_probe.gd
## Saída: Builds/StormGallery/*.jpg

var world: Node3D
var cam: Camera3D

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/StormGallery/%s.jpg" % name), 0.85)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/StormGallery"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.clock.set_time(0.40, true)
	world.select_time("day")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	world.hud.visible = false
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.far = 4000.0
	world.add_child(cam)
	cam.make_current()
	var weather: Node = world.weather
	for i in weather.movers.size():
		weather.targets[i] = weather.movers[i].center
	var cells: Array = weather.storms
	for mode in ["day", "night"]:
		if mode == "sunset":
			world.select_time("day")
			world.clock.set_time(0.73, true)
		else:
			world.select_time(mode)
		for i in cells.size():
			var cell: Node3D = cells[i]
			var centre: Vector3 = cell.center * world.planet_radius
			var up: Vector3 = cell.center
			var away: Vector3 = up.cross(Vector3.RIGHT).normalized()
			var eye_dir: Vector3 = (centre + away * 260.0).normalized()
			for f in 20:
				cam.global_position = eye_dir * (world.planet_radius + 6.0)
				cam.look_at(centre + up * 35.0, eye_dir)
				await process_frame
			print("GALLERY %s %d shape=%s badness=%.1f" % [mode, i, cell.shape, cell.badness])
			await still("%s_%d_%s" % [mode, i, cell.shape])
	quit()
