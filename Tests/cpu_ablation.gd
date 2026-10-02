extends SceneTree

## Onde vai o tempo de CPU? Mede process/physics médios com o mundo rodando e
## depois desliga um filho do mundo (ou autoload) por vez e mede de novo.

func _initialize() -> void:
	call_deferred("run")

func sample(seconds: float) -> Vector2:
	var total := Vector2.ZERO
	var frames := 0
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		total += Vector2(Performance.get_monitor(Performance.TIME_PROCESS), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		frames += 1
	return total / maxf(1.0, frames)

func run() -> void:
	var world := (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await create_timer(3.0).timeout
	if world.has_method("_start_sailing"):
		world._start_sailing()
	await create_timer(1.0).timeout
	var base: Vector2 = await sample(3.0)
	print("BASE process=%.2f ms physics=%.2f ms" % [base.x, base.y])
	var targets: Array[Node] = []
	targets.append_array(world.get_children())
	for child in root.get_children():
		if child != world:
			targets.append(child)
	var results := []
	for node in targets:
		var before := node.process_mode
		node.process_mode = Node.PROCESS_MODE_DISABLED
		await create_timer(0.3).timeout
		var t: Vector2 = await sample(1.5)
		node.process_mode = before
		results.append([base.x - t.x, base.y - t.y, node.name])
	results.sort_custom(func(a, b): return a[0] + a[1] > b[0] + b[1])
	for r in results.slice(0, 15):
		print("SAVES process=%6.2f physics=%6.2f  %s" % [r[0], r[1], r[2]])
	quit()
