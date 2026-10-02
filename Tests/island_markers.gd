extends SceneTree

## Renderiza uma ilha isolada com uma grade de marcadores (coordenadas normalizadas
## do AABB) para posicionar luzes, fumaça etc. sem chute.
## Uso: Godot.exe --path . --script res://Tests/island_markers.gd -- island=0 face=z+

const FILES := ["island_sobre", "island_experiencia", "island_formacao", "island_projetos", "island_contato"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var island := 0
	var face := "z+"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("island="): island = int(arg.trim_prefix("island="))
		if arg.begins_with("face="): face = arg.trim_prefix("face=")
	root.size = Vector2i(1280, 960)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.7, 0.8, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var model := (load("res://Assets/Optimized/%s.glb" % FILES[island]) as PackedScene).instantiate() as Node3D
	world.add_child(model)
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	var axis: Vector3 = {"z+": Vector3(0, 0, 1), "z-": Vector3(0, 0, -1), "x+": Vector3(1, 0, 0), "x-": Vector3(-1, 0, 0), "y+": Vector3(0, 1, 0)}[face]
	var camera := Camera3D.new()
	world.add_child(camera)
	var center := bounds.get_center()
	camera.position = center + axis * 3.2 + (Vector3(0, 0.6, 0) if face != "y+" else Vector3(0, 0, 0.01))
	camera.look_at(center, Vector3.UP if face != "y+" else Vector3.FORWARD)
	camera.fov = 40
	var steps := [0.15, 0.3, 0.45, 0.6, 0.75, 0.9]
	for a in steps:
		for b in steps:
			var f := Vector3.ZERO
			# Grade no plano da face, na frente do modelo (coordenada da face = 0.92 ou 0.08).
			match face:
				"z+": f = Vector3(a, b, 0.92)
				"z-": f = Vector3(a, b, 0.08)
				"x+": f = Vector3(0.92, b, a)
				"x-": f = Vector3(0.08, b, a)
				"y+": f = Vector3(a, 0.95, b)
			var label := Label3D.new()
			label.text = "%.2f,%.2f,%.2f" % [f.x, f.y, f.z]
			label.font_size = 18
			label.pixel_size = 0.0018
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.modulate = Color(1, 0.1, 0.1)
			label.outline_size = 6
			label.position = bounds.position + bounds.size * f
			world.add_child(label)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://Documentation/Previews/markers_%d_%s.png" % [island, face])
	root.get_texture().get_image().save_png(path)
	print("MARKERS ", path)
	quit()
