extends SceneTree

## Vídeo de um encontro com a câmera do jogo (gravado pelo Movie Maker do Godot).
## Uso: Godot.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie Builds/Videos/<nome>.avi
##      --script res://Tests/encounter_video.gd -- <cenário>
## Cenários: foca, arraia, tubarao, jubarte, tubarao_baleia, golfinhos, kraken_fuga,
## kraken_naufragio, fantasma_fuga, fantasma_pego, tornado, canhao (mira, tiro, recarga, acerto),
## mapa (globo, giro, dia/noite), regata.

var world: Node3D
var scenario := "foca"
var autopilot := Callable()

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

## Leme automático: aponta a proa para "wanted" (com impulso opcional).
func steer_to(wanted: Vector3, boost: bool) -> void:
	var ship: Node3D = world.ship
	var up: Vector3 = ship.global_position.normalized()
	var angle: float = (ship.heading as Vector3).signed_angle_to(wanted.slide(up).normalized(), up)
	# Steering positivo vira para boreste (direita), que é giro negativo em volta do "up".
	ship.test_controls = Vector3(1.0, clampf(-angle / 0.4, -1.0, 1.0), 1.0 if boost else 0.0)

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("night" if scenario.begins_with("fantasma") else "day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.hud._set_carta_open(false)
	# Gravação é mais lenta que o tempo real: sem travar no Alto o modo automático baixaria a qualidade.
	world.graphics.set_mode("alto")
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1.0, 0.0, 0.0)
	# Desliga os encontros sozinhos (só o do cenário aparece).
	world.sea_life.sea_shadows.timer = 9999.0
	world.sea_life.dolphin_timer = 9999.0
	var p: Vector3 = world.weather.open_sea[world.weather.open_sea.size() / 3]
	place(p * world.planet_radius, Vector3.FORWARD.slide(p).normalized())
	await create_timer(3.0).timeout
	match scenario:
		"golfinhos":
			world.sea_life.spawn_pod(3)
			await create_timer(22.0).timeout
		"kraken_fuga", "kraken_naufragio", "kraken_aborta":
			await _kraken(scenario)
		"tornado":
			# Navega na direção de um ciclone (sem entrar) para mostrar o tornado novo.
			var c: Vector3 = world.weather.cyclones[0].center
			var tangent := c.cross(Vector3.UP if absf(c.y) < 0.9 else Vector3.RIGHT).normalized()
			place((c * world.planet_radius - tangent * 260.0).normalized() * world.planet_radius, tangent)
			world.ship.test_controls = Vector3(1.0, 0.25, 0.0)
			await create_timer(24.0).timeout
		"fantasma_fuga", "fantasma_pego":
			await _ghost(scenario == "fantasma_fuga")
		"canhao":
			await _cannon()
		"mapa":
			# Mapa: abre o globo, gira, troca dia → noite → dia e volta ao barco.
			world.ship.test_controls = Vector3.ZERO
			world.toggle_map()
			await create_timer(4.0).timeout
			for i in 90:
				world.camera.drag_orbit(Vector2(6.0, 1.0))
				await process_frame
			world.select_time("night")
			await create_timer(5.0).timeout
			world.select_time("day")
			await create_timer(4.0).timeout
			world.toggle_map()
			await create_timer(4.0).timeout
		"regata":
			# Regata (time attack): começa e navega pela primeira perna.
			world._start_time_attack()
			await create_timer(26.0).timeout
		_:
			world.sea_life.sea_shadows.spawn(scenario)
			await create_timer(30.0 if scenario == "tubarao_baleia" else 24.0).timeout
	quit()

func _kraken(mode: String) -> void:
	var kraken: Node = world.kraken_event
	kraken.start()
	# Presságio: segue navegando (a sombra vem por trás); no "aborta" foge com impulso.
	world.ship.test_controls = Vector3(1.0, 0.0, 0.0)
	var frames_left := 30 * 110
	while kraken.phase != 0 and frames_left > 0:
		frames_left -= 1
		var out: Vector3 = (world.ship.global_position - kraken.center)
		if frames_left % 30 == 0:
			print("KDBG phase=%d r=%.1f ship=%.1f action=%.2f" % [kraken.phase, out.length(), world.ship.measured_speed, kraken.action])
		if kraken.phase == 3 and mode == "kraken_fuga":
			steer_to(out, true)
			# Na beirada: aperta a barra de ação ~10 vezes por segundo.
			if kraken.action_active() and frames_left % 3 == 0:
				kraken.action_press()
		elif kraken.phase == 3:
			world.ship.test_controls = Vector3(0.3, 0.0, 0.0)
		if world.easter_egg.visible:
			await create_timer(4.0).timeout
			world.easter_egg.close_card()
		await process_frame
	await create_timer(1.5).timeout

func _ghost(escape: bool) -> void:
	var ghost: Node3D = world.ghost_ship
	ghost.require_night = false
	if ghost.model == null:
		ghost._build()
	var ship: Node3D = world.ship
	var up: Vector3 = ship.global_position.normalized()
	var right: Vector3 = ship.heading.cross(up).normalized()
	ghost.position = (ship.global_position + ship.heading * 85.0 + right * 20.0).normalized() * world.planet_radius
	ghost.heading = -ship.heading
	ghost.active = true
	ghost.leaving = false
	ghost.presence = 0.2
	ghost.current_speed = 4.0
	ghost.visible = true
	var frames_left := 30 * 90  # até 90 s de jogo (gravação em 30 fps fixos)
	var turned := false
	while frames_left > 0:
		frames_left -= 1
		if frames_left % 150 == 0:
			print("CHASE dist=%.1f ship=%.1f ghost=%.1f chasing=%s" % [ghost.global_position.distance_to(ship.global_position), ship.measured_speed, ghost.current_speed, ghost.chasing])
		if ghost.chasing and not turned:
			turned = true
		if turned:
			if escape:
				steer_to(ship.global_position - ghost.global_position, true)
			else:
				# Segue reto devagar: é alcançado.
				ship.test_controls = Vector3(0.6, 0.0, 0.0)
		if world.easter_egg.visible:
			await create_timer(4.0).timeout
			world.easter_egg.close_card()
			break
		if escape and turned and not ghost.chasing:
			await create_timer(4.0).timeout
			break
		await process_frame

## Canhão: para ao lado de uma boia livre, acha a elevação que acerta (simulando a parábola),
## segura a mira, solta, espera a recarga e atira de novo.
func _cannon() -> void:
	var naval: Node = world.naval
	var buoy: Dictionary = {}
	for t in naval.targets:
		if not naval.is_course_target(t) and t.active:
			buoy = t
			break
	if buoy.is_empty():
		print("CANNON no active free buoy")
		return
	world.ship.test_controls = Vector3.ZERO
	# Posição real da boia (elas derivam; "normal" é só a âncora).
	var buoy_pos: Vector3 = (buoy.node as Node3D).global_position
	print("CANNON buoy=%s island=%d" % [buoy.id, int(buoy.island)])
	var up := buoy_pos.normalized()
	var heading := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP).normalized()
	place(buoy_pos, heading)
	await create_timer(0.2).timeout
	var side: Vector3 = (-naval.muzzle.global_basis.z).slide(up).normalized()
	place(buoy_pos - side * 26.0, heading)
	# Parado de verdade (sem deriva) e a câmera virada para o lado do canhão: boia, mira e tiro no quadro.
	world.ship.drive_speed = 0.0
	var ship_up: Vector3 = world.ship.global_position.normalized()
	var ship_forward: Vector3 = (-world.ship.global_basis.z).slide(ship_up).normalized()
	world.camera.yaw = ship_forward.signed_angle_to(side, ship_up)
	world.camera.pitch = 3.0
	await create_timer(2.0).timeout
	for shot in 2:
		var best := 0.0
		var best_err := INF
		for deg in range(-3, 31):
			naval.aim_elevation = deg_to_rad(float(deg))
			var pos: Vector3 = naval.muzzle.global_position
			var vel: Vector3 = naval._launch_velocity()
			for i in 160:
				vel -= pos.normalized() * 9.8 * 0.05
				pos += vel * 0.05
				if pos.length() <= world.planet_radius + float(world.ocean.height_at(pos)):
					break
			var err := pos.distance_to(buoy_pos)
			if err < best_err:
				best_err = err
				best = float(deg)
		naval.aim_elevation = deg_to_rad(best + (4.0 if shot == 0 else 0.0))
		# Mantém o barco no lugar enquanto mira (as ondas empurram).
		place(buoy_pos - side * 26.0, heading)
		world.ship.drive_speed = 0.0
		naval.begin_aim()
		await create_timer(2.2).timeout
		naval.release_aim()
		print("CANNON shot=%d aim=%.0f" % [shot, best])
		await create_timer(4.0).timeout
	await create_timer(2.0).timeout
