extends SceneTree

## Raycast a partir de pixels de uma vista fixa da ilha (mesma câmera de
## island_markers.gd) até a superfície real do modelo. Imprime o ponto em
## coordenadas normalizadas do AABB e a normal — usado para posicionar janelas
## acesas, chaminé, fogueiras etc. exatamente sobre a geometria.
## Uso: Godot.exe --path . --script res://Tests/island_probe.gd -- island=0 face=z+ zoom=1 px=600:425,636:425

const FILES := ["island_sobre", "island_experiencia", "island_formacao", "island_projetos", "island_contato"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var island := 0
	var face := "z+"
	var zoom := 1.0
	var pixels: Array[Vector2] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("island="): island = int(arg.trim_prefix("island="))
		if arg.begins_with("face="): face = arg.trim_prefix("face=")
		if arg.begins_with("zoom="): zoom = float(arg.trim_prefix("zoom="))
		if arg.begins_with("px="):
			for pair in arg.trim_prefix("px=").split(","):
				var xy := pair.split(":")
				pixels.append(Vector2(float(xy[0]), float(xy[1])))
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
		mesh.create_trimesh_collision()
	# Meshy mistura a ordem dos vértices: colisão de dois lados para o raycast não 'atravessar'.
	for shape_node in model.find_children("*", "CollisionShape3D", true, false):
		(shape_node.shape as ConcavePolygonShape3D).backface_collision = true
	var axis: Vector3 = {"z+": Vector3(0, 0, 1), "z-": Vector3(0, 0, -1), "x+": Vector3(1, 0, 0), "x-": Vector3(-1, 0, 0), "y+": Vector3(0, 1, 0)}[face]
	var camera := Camera3D.new()
	world.add_child(camera)
	var center := bounds.get_center()
	camera.position = center + axis * 3.2 / zoom + (Vector3(0, 0.6 / zoom, 0) if face != "y+" else Vector3(0, 0, 0.01))
	camera.look_at(center, Vector3.UP if face != "y+" else Vector3.FORWARD)
	camera.fov = 40
	for i in range(4):
		await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	# Interseção direta raio-triângulo (exata; a física do Jolt falhava em partes do modelo).
	var faces := PackedVector3Array()
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = mesh.global_transform
		for v in mesh.mesh.get_faces():
			faces.append(xf * v)
	for i in range(pixels.size()):
		var px := pixels[i]
		# Raio calculado à mão a partir do FOV (project_ray_* divergia do tamanho da imagem salva).
		var size := Vector2(image.get_width(), image.get_height())
		var ndc := Vector2(px.x / size.x * 2.0 - 1.0, 1.0 - px.y / size.y * 2.0)
		var tan_half := tan(deg_to_rad(camera.fov) * 0.5)
		var origin := camera.global_position
		var dir := (camera.global_basis * Vector3(ndc.x * tan_half * size.x / size.y, ndc.y * tan_half, -1.0)).normalized()
		var hit := {}
		var best := INF
		for f in range(0, faces.size(), 3):
			var r: Variant = Geometry3D.ray_intersects_triangle(origin, dir, faces[f], faces[f + 1], faces[f + 2])
			if r != null:
				var d: float = (r as Vector3).distance_to(origin)
				if d < best:
					best = d
					hit = {"position": r, "normal": (faces[f + 1] - faces[f]).cross(faces[f + 2] - faces[f]).normalized()}
		if hit.is_empty():
			print("PROBE ", i, " px=", px, " miss")
			continue
		var n: Vector3 = (hit.position - bounds.position) / bounds.size
		print("PROBE %d px=%s norm=Vector3(%.3f, %.3f, %.3f) normal=Vector3(%.2f, %.2f, %.2f)" % [i, px, n.x, n.y, n.z, hit.normal.x, hit.normal.y, hit.normal.z])
		for dx in range(-5, 6):
			for dy in range(-5, 6):
				if absi(dx) == 5 or absi(dy) == 5:
					image.set_pixel(clampi(int(px.x) + dx, 0, 1279), clampi(int(px.y) + dy, 0, 959), Color(1, 0, 1))
	image.save_png(ProjectSettings.globalize_path("res://Documentation/Previews/probe_%d_%s.png" % [island, face]))
	quit()
