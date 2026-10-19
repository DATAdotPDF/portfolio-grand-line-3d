extends SceneTree

## Balanceamento das fugas com o barco a 15 m/s e o BURST (Pedro, 2026-10-18): para cada evento,
## só cruzeiro x BURST sempre que recarrega (proa sempre para fora / para longe).
##   fantasma: só cruzeiro deve ser pego; com BURST, despista.
##   tornado (a 20 e 26 m do eixo, chegando a 15 m/s): perto, só cruzeiro é capturado; com BURST, escapa.
##   kraken: só cruzeiro fica preso; com BURST chega à beirada; BURST + barra de ação escapa.
## Uso: Godot.exe --path . --headless --script res://Tests/escape_balance.gd [-- --only=fantasma|tornado|kraken]

var world: Node3D
var ship: Node3D
var only := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	call_deferred("run")

func run() -> void:
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(1.5).timeout
	world._start_sailing()
	world.hud._set_carta_open(false)
	ship = world.ship
	ship.controls_override = true
	for mode in ["cruzeiro", "burst"]:
		if only in ["", "fantasma"]:
			await _ghost(mode)
		if only in ["", "tornado"]:
			for start in [20.0, 26.0]:
				await _cyclone(mode, start)
	if only in ["", "kraken"]:
		for mode in ["cruzeiro", "burst", "burst+acao"]:
			await _kraken(mode)
	quit()

func _place(p: Vector3, forward: Vector3) -> void:
	var up := p.normalized()
	var f := forward.slide(up).normalized()
	ship.heading = f
	ship.drive_speed = ship.cruise_speed
	ship.burst_left = 0.0
	ship.burst_ready_in = 0.0
	ship.global_transform = Transform3D(Basis(f.cross(up).normalized(), up, -f), up * (world.planet_radius + 0.3))
	ship.reset_physics_interpolation()

## BURST: aperta um quadro sim, outro não (o barco só dispara no aperto).
func _pulse(mode: String, frame: int) -> float:
	return 1.0 if mode.begins_with("burst") and frame % 2 == 0 else 0.0

func _ghost(mode: String) -> void:
	var g: Node3D = world.ghost_ship
	var p: Vector3 = world.weather.open_sea[world.weather.open_sea.size() / 2]
	_place(world.ocean.surface_at(p * world.planet_radius), Vector3.FORWARD)
	ship.test_controls = Vector3(1, 0, 0)
	await create_timer(3.0).timeout
	g.spawn(true)
	g.presence = 1.0
	var frame := 0
	var t := 0.0
	var result := "nada"
	while t < 60.0:
		await physics_frame
		frame += 1
		t += 1.0 / Engine.physics_ticks_per_second
		var away: Vector3 = (ship.global_position - g.global_position).slide(ship.global_position.normalized())
		if away.length() > 1.0:
			ship.heading = away.normalized()
		ship.test_controls = Vector3(1, 0, _pulse(mode, frame) if g.chasing else 0.0)
		if world.easter_egg.visible:
			result = "pego"
			break
		if not g.chasing and g.leaving and t > 2.0:
			result = "despistou" if g.presence > 0.0 or ship.enabled else "pego"
			break
	print("BALANCE fantasma %s: %s em %.1f s (dist %.0f m)" % [mode, result, t, ship.global_position.distance_to(g.global_position)])
	if world.easter_egg.visible:
		world.easter_egg.close_card()
	g.active = false
	g.visible = false
	g.timer = 999.0
	await create_timer(1.0).timeout

func _cyclone(mode: String, start: float) -> void:
	var weather: Node = world.weather
	var cyclone: Node3D = weather.cyclones[0]
	for i in weather.movers.size():
		weather.targets[i] = weather.movers[i].center
	var c0: Vector3 = cyclone.center * world.planet_radius
	var away_dir := c0.normalized().cross(Vector3.FORWARD).normalized()
	_place((c0 + away_dir * start).normalized() * world.planet_radius, away_dir)
	var frame := 0
	var t := 0.0
	var best := 0.0
	while t < 12.0:
		await physics_frame
		frame += 1
		t += 1.0 / Engine.physics_ticks_per_second
		# O jogador briga com o leme: proa sempre para fora do eixo.
		var axis: Vector3 = cyclone.axis_point(0.0)
		var out: Vector3 = (ship.global_position - axis).slide(ship.global_position.normalized())
		if out.length() > 0.5 and weather.ride.phase == 0:
			ship.heading = out.normalized()
		ship.test_controls = Vector3(1, 0, _pulse(mode, frame))
		var d: float = ship.global_position.distance_to(cyclone.center * world.planet_radius)
		best = maxf(best, d)
		if weather.ride.phase != 0 or d > 80.0:
			break
	var captured: bool = weather.ride.phase != 0
	print("BALANCE tornado a %d m %s: %s em %.1f s (mais longe %.0f m)" % [int(start), mode, "capturado" if captured else ("escapou" if best > 80.0 else "preso no puxão"), t, best])
	# Solta o barco se foi capturado (volta ao estado livre).
	while weather.ride.phase != 0:
		await create_timer(0.5).timeout
		t += 0.5
		if t > 60.0:
			break
	ship.enabled = true
	await create_timer(1.0).timeout

func _kraken(mode: String) -> void:
	var p: Vector3 = world.weather.open_sea[world.weather.open_sea.size() / 3]
	_place(world.ocean.surface_at(p * world.planet_radius), Vector3.FORWARD)
	ship.test_controls = Vector3(1, 0, 0)
	await create_timer(2.0).timeout
	var k: Node = world.kraken_event
	k.cooldown = 0.0
	k.start()
	while k.phase != 3:
		await process_frame
	var frame := 0
	var t := 0.0
	var max_r := 0.0
	var result := "preso"
	while t < 50.0:
		await physics_frame
		frame += 1
		t += 1.0 / Engine.physics_ticks_per_second
		var up: Vector3 = k.center.normalized()
		var out: Vector3 = (ship.global_position - k.center).slide(up)
		if out.length() > 0.5:
			ship.heading = out.normalized().slide(ship.global_position.normalized()).normalized()
		ship.test_controls = Vector3(1, 0, _pulse(mode, frame))
		if mode == "burst+acao" and k.action_active() and frame % 6 == 0:
			k.action_press()
		max_r = maxf(max_r, k._ship_radius() if k.phase == 3 else max_r)
		if k.phase != 3:
			result = "naufragou" if k.lost else "escapou"
			break
	print("BALANCE kraken %s: %s em %.1f s (raio máx %.0f m; beirada %.0f, fuga %.0f)" % [mode, result, t, max_r, k.action_radius, k.escape_radius])
	if k.phase == 3:
		k._finish(false)
	while k.phase != 0:
		await process_frame
	if world.easter_egg.visible:
		world.easter_egg.close_card()
	ship.held = false
	await create_timer(1.0).timeout
