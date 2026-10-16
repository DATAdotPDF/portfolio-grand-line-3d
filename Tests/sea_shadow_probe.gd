extends SceneTree

## Silhuetas sob a água: força cada espécie (SeaShadows) e fotografa de cima.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/sea_shadow_probe.gd

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/SeaShadowProbe/%s.jpg" % name), 0.85)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/SeaShadowProbe"))
	world = (load("res://MainWorld.tscn") as PackedScene).instantiate()
	world.show_intro_on_start = false
	root.add_child(world)
	world.select_time("day")
	await create_timer(2.0).timeout
	world._start_sailing()
	world.hud.visible = false
	world.ship.controls_override = true
	world.ship.test_controls = Vector3.ZERO
	var weather: Node = world.weather
	var p: Vector3 = weather.open_sea[0]
	for q in weather.open_sea:
		var clear := INF
		for st in weather.storms + weather.cyclones:
			clear = minf(clear, q.angle_to(st.center))
		if clear * world.planet_radius > 300.0:
			p = q
			break
	var heading: Vector3 = p.cross(Vector3.UP).normalized()
	world.ship.heading = heading
	world.ship.global_transform = Transform3D(Basis(heading.cross(p).normalized(), p, -heading), p * (world.planet_radius + 0.3))
	world.ship.reset_physics_interpolation()
	var cam := Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	cam.make_current()
	var shadows: Node = world.sea_life.sea_shadows
	for species in shadows.SPECIES:
		for g in shadows.groups:
			shadows._free_group(g)
		shadows.groups.clear()
		await process_frame
		var g: Dictionary = shadows.spawn(species, world.ship.global_position + world.ship.heading * 20.0, world.ship.heading)
		g.age = float(g.fade) + 0.5
		for f in 30:
			var t: Transform3D = world.ship.global_transform
			cam.global_position = t * Vector3(0.0, 22.0, 10.0)
			cam.look_at(t * Vector3(0.0, 0.0, -20.0), t.basis.y)
			await process_frame
		await still("species_%s" % species)
	quit()
