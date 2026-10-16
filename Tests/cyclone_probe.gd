extends SceneTree

## Ciclone: de longe, perto, de baixo e dois quadros seguidos para ver o movimento.
## Uso: Godot.exe --path . --resolution 1280x720 --script res://Tests/cyclone_probe.gd
## Saída: Builds/CycloneProbe/*.jpg

var world: Node3D
var cam: Camera3D

func _initialize() -> void:
	call_deferred("run")

func still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://Builds/CycloneProbe/%s.jpg" % name), 0.85)

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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Builds/CycloneProbe"))
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
	var cyclone: Node3D = world.weather.cyclones[0]
	var centre: Vector3 = cyclone.center * world.planet_radius
	var ship_pos: Vector3 = world.ship.global_position
	print("CYCLONE count=%d distance=%.0f m" % [world.weather.cyclones.size(), ship_pos.distance_to(centre)])
	var up := ship_pos.normalized()
	var toward := (centre - ship_pos).slide(up).normalized()
	put_ship((centre - toward * 220.0).normalized(), toward)
	await create_timer(1.0).timeout
	await ship_shot("cyclone_far", Vector3(0.0, 4.0, 6.0), Vector3(0, 22.0, -80.0))
	put_ship((centre - toward * 90.0).normalized(), toward)
	await create_timer(1.0).timeout
	await ship_shot("cyclone_near", Vector3(-3.0, 3.0, 8.0), Vector3(0, 22.0, -40.0))
	await ship_shot("cyclone_near_b", Vector3(-3.0, 3.0, 8.0), Vector3(0, 22.0, -40.0), 30)
	put_ship((centre - toward * 40.0).normalized(), toward)
	await create_timer(1.0).timeout
	await ship_shot("cyclone_base", Vector3(-2.0, 2.5, 6.0), Vector3(0, 6.0, -30.0))
	await ship_shot("cyclone_up", Vector3(-2.0, 2.5, 6.0), Vector3(0, 45.0, -30.0))
	await ship_shot("cyclone_above", Vector3(0.0, 30.0, 10.0), Vector3(0, 0.0, -40.0))
	print("CYCLONE axis top offset=%s" % str(cyclone.axis_offset(1.0)))
	quit()
