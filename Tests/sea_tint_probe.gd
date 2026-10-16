extends SceneTree

## Os quatro mares (WorldDecor + ocean_waves.gdshaderinc biome_tint): fotos do alto em cima das
## bordas entre biomas (Leste|Oeste no equador, faixa|Sul e faixa|Norte), de dia.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/sea_tint_probe.gd [-- noite]

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var night := "noite" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/SeaTint"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("night" if night else "day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.graphics.set_mode("alto")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	var decor: Node = world.world_decor
	var cam := Camera3D.new()
	cam.far = 5000.0
	cam.fov = 60.0
	root.add_child(cam)
	# [nome, lat, lon do ponto olhado]
	for spot in [["leste_oeste", 0.0, 180.0], ["faixa_sul", -30.0, 300.0], ["faixa_norte", 30.0, 60.0]]:
		var c: Vector3 = decor._lat_lon(spot[1], spot[2]) * world.planet_radius
		var up := c.normalized()
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		world.ship.global_position = world.ocean.surface_at(c + side * 30.0)
		for f in 90:
			for layer in world.find_children("*", "CanvasLayer", true, false):
				layer.visible = false
			cam.make_current()
			cam.look_at_from_position(c + up * 55.0 - side * 120.0, c + side * 60.0, up)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/SeaTint/%s_%s.jpg" % ["noite" if night else "dia", spot[0]]), 0.88)
		print("PRINT ", spot[0])
	quit()
