extends SceneTree

## Miniaturas de GLBs (fundo escuro, luz neutra), para comparar com referências.
## Uso: Godot.exe --path . --resolution 512x512 --script res://Tests/glb_thumbs.gd -- <saída> <res://a.glb> ...

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.13, 0.14)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	for path in args.slice(1):
		var node: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(node)
		var box := AABB()
		var first := true
		for m in node.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		var c := box.get_center()
		var r := box.size.length() * 0.5
		cam.look_at_from_position(c + Vector3(0.8, 0.45, 1.0).normalized() * r * 2.3, c, Vector3.UP)
		for f in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg("%s/%s.jpg" % [out, path.get_file().get_basename().substr(9, 22)], 0.9)
		node.queue_free()
		await process_frame
	quit()
