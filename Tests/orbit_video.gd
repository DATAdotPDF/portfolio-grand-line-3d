extends SceneTree

## Volta de 360° em volta de uma coisa do mundo, sem HUD, para conferir de todos os lados.
## Cenários: ilha0..ilha4 (Sobre, Experiência, Formação, Projetos, Contato), tornado, fantasma.
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie Builds/Videos/X.avi
##      --script res://Tests/orbit_video.gd -- <cenário> [night]

const SECONDS := 12.0

var world: Node3D
var camera: Camera3D
var scenario := "ilha0"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg in ["night"]:
			scenario = arg
	call_deferred("run")

func run() -> void:
	var night := "night" in OS.get_cmdline_user_args() or scenario == "fantasma"
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("night" if night else "day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.graphics.set_mode("alto")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	world.sea_life.sea_shadows.timer = 9999.0
	world.sea_life.dolphin_timer = 9999.0
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 50.0
	root.add_child(camera)
	# [alvo, raio da volta, altura da câmera, altura do ponto olhado]
	var target: Node3D
	var radius := 40.0
	var height := 14.0
	var look := 5.0
	if scenario.begins_with("ilha"):
		var index := int(scenario.trim_prefix("ilha"))
		target = world.islands[index]
		# Por ilha (o forte e o farol são bem mais altos): [raio, altura, ponto olhado].
		var framing: Array = [[30.0, 12.0, 4.0], [44.0, 20.0, 9.0], [34.0, 14.0, 6.0], [34.0, 13.0, 4.0], [50.0, 22.0, 15.0]][index]
		radius = framing[0]
		height = framing[1]
		look = framing[2]
	elif scenario == "tornado":
		target = world.weather.cyclones[0]
		radius = 190.0
		height = 55.0
		look = 50.0
	elif scenario == "fantasma":
		var ghost: Node3D = world.ghost_ship
		ghost.require_night = false
		if ghost.model == null:
			ghost._build()
		var ship: Node3D = world.ship
		ghost.position = (ship.global_position + ship.heading * 120.0).normalized() * world.planet_radius
		ghost.heading = -ship.heading
		ghost.active = true
		ghost.leaving = false
		ghost.presence = 1.0
		ghost.visible = true
		target = ghost
		radius = 28.0
		height = 7.0
		look = 4.0
	await create_timer(1.0).timeout
	var frames := int(SECONDS * 30.0)
	# Para cortar o começo no ffmpeg (antes disso aparece a câmera do jogo).
	print("ORBIT_START %.3f" % (Engine.get_process_frames() / 30.0))
	for i in frames:
		for layer in world.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		var center := target.global_position
		var up := center.normalized()
		var side := target.global_basis.z.slide(up).normalized().rotated(up, TAU * float(i) / frames)
		camera.make_current()
		camera.look_at_from_position(center + side * radius + up * height, center + up * look, up)
		await process_frame
	quit()
