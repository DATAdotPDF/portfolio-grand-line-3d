extends SceneTree

## Foto de cima (ortográfica) do caranguejo e da tartaruga com as formas de colisão desenhadas.
## Uso: Godot.exe --path . --resolution 1200x1200 --script res://Tests/beast_collision_shots.gd -- [--out=<pasta>]

var world: Node3D
var out_dir := "res://Builds/CollisionShots"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	call_deferred("run")

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	for beast in world.sea_beasts.beasts:
		if beast.name == "abyssal_behemoth":
			await _shot("caranguejo", beast.root, 300.0)
	if not world.world_decor.turtle.is_empty():
		await _shot("tartaruga", world.world_decor.turtle.item.root, 300.0)
	quit()

func _shot(label: String, node: Node3D, span: float) -> void:
	var up := node.global_position.normalized()
	world.ship.global_transform = Transform3D(world.ship.global_transform.basis, world.ocean.surface_at(node.global_position + node.global_transform.basis.x.slide(up).normalized() * 240.0))
	await create_timer(4.0).timeout
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = span
	cam.far = 2000.0
	root.add_child(cam)
	var fwd := node.global_transform.basis.z.slide(up).normalized()
	cam.look_at_from_position(node.global_position + up * 400.0, node.global_position, fwd)
	cam.make_current()
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var clouds: Node = world.find_child("SkyClouds", true, false)
	if clouds is Node3D:
		(clouds as Node3D).visible = false
	world.sea_beasts.set_process(false)
	world.world_decor.set_process(false)
	await physics_frame
	await physics_frame
	# Borda da colisão (onde o barco começa a bater) em pontos vermelhos, por cima de tudo.
	var marker := StandardMaterial3D.new()
	marker.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.albedo_color = Color(1, 0.1, 0.1)
	marker.no_depth_test = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 3.0
	box.material = marker
	var space := world.get_world_3d().direct_space_state
	var water: float = world.ocean.surface_at(node.global_position).length()
	var side := node.global_transform.basis.x.slide(up).normalized()
	var dots: Array[Node] = []
	for step in 144:
		var dir := side.rotated(up, TAU * step / 144.0)
		var r := 200.0
		while r > 0.0:
			var q := PhysicsPointQueryParameters3D.new()
			q.position = (node.global_position + dir * r).normalized() * (water + 1.0)
			q.collision_mask = 1
			if not space.intersect_point(q, 4).filter(func(f: Dictionary) -> bool: return f.collider != world.ship).is_empty():
				var dot := MeshInstance3D.new()
				dot.mesh = box
				root.add_child(dot)
				dot.global_position = q.position + up * 3.0
				dots.append(dot)
				break
			r -= 1.0
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var dir := out_dir if not out_dir.begins_with("res://") else ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_jpg(dir.path_join(label + ".jpg"), 0.9)
	print("COLLISION_SHOT ", label)
	cam.queue_free()
	for dot in dots:
		dot.queue_free()
	world.sea_beasts.set_process(true)
	world.world_decor.set_process(true)
