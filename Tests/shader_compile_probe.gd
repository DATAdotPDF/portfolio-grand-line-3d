extends SceneTree

## Tempo de compilação de cada shader (desenha um quadro com só ele na tela).
## Uso: Godot.exe --path . --resolution 640x360 --script res://Tests/shader_compile_probe.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 0, 3)
	var results: Array = []
	var dir := DirAccess.open("res://Shaders")
	for f in dir.get_files():
		if not f.ends_with(".gdshader"):
			continue
		var shader: Shader = load("res://Shaders/" + f)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var node: Node
		if shader.get_mode() == Shader.MODE_SPATIAL:
			var mi := MeshInstance3D.new()
			mi.mesh = QuadMesh.new()
			mi.material_override = mat
			node = mi
		elif shader.get_mode() == Shader.MODE_CANVAS_ITEM:
			var cr := ColorRect.new()
			cr.size = Vector2(64, 64)
			cr.material = mat
			node = cr
		else:
			continue
		root.add_child(node)
		var t0 := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		results.append([(Time.get_ticks_usec() - t0) / 1000.0, f])
		node.queue_free()
		await process_frame
	results.sort_custom(func(a, b): return a[0] > b[0])
	for r in results:
		print("COMPILE %7.0f ms  %s" % [r[0], r[1]])
	quit()
