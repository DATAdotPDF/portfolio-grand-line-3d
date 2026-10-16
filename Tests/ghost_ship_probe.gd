extends SceneTree

## Navio fantasma: força a noite, faz ele surgir perto e fotografa aparecendo e inteiro.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/ghost_ship_probe.gd

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/GhostShipProbe/%s.jpg" % name), 0.85)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/GhostShipProbe"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("night")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.hud.visible = false
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	var ghost: Node3D = world.ghost_ship
	ghost.vanish_distance = 0.0
	ghost.require_night = false
	# Teleporta o barco para mar aberto e faz o fantasma surgir a 40–70 m.
	var p: Vector3 = world.weather.open_sea[world.weather.open_sea.size() / 2]
	world.ship.global_position = p * world.planet_radius
	for f in 10:
		await process_frame
	print("night=", world.clock.night_at(world.ship.global_position))
	if not ghost.spawn(true):
		print("GHOST_PROBE spawn failed")
		quit()
		return
	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.make_current()
	for shot in [["appear", 1.5], ["half", 3.0], ["full", 6.0], ["full_b", 9.0]]:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < shot[1] * 1000.0 * 0.4:
			var g: Transform3D = ghost.global_transform
			cam.global_position = g * Vector3(18.0, 6.0, 4.0)
			cam.look_at(g * Vector3(0.0, 4.5, 0.0), g.basis.y)
			await process_frame
		await still(shot[0])
	print("GHOST_PROBE presence=", ghost.presence)
	quit()
