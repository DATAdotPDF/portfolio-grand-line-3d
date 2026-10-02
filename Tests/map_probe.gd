extends SceneTree

## Para o vídeo: quanto girar o globo do mapa para ver o máximo de ilhas de uma vez.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await create_timer(1.0).timeout
	world.toggle_map()
	await create_timer(3.0).timeout
	for speed in [Vector2(9, 0), Vector2(-9, 0), Vector2(0, 9), Vector2(0, -9), Vector2(9, 6), Vector2(-9, 6)]:
		world.camera.overview_direction = world.ship.global_position.normalized()
		var best := 0
		var best_frame := 0
		for frame in range(240):
			world.camera.drag_orbit(speed)
			await process_frame
			var count := 0
			for marker in world.hud.map_markers:
				if marker.visible: count += 1
			if count > best:
				best = count
				best_frame = frame
		print("MAP_PROBE speed=", speed, " best=", best, " at frame ", best_frame)
	quit()
