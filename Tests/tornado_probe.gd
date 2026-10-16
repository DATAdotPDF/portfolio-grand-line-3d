extends SceneTree

## Tornado (Cyclone) visto do barco, de dia e à noite. Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/tornado_probe.gd

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/Encounters/%s.jpg" % name), 0.85)
	print("PRINT ", name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/Encounters"))
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.hud._set_carta_open(false)
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	var cyclone: Node3D = world.weather.cyclones[0]
	var c: Vector3 = cyclone.center
	var tangent := c.cross(Vector3.UP if absf(c.y) < 0.9 else Vector3.RIGHT).normalized()
	for shot in [["tornado_far", 330.0], ["tornado_near", 170.0]]:
		var pos: Vector3 = (c * world.planet_radius - tangent * float(shot[1])).normalized() * world.planet_radius
		var surface: Vector3 = world.ocean.surface_at(pos)
		var up := surface.normalized()
		var forward := tangent.slide(up).normalized()
		world.ship.heading = forward
		world.ship.global_transform = Transform3D(Basis(forward.cross(up).normalized(), up, -forward), surface)
		await create_timer(3.0).timeout
		await still(shot[0])
	quit()
