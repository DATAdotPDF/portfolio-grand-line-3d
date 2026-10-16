extends SceneTree

## Vídeo com som dos efeitos sonoros do mar (gravado pelo Movie Maker do Godot, com áudio).
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie Builds/Videos/sfx_<cenário>.avi
##      --script res://Tests/sfx_video.gd -- <cenário>
## Cenários: mar (água no casco pela velocidade + vela panejando contra o vento),
## tempestade (chuva, vento, mar grosso, ondas arrebentando, raios/trovões, batidas da proa),
## ciclone (queda do barco na água depois do passeio), boias (alvos quebrando),
## kraken (sons próprios: presságio, rugido, tentáculos, redemoinho, barra de ação).

var world: Node3D
var scenario := "mar"
var caption: Label

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		scenario = args[0]
	call_deferred("run")

func say(text: String) -> void:
	caption.text = text
	print("SFX_VIDEO ", text)

func place(pos: Vector3, heading: Vector3) -> void:
	var ship: Node3D = world.ship
	var surface: Vector3 = world.ocean.surface_at(pos)
	var up := surface.normalized()
	var forward := heading.slide(up).normalized()
	ship.heading = forward
	ship.global_transform = Transform3D(Basis(forward.cross(up).normalized(), up, -forward), surface)
	ship.last_target_radius = -1.0
	ship.reset_physics_interpolation()
	world.camera.snap_to_boat()

## Leme automático por alguns segundos: mantém a proa em "wanted()" (a direção pode mudar).
func steer(seconds: float, wanted: Callable, throttle: float, boost: bool) -> void:
	var frames := int(seconds * 30.0)
	for i in frames:
		var ship: Node3D = world.ship
		var up: Vector3 = ship.global_position.normalized()
		var target: Vector3 = (wanted.call() as Vector3).slide(up).normalized()
		var angle: float = (ship.heading as Vector3).signed_angle_to(target, up)
		ship.test_controls = Vector3(throttle, clampf(-angle / 0.4, -1.0, 1.0), 1.0 if boost else 0.0)
		if i % 60 == 0:
			log_levels()
		await process_frame

func log_levels() -> void:
	var amb: Node = world.sea_ambience
	var parts := ["speed=%.1f badness=%.1f" % [world.ship.measured_speed, world.weather.badness]]
	for n in amb.storm_layers.values():
		parts.append("%s=%.0f" % [n.name, n.volume_db])
	print("SFX_LEVELS ", " ".join(parts))

func wind_dir() -> Vector3:
	return (root.get_node("/root/WindManager").wind_at(world.ship.global_position) as Vector3)

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.hud._set_carta_open(false)
	world.graphics.set_mode("alto")
	# Sem música no vídeo: só os efeitos.
	if world.music:
		world.music.stop()
		world.music.stream = null
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	world.sea_life.sea_shadows.timer = 9999.0
	world.sea_life.dolphin_timer = 9999.0
	var layer := CanvasLayer.new()
	layer.layer = 50
	caption = Label.new()
	caption.position = Vector2(24, 96)
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	layer.add_child(caption)
	root.add_child(layer)
	var weather: Node = world.weather
	# Tempestades e ciclones parados durante o vídeo.
	weather.storm_speed = 0.0
	weather.cyclone_speed = 0.0
	var p: Vector3 = weather.open_sea[weather.open_sea.size() / 3]
	match scenario:
		"mar":
			place(p * world.planet_radius, wind_dir())
			say("Parado: só o mar em volta")
			await create_timer(4.0).timeout
			say("Navegando devagar: água no casco baixinha")
			await steer(7.0, wind_dir, 0.5, false)
			say("Velocidade de cruzeiro")
			await steer(6.0, wind_dir, 1.0, false)
			say("Turbo (Shift): água correndo forte")
			await steer(9.0, wind_dir, 1.0, true)
			say("Proa contra o vento: a vela perde o vento e paneja")
			await steer(12.0, func(): return -wind_dir(), 1.0, false)
			say("Vira de volta: vela cheia, sem panejar")
			await steer(8.0, wind_dir, 1.0, false)
		"tempestade":
			var storm: Node3D = weather.storms[0]
			storm.min_badness = 3.6
			storm.peak_badness = 3.6
			var centre: Vector3 = storm.center * world.planet_radius
			var up := centre.normalized()
			var side := up.cross(Vector3.RIGHT).normalized()
			var start: Vector3 = (centre + side * (storm.radius * 1.9)).normalized() * world.planet_radius
			place(start, centre - start)
			say("Entrando na tempestade (ainda fora)")
			await steer(10.0, func(): return centre - world.ship.global_position, 1.0, true)
			say("Dentro: chuva gravada e trovões reais (atrasados pela distância do raio)")
			# Dá voltas lá dentro com turbo (batidas da proa e saltos nas ondas).
			# Perto do miolo anda de lado (círculo); longe dele volta para dentro.
			await steer(40.0, func():
				var to_centre: Vector3 = centre - world.ship.global_position
				var turn := 1.3 if to_centre.length() < storm.radius * 0.45 else 0.2
				return to_centre.rotated(world.ship.global_position.normalized(), turn), 1.0, true)
		"ciclone":
			var cyclone: Node3D = weather.cyclones[0]
			var centre: Vector3 = cyclone.center * world.planet_radius
			var up := centre.normalized()
			var side := up.cross(Vector3.RIGHT).normalized()
			var start: Vector3 = (centre + side * 90.0).normalized() * world.planet_radius
			place(start, centre - start)
			say("Indo para o ciclone")
			world.ship.test_controls = Vector3(1, 0, 0)
			var elapsed := 0.0
			var rode := false
			while elapsed < 70.0:
				await process_frame
				elapsed += 1.0 / 30.0
				if weather.ride.is_riding():
					if not rode:
						say("Pego pelo ciclone")
					rode = true
					if weather.ride.phase == 3 and not caption.text.begins_with("Caindo"):
						say("Caindo do alto...")
				elif rode:
					say("Casco bate na água")
					await create_timer(5.0).timeout
					break
		"kraken":
			var kraken: Node = world.kraken_event
			kraken.start()
			say("Kraken: presságio (a sombra vem por baixo)")
			world.ship.test_controls = Vector3(1.0, 0.0, 0.0)
			var frames_left := 30 * 110
			var last_phase := -1
			while kraken.phase != 0 and frames_left > 0:
				frames_left -= 1
				if kraken.phase != last_phase:
					last_phase = kraken.phase
					say(["", "Kraken: presságio (a sombra vem por baixo)", "Kraken: rugido e tentáculos rompendo a água", "Kraken: redemoinho (fugindo para a beirada)", "Kraken: escapou, ele vai embora"][last_phase])
				if kraken.phase == 3:
					var out: Vector3 = world.ship.global_position - kraken.center
					var up: Vector3 = world.ship.global_position.normalized()
					var angle: float = (world.ship.heading as Vector3).signed_angle_to(out.slide(up).normalized(), up)
					world.ship.test_controls = Vector3(1.0, clampf(-angle / 0.4, -1.0, 1.0), 1.0)
					# Na beirada: aperta a barra de ação ~10 vezes por segundo.
					if kraken.action_active() and frames_left % 3 == 0:
						if not caption.text.begins_with("Kraken: barra"):
							say("Kraken: barra de ação (Espaço) e arranque")
						kraken.action_press()
				await process_frame
			await create_timer(2.0).timeout
		"boias":
			var naval: Node = world.naval
			var targets: Array = naval.course_targets()
			for n in 3:
				var target: Dictionary = targets[n]
				var at: Vector3 = target.node.global_position
				var normal: Vector3 = at.normalized()
				var away := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
				# Barco a 18 m da boia, proa para ela (a câmera atrás do barco vê a boia na frente).
				place(at + away * 18.0, -away)
				say("Alvo %d: tiro de canhão" % (n + 1))
				await create_timer(2.0).timeout
				naval.fire()
				await create_timer(1.6).timeout
				say("Alvo %d: madeira quebrando" % (n + 1))
				naval.hit_target(naval.targets.find(target), at)
				await create_timer(3.5).timeout
	quit()
