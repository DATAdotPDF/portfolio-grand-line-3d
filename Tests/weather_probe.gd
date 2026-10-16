extends SceneTree

## Clima: tempestade local (de longe e por dentro) e gaivotas.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/weather_probe.gd
## Saída: Builds/WeatherProbe/*.jpg

var world: Node3D
var cam: Camera3D

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/WeatherProbe/%s.jpg" % name), 0.85)

## Câmera fixa no mundo olhando para um ponto (atualiza alguns quadros para o resto assentar).
func shot(name: String, from: Vector3, look: Vector3, frames := 20) -> void:
	for i in frames:
		cam.global_position = from
		cam.look_at(look, from.normalized())
		await process_frame
	await still(name)

## Câmera presa ao barco (offset: x = boreste, y = cima, z = popa).
func ship_shot(name: String, offset: Vector3, look: Vector3, frames := 20) -> void:
	for i in frames:
		var t: Transform3D = world.ship.get_global_transform_interpolated()
		cam.global_position = t * offset
		cam.look_at(t * look, t.basis.y)
		await process_frame
	await still(name)

func put_ship(direction: Vector3, heading_hint: Vector3) -> void:
	var up := direction.normalized()
	var heading := heading_hint.slide(up).normalized()
	world.ship.heading = heading
	world.ship.global_transform = Transform3D(Basis(heading.cross(up).normalized(), up, -heading), up * (world.planet_radius + 0.3))
	world.ship.reset_physics_interpolation()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/WeatherProbe"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.clock.set_time(0.40, true)
	world.select_time("day")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(0, 0, 0)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 4000.0
	world.add_child(cam)
	cam.make_current()
	# Tempestade mais próxima do barco.
	var storm: Node3D = null
	for st in world.weather.storms:
		if storm == null or world.ship.global_position.distance_to(st.center * world.planet_radius) < world.ship.global_position.distance_to(storm.center * world.planet_radius):
			storm = st
	# Tempestade no pico (badness = peak) para ver espuma, spray e raios.
	storm.peak_badness = 4.0
	storm.cycle_phase = PI * 0.5 - storm.age * TAU / storm.cycle_period
	# Para a deriva durante as fotos (o destino vira a posição atual).
	for i in world.weather.movers.size():
		world.weather.targets[i] = world.weather.movers[i].center
	var centre: Vector3 = storm.center * world.planet_radius
	print("WEATHER storms=%d nearest=%.0f m radius=%.0f" % [world.weather.storms.size(), world.ship.global_position.distance_to(centre), storm.radius])
	var ship_pos: Vector3 = world.ship.global_position
	var up := ship_pos.normalized()
	var toward := (centre - ship_pos).slide(up).normalized()
	# 1. De longe (~260 m), do barco olhando para a tempestade.
	put_ship((centre - toward * 260.0).normalized(), toward)
	await create_timer(1.0).timeout
	await ship_shot("storm_far", Vector3(0.0, 4.0, 6.0), Vector3(0, 10.0, -60.0))
	# 2. Na borda (1,5 raio).
	put_ship((centre - toward * storm.radius * 1.5).normalized(), toward)
	await create_timer(1.0).timeout
	await ship_shot("storm_near", Vector3(-4.0, 3.0, 9.0), Vector3(0, 8.0, -30.0))
	# 3. Dentro: gotas, véu, mar revolto; depois um raio forçado.
	put_ship((centre - toward * storm.radius * 0.25).normalized(), toward)
	await create_timer(2.5).timeout
	print("WEATHER inside badness=%.2f gloom=%.2f wave_factor=%.2f rain_ratio=%.2f wind=%.2f spray=%d" % [world.weather.badness, world.storm_gloom, world.ocean.storm_factor(world.ship.global_position), world.weather.personal_rain.amount_ratio, world.wind_at(world.ship.global_position).length(), world.weather.spray.count])
	await ship_shot("storm_inside", Vector3(-3.5, 2.6, 8.5), Vector3(0, 1.0, -6.0))
	storm.next_strike = 0.0
	await process_frame
	await process_frame
	await ship_shot("storm_foam", Vector3(0.0, 9.0, 14.0), Vector3(0, 0.0, -25.0))
	# Trovão do Wind Waker: força um clarão próximo e fotografa no pico (raios no horizonte).
	var thunder: Node = world.weather.thunder
	await ship_shot("storm_before_thunder", Vector3(-3.5, 2.6, 8.5), Vector3(0, 12.0, -60.0), 10)
	thunder.state = 1
	var waited := 0
	while thunder.state == 1 and waited < 60:
		await process_frame
		waited += 1
	print("WEATHER thunder bolts=%d flash=%.2f near=%.2f" % [thunder.bolts.size(), thunder.flash, thunder.near_flash])
	await still("storm_lightning")
	# 4. Gaivotas pela câmera normal do jogo.
	put_ship(ship_pos.normalized(), -world.ship.global_transform.basis.z)
	world.ship.test_controls = Vector3(1, 0, 0)
	world.camera.make_current()
	world.seagulls.spawn_gulls(3)
	await create_timer(5.0).timeout
	var gull: Dictionary = world.seagulls.gulls[world.seagulls.gulls.size() - 1]
	print("WEATHER gulls count=%d distance=%.1f" % [world.seagulls.gulls.size(), world.ship.global_position.distance_to(gull.position)])
	await still("gulls_game_a")
	# Barco vira forte: as gaivotas não podem virar junto.
	var before: Vector3 = gull.heading
	world.ship.test_controls = Vector3(1, 1, 0)
	await create_timer(3.0).timeout
	print("WEATHER gull heading change while ship turns=%.0f deg" % rad_to_deg(before.angle_to(gull.heading)))
	await still("gulls_game_b")
	world.ship.test_controls = Vector3(1, 0, 0)
	await create_timer(4.0).timeout
	await still("gulls_game_c")
	# 5. Noite: lampião de popa e a tempestade de longe (cumulonimbus contra o céu).
	world.ship.test_controls = Vector3(0, 0, 0)
	world.select_time("night")
	cam.make_current()
	put_ship((centre - toward * 260.0).normalized(), toward)
	await create_timer(2.0).timeout
	await ship_shot("night_lantern", Vector3(-3.5, 2.2, 6.5), Vector3(0, 1.8, 1.0))
	await ship_shot("night_storm_far", Vector3(0.0, 4.0, 6.0), Vector3(0, 30.0, -80.0))
	world.select_time("day")
	await create_timer(1.0).timeout
	await ship_shot("day_storm_far", Vector3(0.0, 4.0, 6.0), Vector3(0, 30.0, -80.0))
	# 6. Mapa grande: colunas de ciclone (turquesa) e tempestades (cinza).
	world.camera.make_current()
	world.toggle_map()
	await create_timer(1.0).timeout
	# Gira o globo até o ciclone.
	world.camera.overview_dragged = true
	world.camera.overview_direction = (world.weather.cyclones[0].center + storm.center * 0.3).normalized()
	await create_timer(3.0).timeout
	await still("map_overview")
	world.toggle_map()
	# 7. Deriva: simula 40 min em passos de 1 s e confere que ninguém sai do mar aberto.
	var weather: Node = world.weather
	for i in weather.movers.size():
		weather.targets[i] = weather._next_target(i)
	var outside := 0
	var closest := INF
	var travelled := 0.0
	var start: Array[Vector3] = []
	for mover in weather.movers:
		start.append(mover.center)
	for step in 2400:
		weather._move(1.0)
		for i in weather.movers.size():
			if not weather._is_open(weather.movers[i].center):
				outside += 1
			for j in range(i + 1, weather.movers.size()):
				closest = minf(closest, weather.movers[i].center.angle_to(weather.movers[j].center) * world.planet_radius)
	for i in weather.movers.size():
		travelled = maxf(travelled, start[i].angle_to(weather.movers[i].center) * world.planet_radius)
	print("WEATHER roam steps=2400 outside=%d closest=%.0f m max_displacement=%.0f m" % [outside, closest, travelled])
	quit()
