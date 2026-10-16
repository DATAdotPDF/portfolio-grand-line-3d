extends SceneTree

## Vídeo da bandeira do cemitério de navios (ship_graveyard, Sul): barco parado perto, câmera de lado
## olhando o mastro com a bandeira (perto) e depois a câmera do jogo (de longe).
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie X.avi
##      --script res://Tests/flag_video.gd -- [ship_graveyard|stilt_lookout_post]

var world: Node3D
var kind := "ship_graveyard"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		kind = args[0]
	call_deferred("run")

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.hud._set_carta_open(false)
	world.graphics.set_mode("alto")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	var item: Dictionary = {}
	for it in world.world_decor.items:
		if it.kind == kind:
			item = it
	if item.is_empty():
		print("FLAG_MISSING")
		quit()
		return
	var model: Node3D = item.model
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var flag_at: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Flag2")).origin
	var dir: Vector3 = item.dir
	var up := dir
	var basis: Basis = (item.root as Node3D).global_basis
	var side := basis.x.slide(up).normalized()
	# Barco a ~90 m do cemitério, de proa para ele.
	var ship_at: Vector3 = dir * world.planet_radius + side * 90.0
	var surface: Vector3 = world.ocean.surface_at(ship_at)
	var n := surface.normalized()
	var fwd: Vector3 = (dir * world.planet_radius - ship_at).slide(n).normalized()
	world.ship.heading = fwd
	world.ship.global_transform = Transform3D(Basis(fwd.cross(n).normalized(), n, -fwd), surface)
	var camera := Camera3D.new()
	camera.far = 3000.0
	camera.fov = 45.0
	root.add_child(camera)
	await create_timer(1.5).timeout
	print("FLAG_START %.3f" % (Engine.get_process_frames() / 30.0))
	for i in 10 * 30:
		for layer in world.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		camera.make_current()
		var near := 9.0 if kind == "stilt_lookout_post" else 28.0
		camera.look_at_from_position(flag_at + side * near + up * near * 0.07 - basis.z * near * 0.2, flag_at, up)
		await process_frame
	# Câmera do jogo, de longe.
	camera.current = false
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = true
	for i in 8 * 30:
		await process_frame
	quit()
