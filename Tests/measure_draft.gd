extends SceneTree

## Mede a linha d'água real da chalupa: fundo da quilha e convés (AABB do modelo
## no espaço do barco) contra a altura da água sob o barco, ao longo de 12 s.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await create_timer(1.0).timeout
	var ship: Node3D = world.ship
	var model: Node3D = world.sail_model
	var inv: Transform3D = ship.float_visual.global_transform.affine_inverse()
	var lo := INF
	var hi := -INF
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = inv * mesh.global_transform
		for v in mesh.mesh.get_faces():
			var y: float = (xf * v).y
			lo = minf(lo, y)
			hi = maxf(hi, y)
	print("HULL keel=%.2f top=%.2f (local, relativo ao centro do barco)" % [lo, hi])
	var samples := []
	for i in range(24):
		await create_timer(0.5).timeout
		var water: float = world.ocean.height_at(ship.global_position) + world.ocean.radius
		var center := ship.global_position.length()
		samples.append(center - water)
	var avg := 0.0
	for s in samples:
		avg += s
	avg /= samples.size()
	print("CENTER_MINUS_WATER avg=%.2f min=%.2f max=%.2f" % [avg, samples.min(), samples.max()])
	quit()
