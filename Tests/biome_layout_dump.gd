extends SceneTree

## Confere as regras dos biomas (WorldDecor): para cada item, setor, distância da ilha principal
## mais próxima e da rota (já descontado o raio do modelo). Marca "!!" o que quebra a regra.
## Uso: Godot.exe --path . --headless --script res://Tests/biome_layout_dump.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await process_frame
	await process_frame
	var decor: Node = world.world_decor
	var names := ["N", "L", "S", "O"]
	var bad := 0
	for item in decor.items:
		var dir: Vector3 = item.dir
		var r: float = item.radius
		var island: float = decor._island_distance(dir) - r
		var route: float = decor._route_distance(dir) - r
		var flag := ""
		if island < decor.ISLAND_CLEARANCE - 1.0 or route < decor.ROUTE_CLEAR - 1.0:
			flag = " !!"
			bad += 1
		if item.kind != "spectral_lantern":
			print("ITEM %s %-28s lat=%6.1f lon=%6.1f ilha=%5d rota=%5d r=%4.1f%s" % [names[int(item.sector)], item.kind,
				decor._lat_of(dir), decor._lon_of(dir), int(island), int(route), r, flag])
	# Colisão: peças por modelo e o maior vão entre as duas maiores (canal navegável se > ~6 m).
	var done := {}
	for item in decor.items:
		if done.has(item.kind) or item.pieces.is_empty():
			continue
		done[item.kind] = true
		var hulls: Array = item.pieces.duplicate()
		hulls.sort_custom(func(a, b): return a.size() > b.size())
		var gap := 0.0
		if hulls.size() >= 2:
			gap = INF
			for p in hulls[0]:
				for q in hulls[1]:
					gap = minf(gap, (p as Vector2).distance_to(q))
		print("COLISAO %-28s pecas=%d vao_entre_as_maiores=%.1f m" % [item.kind, hulls.size(), gap])
	print("LAYOUT itens=%d quebrando_regra=%d" % [decor.items.size(), bad])
	quit()
