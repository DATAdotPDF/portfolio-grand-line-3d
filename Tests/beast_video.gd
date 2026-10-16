extends SceneTree

## Vídeo de cada besta do mar (SeaBeasts: rig do Meshy + clipe do Blender) andando no seu circuito,
## gráficos no Alto, dia. Vistas: lado (câmera acompanhando de lado, sem HUD) e jogo (barco parado
## perto do caminho, câmera do jogo).
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie X.avi
##      --script res://Tests/beast_video.gd -- <timber_whale|abyssal_behemoth|abyssal_obsidian|tartaruga> <lado|jogo|escala|rastro>

var world: Node3D
var camera: Camera3D
var beast_name := "timber_whale"
var view := "lado"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		beast_name = args[0]
	if args.size() > 1:
		view = args[1]
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
	var beast: Dictionary = {}
	for b in world.sea_beasts.beasts:
		if b.name == beast_name:
			beast = b
	var body: Node3D
	var length := 0.0
	var width := 0.0
	if beast_name == "tartaruga":
		var item: Dictionary = world.world_decor.turtle.item
		body = item.root
		length = float(item.radius) * 2.0
		width = length
	elif beast.is_empty():
		print("BEAST_MISSING %s" % beast_name)
		quit()
		return
	else:
		# Sons próprios mais cedo para aparecerem no vídeo.
		beast.call_timer = 3.0
		body = beast.root
		length = maxf(float(beast.length), float(beast.get("height", 0.0)))
		width = float(beast.width)
	var up := body.global_position.normalized()
	var forward := -body.global_basis.z.slide(up).normalized()
	var right := forward.cross(up).normalized()
	if view == "escala":
		# Barco parado bem ao lado do colosso, no mesmo rumo: dá a escala (barco de 5 m).
		var beside: Vector3 = body.global_position + right * (width * 0.5 + 25.0)
		park_ship(beside, forward)
	else:
		# Barco ao lado, um pouco à frente, de proa para a besta (passa na frente da câmera do jogo).
		var ship_at: Vector3 = body.global_position + forward * length * 0.6 + right * (length * 0.75 + 45.0)
		park_ship(ship_at, (body.global_position - ship_at).slide(ship_at.normalized()))
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 50.0
	root.add_child(camera)
	await create_timer(2.0).timeout
	print("BEAST_START %.3f" % (Engine.get_process_frames() / 30.0))
	for i in 18 * 30:
		var center := body.global_position
		up = center.normalized()
		forward = -body.global_basis.z.slide(up).normalized()
		right = forward.cross(up).normalized()
		if view == "lado" or view == "escala" or view == "rastro":
			for layer in world.find_children("*", "CanvasLayer", true, false):
				layer.visible = false
			var from: Vector3 = center + right * length * 0.95 + forward * length * 0.25 + up * length * 0.14
			if view == "escala":
				# De lado, mais longe e baixo, com o barco entre a câmera e o colosso.
				from = center + right * (width * 0.5 + length * 0.75) + forward * length * 0.15 + up * length * 0.08
			var target := center + up * length * 0.06
			if view == "rastro":
				# De cima e de trás: o rastro abrindo atrás do bicho.
				from = center - forward * length * 1.25 + right * length * 0.45 + up * length * 0.28
				target = center - forward * length * 0.35
			camera.make_current()
			camera.look_at_from_position(from, target, up)
		await process_frame
	quit()
