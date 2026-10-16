extends SceneTree

## Marolas desenhadas no mar calmo (camera alta olhando o mar perto do barco).
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/sea_marks_probe.gd
## Saida: Builds/SeaMarksProbe/*.jpg

var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/SeaMarksProbe/%s.jpg" % name), 0.85)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/SeaMarksProbe"))
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
	var up := p
	var heading := up.cross(Vector3.UP).normalized()
	world.ship.heading = heading
	world.ship.global_transform = Transform3D(Basis(heading.cross(up).normalized(), up, -heading), up * (world.planet_radius + 0.3))
	world.ship.reset_physics_interpolation()
	var cam := Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	cam.make_current()
	for i in 3:
		for f in 40:
			var t: Transform3D = world.ship.global_transform
			# 0: de cima; 1 e 2: baixa, olhando o horizonte (silhuetas, como na referência).
			var eye := Vector3(0.0, 9.0, 14.0) if i == 0 else Vector3(0.0, 2.2, 8.0)
			var look := Vector3(0.0, 0.0, -10.0) if i == 0 else Vector3(0.0, 1.5, -60.0)
			cam.global_position = t * eye
			cam.look_at(t * look, t.basis.y)
			await process_frame
		await still("marks_%d" % i)
	var vals: Array = []
	var su: Vector3 = world.ship.global_position.normalized()
	var t1: Vector3 = su.cross(Vector3.RIGHT).normalized()
	var t2: Vector3 = su.cross(t1)
	for i in 400:
		vals.append(world.ocean.crest_at(world.ship.global_position + t1 * randf_range(-150, 150) + t2 * randf_range(-150, 150)))
	vals.sort()
	print("CREST p50=%.2f p90=%.2f p97=%.2f max=%.2f" % [vals[200], vals[360], vals[388], vals[399]])
	quit()
