extends SceneTree

## Mesma câmera e mesma luz: ilha antiga (Assets/Optimized/island_*.glb, 3 mapas do Meshy) ao lado
## da nova segmentada (Optimized/Islands/*_parts.glb, cor assada). Para conferir a qualidade.
## Uso: Godot.exe --path . --resolution 1600x800 --script res://Tests/island_quality_compare.gd

const NAMES := ["sobre", "experiencia", "formacao", "projetos", "contato"]
# [yaw graus, distância relativa, altura relativa] de um close em cada ilha.
const SHOTS := {"longe": [35.0, 1.6, 0.9], "perto": [35.0, 0.75, 0.45]}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1600, 800)
	var out := ProjectSettings.globalize_path("res://Builds/IslandVideo")
	DirAccess.make_dir_recursive_absolute(out)
	for n in NAMES:
		for shot in SHOTS:
			var images: Array[Image] = []
			for path in ["res://Assets/Optimized/island_%s.glb" % n, "res://Assets/Optimized/Islands/island_%s_parts.glb" % n]:
				images.append(await _render(path, SHOTS[shot]))
			var sheet := Image.create(1600, 800, false, Image.FORMAT_RGB8)
			sheet.blit_rect(images[0], Rect2i(400, 0, 800, 800), Vector2i(0, 0))
			sheet.blit_rect(images[1], Rect2i(400, 0, 800, 800), Vector2i(800, 0))
			sheet.save_jpg(out + "/compare_%s_%s.jpg" % [n, shot], 0.9)
			print("COMPARE ", n, " ", shot)
	quit()

func _render(path: String, shot: Array) -> Image:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.78, 0.92)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.environment.ambient_light_energy = 0.3
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	world.add_child(sun)
	var model := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(model)
	var box := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var size := box.size.length()
	var yaw := deg_to_rad(float(shot[0]))
	var target := box.get_center()
	var camera := Camera3D.new()
	camera.fov = 45.0
	world.add_child(camera)
	camera.look_at_from_position(target + Vector3(sin(yaw), 0, cos(yaw)) * size * float(shot[1]) + Vector3.UP * size * float(shot[2]), target)
	camera.make_current()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	world.queue_free()
	await process_frame
	return image
