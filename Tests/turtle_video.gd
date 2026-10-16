extends SceneTree

## Vídeo da tartaruga gigante modular (Tools/turtle_assemble_blender.py) nadando no Oeste, gráficos no
## Alto: lado (perto), frente e câmera do jogo (barco parado perto dela).
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie X.avi
##      --script res://Tests/turtle_video.gd -- <lado|frente|proa|jogo>

var world: Node3D
var camera: Camera3D
var view := "lado"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		view = args[0]
	call_deferred("run")

func park_ship(at: Vector3, heading: Vector3) -> void:
	var ship: Node3D = world.ship
	var surface: Vector3 = world.ocean.surface_at(at)
	var up := surface.normalized()
	var forward := heading.slide(up).normalized()
	ship.heading = forward
	ship.global_transform = Transform3D(Basis(forward.cross(up).normalized(), up, -forward), surface)
	ship.drive_speed = 0.0

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
	world.sea_life.sea_shadows.timer = 9999.0
	world.sea_life.dolphin_timer = 9999.0
	var decor: Node = world.world_decor
	var turtle: Node3D = (decor.turtle.item as Dictionary).root
	# Distâncias acertadas com a tartaruga de 80 m: crescem junto com ela.
	var k: float = float(decor.MODELS["turtle_island"][1]) / 80.0
	var up := turtle.global_position.normalized()
	var forward := -turtle.global_basis.z.slide(up).normalized()
	var right := forward.cross(up).normalized()
	# Barco ao lado, de proa para a tartaruga (na câmera do jogo ela aparece na frente do barco).
	var ship_at: Vector3 = turtle.global_position - forward * 40.0 * k + right * 90.0 * k
	park_ship(ship_at, (turtle.global_position - ship_at).slide(ship_at.normalized()))
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 50.0
	root.add_child(camera)
	await create_timer(2.0).timeout
	print("TURTLE_START %.3f" % (Engine.get_process_frames() / 30.0))
	for i in 16 * 30:
		var center := turtle.global_position
		up = center.normalized()
		forward = -turtle.global_basis.z.slide(up).normalized()
		right = forward.cross(up).normalized()
		if view != "jogo":
			for layer in world.find_children("*", "CanvasLayer", true, false):
				layer.visible = false
			var from: Vector3 = center + (right * 62.0 + up * 6.0 if view == "lado" else forward * 70.0 + up * 10.0 + right * 8.0) * k
			var look: Vector3 = center + up * 4.0 * k
			if view == "proa":
				# Rente à água, na frente e de lado do casco: lâmina d'água da proa e borrifos.
				from = center + (forward * 38.0 + right * 34.0 + up * 3.0) * k
				look = center + (forward * 8.0 + up * 1.0) * k
			camera.make_current()
			camera.look_at_from_position(from, look, up)
		await process_frame
	quit()
