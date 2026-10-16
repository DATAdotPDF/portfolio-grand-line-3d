extends SceneTree

## Flare do sol: câmera no barco olhando o sol ao meio-dia e perto do poente; imprime se o flare
## está ligado, a força e a cor do disco do sol na tela (o shader só acende com o disco quase branco).
## Uso: Godot.exe --path . --script res://Tests/flare_probe.gd -- [--out=<pasta>] [low]
##   ou, num build exportado: Godot.exe --main-pack index.pck --script <abs>/Tests/flare_probe.gd -- --out=<pasta>

var world: Node3D
var out_dir := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	call_deferred("run")

func probe(label: String, cam: Camera3D) -> void:
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var flare := world.get_node_or_null("SunFlare")
	var image := root.get_texture().get_image()
	var to_sun: Vector3 = world.clock.sun_direction
	var px := cam.unproject_position(cam.global_position + to_sun * 2000.0)
	var c := Color.BLACK
	if Rect2(Vector2.ZERO, Vector2(image.get_size())).has_point(px):
		c = image.get_pixelv(Vector2i(px))
	var mat: ShaderMaterial = flare.material if flare else null
	print("FLARE %s visivel=%s forca=%.2f disco=(%.2f, %.2f, %.2f) menor_canal=%.2f tier=%s" % [label,
		flare.rect.visible if flare else false, float(mat.get_shader_parameter("strength")) if mat else -1.0,
		c.r, c.g, c.b, minf(c.r, minf(c.g, c.b)), world.graphics.tier if world.get("graphics") else -1])
	if flare:
		var eye := cam.global_position
		var space := cam.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(eye, eye + to_sun * 900.0)
		var hit := space.intersect_ray(q)
		print("FLARE   raio=%s cobertura_nuvem=%.2f" % [str(hit.collider.get_path()) + " a %.0f m" % eye.distance_to(hit.position) if not hit.is_empty() else "livre", flare._cloud_cover(eye, to_sun)])
	if not out_dir.is_empty():
		image.save_jpg(out_dir.path_join("flare_%s.jpg" % label), 0.88)

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	await create_timer(1.5).timeout
	world._start_sailing()
	if "low" in OS.get_cmdline_user_args() and world.graphics:
		world.graphics.set_mode("baixo")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.make_current()
	for label in ["dia", "tarde"]:
		world.select_time("day")
		if label == "tarde" and world.clock.has_method("set_time"):
			world.clock.set_time(17.0)
		await create_timer(0.5).timeout
		var up: Vector3 = world.ship.global_position.normalized()
		var eye: Vector3 = world.ship.global_position + up * 6.0
		var to_sun: Vector3 = world.clock.sun_direction
		cam.look_at_from_position(eye, eye + to_sun * 100.0, up if absf(up.dot(to_sun)) < 0.98 else Vector3.FORWARD)
		await probe(label, cam)
	quit()
