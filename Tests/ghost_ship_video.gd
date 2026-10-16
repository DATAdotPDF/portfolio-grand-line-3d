extends SceneTree

## Vídeo do navio fantasma navegando (noite): câmera de lado e um pouco à frente, para conferir que a
## proa aponta para onde ele anda. Depois de uns segundos ele persegue o barco (câmera do jogo).
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie X.avi
##      --script res://Tests/ghost_ship_video.gd

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("night")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.hud._set_carta_open(false)
	world.graphics.set_mode("alto")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(0.6, 0.0, 0.0)
	# Barco no Mar Sombrio (bioma do navio fantasma), num ponto de mar livre.
	var points: Array = world.world_decor.ghost_points
	var start_at: Vector3 = (points[points.size() / 2] as Vector3) * world.planet_radius
	var surface: Vector3 = world.ocean.surface_at(start_at)
	var n := surface.normalized()
	var fwd := Vector3.FORWARD.slide(n).normalized()
	world.ship.heading = fwd
	world.ship.global_transform = Transform3D(Basis(fwd.cross(n).normalized(), n, -fwd), surface)
	await create_timer(0.5).timeout
	var ghost: Node3D = world.ghost_ship
	ghost.vanish_distance = 0.0
	ghost.chase_distance = 0.0
	if not ghost.spawn(true):
		print("GHOST_NO_SPAWN")
		quit()
		return
	var camera := Camera3D.new()
	camera.far = 3000.0
	camera.fov = 55.0
	root.add_child(camera)
	await create_timer(1.0).timeout
	print("GHOST_START %.3f" % (Engine.get_process_frames() / 30.0))
	for i in 14 * 30:
		for layer in world.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		var at := ghost.global_position
		var up := at.normalized()
		var heading: Vector3 = (ghost.heading as Vector3).slide(up).normalized()
		var side := heading.cross(up).normalized()
		camera.make_current()
		camera.look_at_from_position(at + side * 30.0 + heading * 14.0 + up * 7.0, at + up * 3.0, up)
		await process_frame
	quit()
