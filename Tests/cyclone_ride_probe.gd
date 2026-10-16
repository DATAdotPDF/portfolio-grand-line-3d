extends SceneTree

## Passeio no ciclone com a câmera do jogo: captura, espiral, subida, teleporte e queda.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/cyclone_ride_probe.gd
## Saída: Builds/CycloneRideProbe/*.jpg

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/CycloneRideProbe/%s.jpg" % name), 0.85)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/CycloneRideProbe"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.clock.set_time(0.40, true)
	world.select_time("day")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.ship.controls_override = true
	world.ship.test_controls = Vector3(1, 0, 0)
	var weather: Node = world.weather
	var cyclone: Node3D = weather.cyclones[0]
	for i in weather.movers.size():
		weather.targets[i] = weather.movers[i].center
	# Fuga: a 35 m, proa para fora, turbo — tem que conseguir escapar.
	var c0: Vector3 = cyclone.center * world.planet_radius
	var away_dir := c0.normalized().cross(Vector3.FORWARD).normalized()
	var esc := (c0 + away_dir * 35.0).normalized()
	world.ship.heading = away_dir.slide(esc).normalized()
	world.ship.global_transform = Transform3D(Basis(world.ship.heading.cross(esc).normalized(), esc, -world.ship.heading), esc * (world.planet_radius + 0.3))
	world.ship.reset_physics_interpolation()
	world.ship.test_controls = Vector3(1, 0, 1)
	await create_timer(8.0).timeout
	print("PROBE escape distance_after_8s=%.0f m phase=%d" % [world.ship.global_position.distance_to(cyclone.center * world.planet_radius), weather.ride.phase])
	world.ship.test_controls = Vector3(1, 0, 0)
	# Barco a 90 m do ciclone, apontando para ele.
	var centre: Vector3 = cyclone.center * world.planet_radius
	var up := centre.normalized()
	var side := up.cross(Vector3.RIGHT).normalized()
	var start := (centre + side * 90.0).normalized()
	var heading: Vector3 = (centre - start * world.planet_radius).slide(start).normalized()
	world.ship.heading = heading
	world.ship.global_transform = Transform3D(Basis(heading.cross(start).normalized(), start, -heading), start * (world.planet_radius + 0.3))
	world.ship.reset_physics_interpolation()
	world.camera.snap_to_boat()
	await create_timer(1.5).timeout
	await still("1_approach")
	var phase_names := ["FREE", "SPIRAL", "LIFT", "DROP"]
	var shots := {}
	var last := -1
	var elapsed := 0.0
	var landed := false
	while elapsed < 60.0:
		await process_frame
		elapsed += 1.0 / 60.0
		var ride: Node = weather.ride
		if ride.phase != last:
			last = ride.phase
			print("PROBE t=%.1f phase=%s badness=%.2f gloom=%.2f" % [elapsed, phase_names[last], weather.badness, world.storm_gloom])
			shots[last] = elapsed
		if ride.phase == 1 and elapsed - shots[1] > 2.0 and not shots.has("s"):
			shots["s"] = true
			await still("2_spiral")
		if ride.phase == 2 and elapsed - shots[2] > 1.5 and not shots.has("l"):
			shots["l"] = true
			await still("3_lift")
		if ride.phase == 3 and elapsed - shots[3] > 1.0 and not shots.has("d"):
			shots["d"] = true
			await still("4_drop")
		if ride.phase == 0 and shots.has(3):
			landed = true
			await create_timer(1.0).timeout
			await still("5_landed")
			break
	print("PROBE landed=%s ship_enabled=%s cyclone_to_ship=%.0f m" % [landed, world.ship.enabled, world.ship.global_position.distance_to(cyclone.center * world.planet_radius)])
	quit()
