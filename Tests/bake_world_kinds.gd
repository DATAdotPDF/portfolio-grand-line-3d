extends SceneTree

## Mede todos os modelos da decoração (caixa, contorno de colisão, "Idle") e o pacote de cada um, e
## grava Config/world_kinds.json (WorldDecor.KIND_CACHE). Rodado pelo Web/build_variant.ps1 antes do
## export: no site, os modelos dos setores chegam depois e a disposição sai destas medidas.
## Também imprime a disposição (DECOR_ITEM) para comparar com a do site (-- dump).
## Uso: Godot.exe --headless --path . --script res://Tests/bake_world_kinds.gd [-- dump]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await process_frame
	var decor: Node = world.world_decor
	if "dump" in OS.get_cmdline_user_args():
		for item in decor.items:
			var d: Vector3 = item.dir
			print("DECOR_ITEM %s %.4f %.4f %.4f %.3f" % [item.kind, d.x, d.y, d.z, float(item.yaw)])
		print("DECOR_PENDING %d" % decor.pending.size())
	else:
		var changed: bool = decor.save_kind_cache()
		var data: Dictionary = decor.kind_cache_data()
		var per := {}
		for kind in data.kinds:
			var pack: String = data.kinds[kind].pack
			per[pack] = int(per.get(pack, 0)) + 1
		print("BAKE %d modelos, pacotes %s, %s" % [data.kinds.size(), per, "gravado" if changed else "sem mudança"])
	quit()
