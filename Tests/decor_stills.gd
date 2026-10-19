extends SceneTree

## Prints dos modelos do mapa (WorldDecor), de dia ou à noite, gráficos no Alto, sem HUD: um
## enquadramento de 3/4 por modelo (primeiro exemplar), barco parado perto (animações ativas).
## "mar": câmera rente à água (~2,5 m), para conferir a linha d'água de cada um.
## "longe=<m>": câmera a essa distância do modelo (ex.: runas à noite vistas do mar).
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/decor_stills.gd -- noite [mar] [longe=280] [tipo ...]
## Saída: Builds/DecorStills/<dia|noite>[_mar]_<tipo>.jpg

var world: Node3D
var decor: Node3D
var camera: Camera3D
var sea_level := false
var far_distance := 0.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var night := args.size() > 0 and args[0] == "noite"
	var sea := "mar" in args
	for a in args:
		if a.begins_with("longe="):
			far_distance = float(a.trim_prefix("longe="))
	var kinds: Array = Array(args.slice(1)).filter(func(a): return a != "mar" and not a.begins_with("longe=")) if args.size() > 1 else []
	sea_level = sea
	var out := "res://Builds/DecorStills"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("night" if night else "day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.graphics.set_mode("alto")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	world.ghost_ship.timer = 9999.0
	decor = world.world_decor
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 50.0
	root.add_child(camera)
	var seen := {}
	for item in decor.items:
		if seen.has(item.kind) or (not kinds.is_empty() and item.kind not in kinds):
			continue
		seen[item.kind] = true
		# Só os fixos interessam no nível do mar (boias e caixas boiam na onda).
		if sea_level and (item.float or float(item.hover) > 0.0):
			continue
		await _shot(item, "%s/%s%s_%s.jpg" % [out, "noite" if night else "dia", "_mar" if sea_level else "", item.kind])
	quit()

func _shot(item: Dictionary, path: String) -> void:
	var target: Node3D = item.root
	var up := target.global_position.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var pos: Vector3 = world.ocean.surface_at(target.global_position + side * 60.0)
	var u := pos.normalized()
	var fwd := u.cross(side).normalized()
	world.ship.heading = fwd
	world.ship.global_transform = Transform3D(Basis(fwd.cross(u).normalized(), u, -fwd), pos)
	world.ship.drive_speed = 0.0
	var box := AABB()
	var first := true
	for mesh in target.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null or mi.mesh is QuadMesh or mi.name.begins_with("Lava") or mi.name == "BoilingWater":
			continue
		var b: AABB = target.global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var width := maxf(box.size.x, box.size.z)
	var tall := box.end.y
	var dist := far_distance if far_distance > 0.0 else maxf(maxf(width, tall) * 1.35, 9.0)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2200:
		for layer in world.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		var center := target.global_position
		var c_up := center.normalized()
		camera.make_current()
		if sea_level:
			var eye_pos: Vector3 = center + side.rotated(c_up, 0.7) * maxf(width * 1.1, 14.0)
			eye_pos = world.ocean.surface_at(eye_pos) + c_up * 2.5
			camera.look_at_from_position(eye_pos, center + c_up * minf(tall * 0.15, 4.0), c_up)
		else:
			camera.look_at_from_position(center + side.rotated(c_up, 0.7) * dist + c_up * (tall * 0.35 + 3.0), center + c_up * tall * 0.42, c_up)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path(path), 0.88)
	print("PRINT ", path.get_file())
