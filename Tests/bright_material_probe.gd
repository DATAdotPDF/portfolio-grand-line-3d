extends SceneTree

## Por que alguns modelos ficam quase brancos: materiais (metal/rugosidade/especular) da tartaruga e
## da baleia colosso + névoa e tonemap do mundo, e prints de perto e de longe.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/bright_material_probe.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	var env: Environment = world.get_viewport().world_3d.environment
	for node in world.find_children("*", "WorldEnvironment", true, false):
		env = (node as WorldEnvironment).environment
	print("ENV tonemap=%d exposure=%.2f fog=%s density=%.4f aerial=%.2f sun_scatter=%.2f fog_color=%s ambient=%.2f" % [env.tonemap_mode, env.tonemap_exposure, env.fog_enabled, env.fog_density, env.fog_aerial_perspective, env.fog_sun_scatter, env.fog_light_color, env.ambient_light_energy])
	for item in world.world_decor.items:
		if not (str(item.kind) in ["turtle_island", "timber_whale"]):
			continue
		for mesh in (item.root as Node3D).find_children("*", "MeshInstance3D", true, false):
			for s in mesh.mesh.get_surface_count():
				var m: Material = mesh.get_active_material(s)
				if m is StandardMaterial3D:
					var sm := m as StandardMaterial3D
					print("MAT %s metallic=%.2f metal_tex=%s rough=%.2f rough_tex=%s spec=%.2f albedo=%s normal=%s fog_off=%s shading=%d" % [item.kind, sm.metallic, sm.metallic_texture != null, sm.roughness, sm.roughness_texture != null, sm.metallic_specular, sm.albedo_color, sm.normal_enabled, sm.disable_fog, sm.shading_mode])
				else:
					print("MAT %s %s" % [item.kind, m.get_class() if m else "null"])
		break
	quit()
