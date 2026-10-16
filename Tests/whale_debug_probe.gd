extends SceneTree

## Diagnóstico: estado de um grupo de silhuetas (posição relativa ao barco e opacidade) por segundo.
## Uso: Godot.exe --path . --headless --script res://Tests/whale_debug_probe.gd -- jubarte

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var species := "jubarte"
	if not OS.get_cmdline_user_args().is_empty():
		species = OS.get_cmdline_user_args()[0]
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await create_timer(1.5).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1, 0, 0)
	var p: Vector3 = world.weather.open_sea[world.weather.open_sea.size() / 3]
	world.ship.global_position = world.ocean.surface_at(p * world.planet_radius)
	world.ship.heading = Vector3.FORWARD.slide(p).normalized()
	await create_timer(3.0).timeout
	var shadows: Node = world.sea_life.sea_shadows
	var g: Dictionary = shadows.spawn(species)
	for i in 30:
		await create_timer(1.0).timeout
		if not shadows.groups.has(g):
			print("DBG gone at ", i)
			break
		var m: Dictionary = g.members[0]
		var rel: Vector3 = (m.pos as Vector3) - world.ship.global_position
		var fwd: Vector3 = world.ship.heading
		var mat: ShaderMaterial = m.plate[1]
		print("DBG t=%d along=%.1f side=%.1f opacity=%.2f leaving=%.1f speed=%.1f ship=%.1f" % [i, rel.dot(fwd), rel.dot(fwd.cross(world.ship.global_position.normalized())), float(mat.get_shader_parameter("opacity")), float(g.leaving), float(g.speed), world.ship.measured_speed])
	quit()
