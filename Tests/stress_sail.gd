extends SceneTree

## Teste de estabilidade (como apertar F5 e jogar): entra navegando e leva o barco perto de cada
## ilha e de um item de cada bioma, alguns segundos em cada, em tempo real. Imprime a memória.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/stress_sail.gd [-- low]  (low: nível Baixo, como no celular)

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func place(target: Vector3) -> void:
	var up := target.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var pos: Vector3 = world.ocean.surface_at(target + side * 80.0)
	var fwd := side.cross(pos.normalized()).normalized()
	world.ship.heading = fwd
	world.ship.global_transform = Transform3D(Basis(fwd.cross(pos.normalized()).normalized(), pos.normalized(), -fwd), pos)

func mem() -> String:
	return "%.0f MB static, %.0f MB video (tex %.0f, buf %.0f), %d fps, %d draws, %.1fk tris" % [OS.get_static_memory_usage() / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0]

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await create_timer(3.0).timeout
	print("STRESS intro ", mem())
	world._start_sailing()
	if "low" in OS.get_cmdline_user_args() and world.graphics:
		world.graphics.set_mode("baixo")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1.0, 0.2, 0.0)
	await create_timer(8.0).timeout
	print("STRESS sailing ", mem())
	for i in world.islands.size():
		place(world.islands[i].global_position)
		await create_timer(4.0).timeout
		print("STRESS island %d %s" % [i, mem()])
	var seen := {}
	for item in world.world_decor.items:
		var sector := str(item.get("sector", "?"))
		if seen.has(sector):
			continue
		seen[sector] = true
		place((item.root as Node3D).global_position)
		await create_timer(5.0).timeout
		print("STRESS sector %s %s %s" % [sector, item.kind, mem()])
	world.toggle_map()
	await create_timer(3.0).timeout
	world.toggle_map()
	world.select_time("night")
	await create_timer(5.0).timeout
	print("STRESS night ", mem())
	print("STRESS done")
	quit()
