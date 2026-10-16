extends SceneTree

## Evento do kraken: fotos da chegada (sombra), dos tentáculos e do redemoinho (de cima e do barco).
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/kraken_probe.gd

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/Encounters/%s.jpg" % name), 0.85)
	print("PRINT ", name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/Encounters"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.hud._set_carta_open(false)
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1.0, 0.0, 0.0)
	var p: Vector3 = world.weather.open_sea[world.weather.open_sea.size() / 3]
	world.ship.global_position = world.ocean.surface_at(p * world.planet_radius)
	world.ship.heading = Vector3.FORWARD.slide(p).normalized()
	await create_timer(2.0).timeout
	var k: Node = world.kraken_event
	k.start()
	await create_timer(9.0).timeout
	await still("k1_shadow_arriving")
	while k.phase == 1:
		await process_frame
	await create_timer(7.0).timeout
	await still("k2_tentacles")
	while k.phase == 2:
		await process_frame
	world.ship.test_controls = Vector3.ZERO
	await create_timer(5.0).timeout
	await still("k3_whirlpool_boat")
	var cam := Camera3D.new()
	world.add_child(cam)
	var up: Vector3 = k.center.normalized()
	cam.global_position = k.center + up * 160.0
	cam.look_at(k.center, up.cross(Vector3.RIGHT).normalized())
	cam.make_current()
	k.vortex.visible = false  # câmera acima das nuvens: tira o vórtice do céu para ver o mar
	await create_timer(0.5).timeout
	await still("k4_whirlpool_top")
	k.vortex.visible = true
	var side := Camera3D.new()
	world.add_child(side)
	var t: Vector3 = up.cross(Vector3.RIGHT).normalized()
	side.global_position = k.center - t * 150.0 + up * 45.0
	side.look_at(k.center, up)
	side.make_current()
	await create_timer(0.5).timeout
	await still("k5_whirlpool_side")
	quit()
