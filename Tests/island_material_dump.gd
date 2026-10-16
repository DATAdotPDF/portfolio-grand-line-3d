extends SceneTree

## Diagnóstico: materiais reais das ilhas no jogo (peças animadas e paradas) e o ambiente do mundo.
## Uso: Godot.exe --path . --script res://Tests/island_material_dump.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await create_timer(2.0).timeout
	var env: Environment = null
	for node in world.find_children("*", "WorldEnvironment", true, false):
		env = (node as WorldEnvironment).environment
	if env == null and world.get_viewport().world_3d.environment:
		env = world.get_viewport().world_3d.environment
	if env:
		print("ENV tonemap=%d exposure=%.2f white=%.2f ambient_src=%d ambient_energy=%.2f sky_contrib=%.2f" % [env.tonemap_mode, env.tonemap_exposure, env.tonemap_white, env.ambient_light_source, env.ambient_light_energy, env.ambient_light_sky_contribution])
	for i in world.islands.size():
		var model: Node3D = world.islands[i].get_node("IslandModel")
		var seen := {}
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var animated: bool = mesh.get_parent() != model
			for s in mesh.mesh.get_surface_count():
				var mat: Material = mesh.get_active_material(s)
				var key := "%s|%s" % [mat.get_class() if mat else "null", animated]
				if seen.has(key): continue
				seen[key] = true
				var line := "ISLAND %d %s animated=%s mat=%s" % [i, mesh.name, animated, mat.get_class() if mat else "null"]
				if mat is StandardMaterial3D:
					var m := mat as StandardMaterial3D
					var tex := m.albedo_texture
					line += " albedo=%s metallic=%.2f rough=%.2f spec=%.2f vcol=%s tex=%s %s" % [m.albedo_color, m.metallic, m.roughness, m.metallic_specular, m.vertex_color_use_as_albedo, tex.get_size() if tex else "none", tex.resource_path.get_file() if tex else ""]
				elif mat is ShaderMaterial:
					line += " shader=%s" % (mat as ShaderMaterial).shader.resource_path.get_file()
				print(line)
	quit()
