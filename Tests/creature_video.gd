extends SceneTree

## Vídeo de cada bicho novo no jogo (modelos do Meshy riggados no Blender, gráficos no Alto, sem HUD):
## câmera acompanhando o bicho de lado. Cenários: golfinhos, gaivotas, peixe_voador, tubarao, kraken.
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie Builds/Videos/X.avi
##      --script res://Tests/creature_video.gd -- <cenário>

var world: Node3D
var camera: Camera3D
var scenario := "golfinhos"
var cam_pos := Vector3.ZERO

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		scenario = args[0]
	call_deferred("run")

func place(pos: Vector3, heading: Vector3) -> void:
	var ship: Node3D = world.ship
	var surface: Vector3 = world.ocean.surface_at(pos)
	var up := surface.normalized()
	var forward := heading.slide(up).normalized()
	ship.heading = forward
	ship.global_transform = Transform3D(Basis(forward.cross(up).normalized(), up, -forward), surface)
	ship.drive_speed = 0.0

## Acompanha `target()` de lado (à direita do rumo), a `distance` m e `height` m, suavizando.
func follow(seconds: float, target: Callable, distance: float, height: float, back := 0.35) -> void:
	for i in int(seconds * 30.0):
		for layer in world.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		var data: Array = target.call()
		if data.is_empty():
			await process_frame
			continue
		var at: Vector3 = data[0]
		var heading: Vector3 = data[1]
		var up := at.normalized()
		var side := heading.cross(up).normalized()
		var wanted := at + side * distance - heading * distance * back
		# Altura medida da superfície do mar (não do bicho, que mergulha): a câmera nunca entra na água.
		var water: Vector3 = world.ocean.surface_at(wanted)
		wanted = water + water.normalized() * height
		cam_pos = wanted if cam_pos == Vector3.ZERO else cam_pos.lerp(wanted, 0.12)
		camera.make_current()
		camera.look_at_from_position(cam_pos, at, up)
		if OS.get_environment("CREATURE_DEBUG") != "" and i % 30 == 0:
			print("FOLLOW d=%.1f screen=%s" % [cam_pos.distance_to(at), camera.unproject_position(at)])
		await process_frame

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
	world.ship.test_controls = Vector3(1.0, 0.0, 0.0)
	var sea: Node = world.sea_life
	sea.sea_shadows.timer = 9999.0
	sea.dolphin_timer = 9999.0
	var p: Vector3 = world.weather.open_sea[world.weather.open_sea.size() / 3]
	place(p * world.planet_radius, Vector3.FORWARD.slide(p).normalized())
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 55.0
	root.add_child(camera)
	await create_timer(3.0).timeout
	match scenario:
		"golfinhos":
			sea.spawn_pod(3)
			print("CREATURE_START %.3f" % (Engine.get_process_frames() / 30.0))
			await follow(16.0, func() -> Array: return [] if sea.dolphins.is_empty() else [sea.dolphins[0].position, sea.dolphins[0].heading], 9.0, 3.0)
		"golfinho_perto":
			# De lado e de perto: corpo ondulando em S nadando e arqueando no salto.
			sea.spawn_pod(2)
			print("CREATURE_START %.3f" % (Engine.get_process_frames() / 30.0))
			await follow(14.0, func() -> Array: return [] if sea.dolphins.is_empty() else [sea.dolphins[0].position, sea.dolphins[0].heading], 5.0, 1.0, 0.0)
		"gaivotas_jogo", "peixe_voador_jogo", "golfinhos_jogo":
			# Na distância normal da câmera do jogo (atrás do barco), sem câmera de teste.
			if scenario == "gaivotas_jogo":
				world.seagulls.spawn_gulls(4)
			elif scenario == "golfinhos_jogo":
				sea.spawn_pod(3)
			else:
				sea.spawn_flying_school(8)
			print("CREATURE_START %.3f" % (Engine.get_process_frames() / 30.0))
			for i in int(14.0 * 30.0):
				await process_frame
		"gaivotas":
			world.seagulls.spawn_gulls(3)
			print("CREATURE_START %.3f" % (Engine.get_process_frames() / 30.0))
			await follow(16.0, func() -> Array: return [] if world.seagulls.gulls.is_empty() else [world.seagulls.gulls[0].position, world.seagulls.gulls[0].heading], 7.0, 9.0)
		"peixe_voador":
			sea.spawn_flying_school(6)
			print("CREATURE_START %.3f" % (Engine.get_process_frames() / 30.0))
			await follow(10.0, func() -> Array: return [] if sea.flying_fish.is_empty() else [sea.flying_fish[0].position, sea.flying_fish[0].heading], 3.5, 1.6)
		"tubarao":
			var group: Dictionary = sea.sea_shadows.spawn("tubarao")
			print("CREATURE_START %.3f" % (Engine.get_process_frames() / 30.0))
			await follow(16.0, func() -> Array: return [] if group.members.is_empty() or not group.members[0].has("fin") or not is_instance_valid(group.members[0].fin) else [(group.members[0].fin as Node3D).global_position, group.members[0].heading], 7.0, 2.5)
		"kraken":
			# Evento inteiro do kraken com a câmera do jogo (tentáculos e boca do Meshy).
			print("CREATURE_START %.3f" % (Engine.get_process_frames() / 30.0))
			var kraken: Node = world.kraken_event
			kraken.start()
			var frames_left := 30 * 70
			while kraken.phase != 0 and frames_left > 0:
				frames_left -= 1
				for layer in world.find_children("*", "CanvasLayer", true, false):
					if layer.name != "KrakenAction":
						layer.visible = false
				if kraken.phase == 3 and kraken.action_active() and frames_left % 3 == 0:
					kraken.action_press()
				await process_frame
	quit()
