extends SceneTree

## Simula 30 min do movimento dos ciclones (Weather._move) e mede a menor distância de cada um
## às ilhas/rochas do mapa (WorldDecor) e às 5 ilhas. Antes um ciclone se escondia atrás de rochas.
## Uso: Godot.exe --path . --headless --script res://Tests/cyclone_clearance_probe.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await create_timer(1.0).timeout
	var weather: Node = world.weather
	var decor: Node = world.world_decor
	print("CLEARANCE open_sea=%d decor=%d" % [weather.open_sea.size(), decor.items.size()])
	var worst_decor := INF
	var worst_island := INF
	for step in 3600:
		weather._move(0.5)
		for c in weather.cyclones:
			var at: Vector3 = c.center * world.planet_radius
			for item in decor.items:
				worst_decor = minf(worst_decor, (item.root as Node3D).global_position.distance_to(at) - float(item.height))
			worst_island = minf(worst_island, weather._island_distance(c.center))
	print("CLEARANCE min_decor=%.1f m (minus model height) min_island=%.1f m" % [worst_decor, worst_island])
	quit()
