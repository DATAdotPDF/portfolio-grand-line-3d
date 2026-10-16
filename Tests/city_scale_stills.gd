extends SceneTree

## Escala das 3 cidades grandes: barco parado ao lado de cada uma (a ~25 m da borda), câmera ~35 m atrás
## do barco enquadrando a cidade inteira. Luz do jogo (dia), gráficos no Alto.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/city_scale_stills.gd
## Saída: Builds/Videos/Cidades/escala_<cidade>.jpg

const CITIES := ["runestone_citadel", "driftwood_merchant", "coral_paradise"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.graphics.set_mode("alto")
	world.ghost_ship.timer = 9999.0
	world.kraken_event.cooldown = 1e9
	# Sem tornado no quadro.
	for n in world.find_children("*", "", true, false):
		if n.get("capture_radius") != null and n.get("pull_radius") != null and n is Node3D:
			(n as Node3D).visible = false
			n.set_process(false)
	var ship: Node3D = world.ship
	ship.controls_override = true
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 3000.0
	root.add_child(cam)
	for kind in CITIES:
		var item: Dictionary = {}
		for it in world.world_decor.items:
			if it.kind == kind:
				item = it
				break
		var city: Vector3 = (item.root as Node3D).global_position
		var up := city.normalized()
		var r: float = item.radius
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		var along := side.cross(up).normalized()
		var boat: Vector3 = world.ocean.surface_at(city + side * (r + 25.0))
		var b_up := boat.normalized()
		ship.heading = along.slide(b_up).normalized()
		ship.global_transform = Transform3D(Basis(ship.heading.cross(b_up).normalized(), b_up, -ship.heading), boat)
		for f in 90:
			for layer in world.find_children("*", "CanvasLayer", true, false):
				layer.visible = false
			cam.make_current()
			var b: Vector3 = ship.global_position
			cam.look_at_from_position(b + side * 34.0 + b_up * 11.0 - along * 14.0, city + up * (float(item.tall) * 0.3), b_up)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/Videos/Cidades/escala_%s.jpg" % kind), 0.9)
		print("CITY %s raio=%.0f m altura=%.0f m" % [kind, r, float(item.tall)])
	quit()
