extends SceneTree

## Diagnóstico dos modelos do WorldDecor: transparência, cull, profundidade e triângulos de cada um.
## Uso: Godot.exe --path . --headless --script res://Tests/decor_material_dump.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var dir := "res://Assets/Optimized/World/"
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".glb"): continue
		var model := (load(dir + file) as PackedScene).instantiate() as Node3D
		root.add_child(model)
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = mesh.mesh
			var tris := 0
			for s in m.get_surface_count():
				var idx: PackedInt32Array = m.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
				tris += idx.size() / 3 if idx.size() > 0 else (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				var mat: Material = mesh.get_active_material(s)
				var line := "DECOR %s surf=%d tris=%d" % [file, s, tris]
				if mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					line += " transparency=%d cull=%d depth=%d alpha=%.2f scissor=%.2f vcol=%s tex=%s" % [sm.transparency, sm.cull_mode, sm.depth_draw_mode, sm.albedo_color.a, sm.alpha_scissor_threshold, sm.vertex_color_use_as_albedo, sm.albedo_texture.get_size() if sm.albedo_texture else "none"]
				else:
					line += " mat=%s" % (mat.get_class() if mat else "null")
				print(line)
		model.queue_free()
	quit()
