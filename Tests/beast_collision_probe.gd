extends SceneTree

## Colisão dos colossos contra o modelo: para cada direção (de 15 em 15°) compara o raio do corpo na
## linha d'água (vértices do modelo na faixa da água) com o raio onde a colisão do barco começa.
## Uso: Godot.exe --path . --headless --script res://Tests/beast_collision_probe.gd

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	for beast in world.sea_beasts.beasts:
		if beast.name == "abyssal_behemoth":
			await _probe("caranguejo", beast.root, beast.model)
	var turtle: Dictionary = world.world_decor.turtle
	if not turtle.is_empty():
		var item: Dictionary = turtle.item
		await _probe("tartaruga", item.root, null, item)
	quit()

func _probe(label: String, node: Node3D, model: Node3D, item := {}) -> void:
	# O barco perto (modelos carregam pela distância), tudo parado no lugar.
	var up := node.global_position.normalized()
	var side := node.global_transform.basis.x.slide(up).normalized()
	world.ship.global_transform = Transform3D(world.ship.global_transform.basis, world.ocean.surface_at(node.global_position + side * 260.0))
	for i in 40:
		await process_frame
		if model == null and item.get("model") != null:
			break
		await create_timer(0.25).timeout
	if model == null:
		model = item.get("model")
	if model == null:
		print("COLLISION %s: modelo não carregou" % label)
		return
	world.sea_beasts.set_process(false)
	world.world_decor.set_process(false)
	await physics_frame
	await physics_frame
	var basis := Basis.looking_at(node.global_transform.basis.z.slide(up).normalized() * -1.0, up)
	var water: float = world.ocean.surface_at(node.global_position).length()
	# Vértices do modelo (pose de repouso) perto da água.
	var verts: Array[Vector3] = []
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var pts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for k in range(0, pts.size(), 3):
				verts.append(mi.global_transform * pts[k])
	var visual := []
	var hit := []
	var space := world.get_world_3d().direct_space_state
	for step in 24:
		var a := TAU * step / 24.0
		var dir := (basis.x * cos(a) + basis.z * sin(a)).normalized()
		var best := 0.0
		for v in verts:
			var h := v.length() - water
			if h < -1.5 or h > 4.0:
				continue
			var flat := (v - node.global_position).slide(up)
			if flat.length() < 0.5:
				continue
			if flat.normalized().dot(dir) > cos(deg_to_rad(7.5)):
				best = maxf(best, flat.length())
		visual.append(int(best))
		var reach := 0.0
		var r := 260.0
		while r > 0.0:
			var q := PhysicsPointQueryParameters3D.new()
			q.position = (node.global_position + dir * r).normalized() * (water + 1.0)
			q.collision_mask = 1
			q.collide_with_bodies = true
			var found := space.intersect_point(q, 4)
			var real := found.filter(func(f: Dictionary) -> bool: return f.collider != world.ship)
			if not real.is_empty():
				reach = r
				break
			r -= 1.0
		hit.append(int(reach))
	print("COLLISION %s visual(m)  %s" % [label, visual])
	print("COLLISION %s colisão(m) %s" % [label, hit])
	world.sea_beasts.set_process(true)
	world.world_decor.set_process(true)
