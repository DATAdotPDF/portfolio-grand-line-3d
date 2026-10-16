extends SceneTree

## Diagnóstico de material de um modelo do mapa (WorldDecor): fotografa o mesmo enquadramento com o
## material original, sem o mapa de normais e sem sombreamento (cor crua da textura).
## Uso: Godot.exe --path . --resolution 960x540 --script res://Tests/decor_material_probe.gd -- basalt_caldera

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var kind: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "basalt_caldera"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/MaterialProbe"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.graphics.set_mode("alto")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	var item: Dictionary = {}
	for it in world.world_decor.items:
		if it.kind == kind:
			item = it
			break
	var target: Node3D = item.root
	var up := target.global_position.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	world.ship.global_position = world.ocean.surface_at(target.global_position + side * 70.0)
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	var meshes := target.find_children("*", "MeshInstance3D", true, false)
	var mat := (meshes[0] as MeshInstance3D).get_active_material(0) as BaseMaterial3D
	print("MAT %s normal=%s albedo=%s tex=%s cull=%s" % [kind, mat.normal_enabled, mat.albedo_color, mat.albedo_texture, mat.cull_mode])
	for ps in target.find_children("*", "CPUParticles3D", true, false):
		var gp := ps as CPUParticles3D
		print("PARTICLES %s emitting=%s pos=%s local=%s visible=%s in_tree=%s amount=%d" % [gp.name, gp.emitting, target.to_local(gp.global_position).snapped(Vector3.ONE * 0.1), gp.position, gp.is_visible_in_tree(), gp.is_inside_tree(), gp.amount])
	var smoke_node := target.find_child("Smoke", true, false) as Node3D
	for mode in ["fumaca", "original", "sem_normal", "sem_luz"]:
		if mode == "sem_normal":
			mat.normal_enabled = false
		elif mode == "sem_luz":
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for f in 240:
			for layer in world.find_children("*", "CanvasLayer", true, false):
				layer.visible = false
			cam.make_current()
			if mode == "fumaca" and smoke_node:
				cam.look_at_from_position(smoke_node.global_position + side * 45.0 + up * 5.0, smoke_node.global_position + up * 8.0, up)
			else:
				cam.look_at_from_position(target.global_position + side.rotated(up, 0.6) * 170.0 + up * 40.0, target.global_position + up * 60.0, up)
			await process_frame
		for ps in target.find_children("*", "CPUParticles3D", true, false):
			var cp := ps as CPUParticles3D
			print("PARTICLES_AFTER %s emitting=%s aabb=%s scale=%s mesh=%s" % [cp.name, cp.emitting, cp.capture_aabb(), cp.global_basis.get_scale(), cp.mesh])
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/MaterialProbe/%s_%s.jpg" % [kind, mode]), 0.85)
	quit()
