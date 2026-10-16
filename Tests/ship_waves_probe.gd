extends SceneTree

## Flutuação com gravidade: mar calmo e tempestade no pico, barco em velocidade máxima.
## Mede tempo no ar, maior salto e batidas de proa; fotos de uma batida.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/ship_waves_probe.gd
## Saída: Builds/ShipWavesProbe/*.jpg

var world: Node3D
var splashes := 0
var shot_pending := false

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/ShipWavesProbe/%s.jpg" % name), 0.85)

func _on_splash(_at: Vector3, _strength: float) -> void:
	splashes += 1
	shot_pending = true

func put_ship(direction: Vector3, heading_hint: Vector3) -> void:
	var up := direction.normalized()
	var heading := heading_hint.slide(up).normalized()
	world.ship.heading = heading
	world.ship.global_transform = Transform3D(Basis(heading.cross(up).normalized(), up, -heading), up * (world.planet_radius + 0.3))
	world.ship.reset_physics_interpolation()
	world.camera.snap_to_boat()

func sail(label: String, seconds: float) -> void:
	splashes = 0
	var air := 0.0
	var best := 0.0
	var t := 0.0
	var shots := 0
	var rise := 0.0
	var last := -1.0
	var bad := 0.0
	var peak := 0.0
	var hmin := INF
	var hmax := -INF
	world.ship.max_bow_rate = 0.0
	var prev: Vector3 = world.ship.global_position
	var backs := 0
	var jumps := 0
	var worst := 0.0
	var last_us := Time.get_ticks_usec()
	var hitches := 0
	var worst_ms := 0.0
	while t < seconds:
		await physics_frame
		var now_us := Time.get_ticks_usec()
		var ms := (now_us - last_us) / 1000.0
		last_us = now_us
		if t > 0.5 and ms > 50.0:
			hitches += 1
			print("HITCH t=%.2f %.0f ms" % [t, ms])
		worst_ms = maxf(worst_ms, ms)
		var now: Vector3 = world.ship.global_position
		var step: Vector3 = (now - prev).slide(now.normalized())
		var fwd: float = step.dot(world.ship.heading)
		if fwd < -0.02:
			backs += 1
			worst = minf(worst, fwd)
		if t > 0.5 and absf(now.length() - prev.length()) > 0.6:
			jumps += 1
			print("JUMP t=%.2f dr=%.2f vs=%.1f air=%s horiz=%.2f coll=%s" % [t, now.length() - prev.length(), world.ship.vertical_speed, world.ship.airborne, step.length(), str(world.ship.get_last_slide_collision().get_collider().get_path()) if world.ship.get_last_slide_collision() else "none"])
		prev = now
		t += 1.0 / 60.0
		var ship: Node3D = world.ship
		var surface: float = world.ocean.surface_at(ship.global_position).length()
		var lift: float = ship.global_position.length() - surface
		if ship.airborne:
			air += 1.0 / 60.0
		best = maxf(best, lift)
		if last > 0.0:
			rise = maxf(rise, absf(surface - last) * 60.0)
		last = surface
		bad = maxf(bad, world.ocean.badness_at(ship.global_position))
		peak = maxf(peak, ship.rise_peak)
		hmin = minf(hmin, surface - world.planet_radius)
		hmax = maxf(hmax, surface - world.planet_radius)
		if shot_pending and shots < 3:
			shot_pending = false
			await create_timer(0.15).timeout
			await still("%s_splash_%d" % [label, shots])
			shots += 1
	print("WAVES %s backwards_steps=%d worst=%.2f radial_jumps=%d" % [label, backs, worst, jumps])
	print("WAVES %s air=%.1fs (%.0f%%) highest=%.2f m splashes=%d speed=%.1f max_surface_rate=%.2f badness=%.1f bow_rate=%.1f rise_peak=%.2f sea=%.2f..%.2f" % [label, air, air / seconds * 100.0, best, splashes, world.ship.measured_speed, rise, bad, world.ship.max_bow_rate, peak, hmin, hmax])

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/ShipWavesProbe"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.clock.set_time(0.40, true)
	world.select_time("day")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.ship.splash.connect(_on_splash)
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1, 0, 1)
	var weather: Node = world.weather
	# Mar calmo: um ponto de mar aberto longe das tempestades (sem ilha na frente).
	var calm_point: Vector3 = weather.open_sea[0]
	for p in weather.open_sea:
		var clear := INF
		for st in weather.storms + weather.cyclones:
			clear = minf(clear, p.angle_to(st.center))
		if clear * world.planet_radius > 300.0:
			calm_point = p
			break
	# Contra o vento = de frente para as ondas (onde o barco sobe as faces mais rápido).
	put_ship(calm_point, -world.wind_at(calm_point * world.planet_radius))
	await create_timer(1.0).timeout
	await sail("calm", 15.0)
	for i in weather.movers.size():
		weather.targets[i] = weather.movers[i].center
	var storm: Node3D = weather.storms[0]
	storm.peak_badness = 4.0
	storm.cycle_phase = PI * 0.5 - storm.age * TAU / storm.cycle_period
	var centre: Vector3 = storm.center
	var side := centre.cross(Vector3.RIGHT).normalized()
	var start := centre.rotated(side, 30.0 / world.planet_radius)
	put_ship(start, -world.wind_at(start * world.planet_radius))
	await create_timer(1.0).timeout
	await sail("storm", 45.0)
	quit()
